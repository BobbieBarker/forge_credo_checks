---
type: adr
id: 16
title: Stream Pass-Through Data, Source to Sink
status: accepted
date: 2026-05-08
tags: [elixir, streaming, memory, performance, ecto, s3]
description: "When data is passing through to a downstream sink (export, upload, relay), stream source → transform → sink with bounded O(1) memory. Buffer only when the server genuinely needs the complete payload to do its job. Temp files are buffering with extra failure modes."
---
# ADR-016: Stream Pass-Through Data, Source to Sink

Stream pass-through data. Buffer only what the server must inspect. Temp files are buffering with disk indirection added.

## Context

- A server that buffers a payload it is only relaying pays an O(N) memory cost per request for work it is not doing. Ten concurrent 200 MB exports take 2 GB of process heap.
- The decision rule is structural: ask whether the server needs the complete payload to do its job. If it is relaying, transforming, or assembling on its way to a sink, the answer is no and the implementation is a stream.
- Elixir/Erlang provides streaming primitives at every layer: `Repo.stream/2` (DB cursor), `ExAws.S3.stream!/2` and `upload/4` (S3 source/sink), `Zstream` (streaming ZIP), `NimbleCSV.dump_to_stream/1` (CSV).
- Temp files do not save memory. The final `File.read!` brings the whole binary back into the process heap before the upstream call.

## Consequence

- Pass-through queries use `Repo.stream/2` inside a transaction; results pipe to the sink via `Stream.map/2` and friends.
- `Repo.all/2` is reserved for queries whose results genuinely fit in memory and that the server needs to hold (computing a summary across the set, returning a paginated response).
- `File.write!`/`File.read!` against temp paths does not appear in data-flow code.
- Data-flow modules document their memory ceiling: `Memory = (buffer_size × concurrent_streams) + fixed_overhead`.

## Rules

- Stream pass-through data source-to-sink. When the server is relaying, transforming, or assembling, write a stream pipeline from source through transform to sink.
- Buffer only when the server genuinely needs the complete payload (parsing structure, computing aggregates over the whole input). Document the size limit when buffering.
- Do not use temp files for data flow. They are buffering with disk-full failures, leaked files on crash, and race conditions on file naming on top.
- When a third-party API forces a file path, wrap the call in a small adapter that owns its temp file lifecycle. Do not propagate the pattern outward.

## DO

```elixir
# lib/my_app/reports.ex - DB cursor → CSV row encoder → S3 multipart upload
defmodule MyApp.Reports do
  alias MyApp.Repo

  def export_to_s3(org_id, bucket, key) do
    Repo.transact(fn ->
      Record
      |> Record.by_organization(org_id)
      |> Repo.stream(max_rows: 500)
      |> Stream.map(&to_csv_row/1)
      |> ExAws.S3.upload(bucket, key)
      |> ExAws.request!(ex_aws_config())
      |> then(&{:ok, &1})
    end)
  end
end
```

```elixir
# lib/my_app/backups.ex - Zstream → S3 multipart, no temp file
defmodule MyApp.Backups do
  def archive_to_s3(snapshots, bucket, key) do
    snapshots
    |> Stream.map(&{&1.relative_path, &1.contents_stream})
    |> Zstream.zip()
    |> ExAws.S3.upload(bucket, key)
    |> ExAws.request!(ex_aws_config())
  end
end
```

## DON'T

```elixir
# Why wrong: every record in a list (O(N) heap), full CSV in a single
# binary (O(N) heap again), temp file write, file read back, upload.
# Memory peaks at ~2x payload, multiplied by concurrent exports. Temp file
# is one failure mode (disk full, abandoned files, race on unique-integer
# name) on top of another.
defmodule MyApp.Reports do
  def export_to_s3(org_id, bucket, key) do
    records = Repo.all(Record.by_organization(org_id))
    csv = records |> Enum.map(&to_csv_row/1) |> Enum.join("\n")
    tmp_path = Path.join(System.tmp_dir!(), "export-#{System.unique_integer()}.csv")
    File.write!(tmp_path, csv)
    ExAws.S3.put_object(bucket, key, File.read!(tmp_path)) |> ExAws.request!()
  end
end
```

```elixir
# Why wrong: temp file does not save memory - the final File.read! brings
# the whole archive back into process heap before upload. Disk usage
# scales with archive size; a crash mid-way leaks the temp file.
defmodule MyApp.Backups do
  def archive_to_s3(snapshots, bucket, key) do
    tmp = Path.join(System.tmp_dir!(), "archive-#{System.unique_integer()}.zip")

    {:ok, zip_handle} = :zip.zip_open(tmp, [:cooked])

    Enum.each(snapshots, fn snap ->
      :zip.zip_add(zip_handle, snap.relative_path, snap.contents)
    end)

    :zip.zip_close(zip_handle)

    ExAws.S3.put_object(bucket, key, File.read!(tmp))
    |> ExAws.request!(ex_aws_config())

    File.rm(tmp)
  end
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
