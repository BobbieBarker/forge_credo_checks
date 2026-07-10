---
type: adr
id: 6
title: Use GenStage for Producer-Consumer Pipelines
status: accepted
date: 2026-04-29
tags: [elixir, otp, genserver, backpressure, genstage, broadway, flow]
description: When a producer can outpace a consumer, use GenStage, Flow, or Broadway. Naked cast between processes provides no flow control and lets the consumer mailbox grow unboundedly.
---
# ADR-006: Use GenStage for Producer-Consumer Pipelines

When one process produces work faster than another consumes it, use GenStage, Flow, or Broadway. Do not build pipelines on naked `cast`.

## Context

- A producer that fires `GenServer.cast/2` at a slower consumer has no way to know it should slow down. The consumer's mailbox grows unboundedly.
- Mailbox growth is a process resource: GC pauses scale with mailbox size, `process_info` degrades against long mailboxes (OTP issues #5481, #6494), and the node eventually OOMs.
- GenStage is the OTP primitive for demand-driven flow control: the consumer asks for N events, the producer sends exactly N. The mailbox cannot grow beyond demand in flight.
- Flow and Broadway add concurrency, batching, partitioning, and ack on top of GenStage. The flow-control mechanism is the same.

## Consequence

- Producer-consumer pipelines use GenStage, Flow, or Broadway. Naked `cast` between processes does not appear in this shape.
- Mailbox growth is treated as a system signal: the response is structural back-pressure, not faster processing.
- Servers with no producer-consumer shape do not need GenStage. The rule applies when its condition applies.

## Rules

- If the problem has the shape "process A produces, process B handles, A can outpace B", use GenStage / Flow / Broadway.
- Configure consumer demand explicitly: `subscribe_to: [{Producer, max_demand: N}]`. The producer responds to `handle_demand(demand, state)` and returns at most `demand` events.
- For external sources (Kafka, SQS, RabbitMQ, AMQP), prefer Broadway. For partitioned in-process pipelines, prefer Flow. Reach for raw GenStage when neither library fits.

## DO

```elixir
# lib/my_app/ingest/producer.ex
defmodule MyApp.Ingest.Producer do
  use GenStage

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_), do: {:producer, %{}}

  def handle_demand(demand, state) do
    events = pull_events(demand)
    {:noreply, events, state}
  end
end
```

```elixir
# lib/my_app/ingest/consumer.ex
defmodule MyApp.Ingest.Consumer do
  use GenStage

  def start_link(opts), do: GenStage.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_) do
    {:consumer, %{}, subscribe_to: [{MyApp.Ingest.Producer, max_demand: 10}]}
  end

  def handle_events(events, _from, state) do
    Enum.each(events, &process_event/1)
    {:noreply, [], state}
  end
end
```

## DON'T

```elixir
# Why wrong: every publish call succeeds immediately. The consumer has no
# way to push back. Under sustained load, the mailbox grows without bound,
# GC pauses on the consumer scale with it, and the node eventually runs out
# of memory.
defmodule MyApp.Ingest do
  def publish(event), do: GenServer.cast(MyApp.Ingest.Server, {:event, event})
end

defmodule MyApp.Ingest.Server do
  use GenServer

  def handle_cast({:event, event}, state) do
    {:noreply, Impl.ingest(state, event)}
  end
end
```

## Applies To
- `lib/**/{producer,consumer,producer_consumer,broadway}*.ex`
- `lib/**/*_pipeline.ex`
- `apps/*/lib/**/{producer,consumer,producer_consumer,broadway}*.ex`
- `apps/*/lib/**/*_pipeline.ex`
