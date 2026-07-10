---
type: adr
id: 19
title: Design-to-Code Workflow
status: accepted
date: 2026-05-08
tags: [forge, design, ui, figma, workflow, mcp]
description: "UI implementation reads the approved design via the design-extraction MCP tool, translates to the project's framework and component library, and verifies visually with a side-by-side screenshot comparison. For content-heavy pages, source text from the ticket's content map, not the design's mock copy."
---
# 019: Design-to-Code Workflow

UI implementation is design-first. Read the approved design via MCP, translate to the project's framework and component library, verify visually before opening the PR.

## Context

- LLMs and humans implementing UI from prose alone produce something that "works" but does not match the design's spacing, component variants, or design tokens.
- The design tool (Figma) plus an extraction MCP makes the design machine-readable: reference code (React + Tailwind) plus screenshot plus contextual hints.
- Reference code is a starting point for translation, not code to ship; the project's framework (LiveView HEEx) and component library (DaisyUI / shadcn-live / custom) is what the implementation actually uses.
- Designs typically contain mock text. Real copy lives in a content map attached to the ticket; never source copy from the design.

## Consequence

- The first action on a UX ticket is calling the design-extraction MCP tool, not reading the prose.
- The reference output is translated to the project's framework and component library.
- Visual QA happens before the PR is opened. The PR body includes the comparison.
- Content-heavy pages source text from the ticket's content map.

## Rules

- Before writing UI code, fetch the approved design via the design-extraction MCP tool (`mcp.design.get_design_context`) to receive reference code + screenshot + hints. Reading prose without the design produces UI that matches the prose but not the spec.
- Translate the reference code (React + Tailwind) to the project's framework (LiveView HEEx) and component library (`<.card>`, `<.button>`, etc.). Pasting React `className` into HEEx is a category error.
- After implementation, take a browser screenshot and compare side-by-side with the design screenshot. Note divergences in the PR body. Fix divergences before requesting review.
- For content-heavy pages (legal, pricing, marketing landing, docs), source text from the content map attached to the ticket. Never use the design's mock text in production UI.
- `get_design_context` requires a Figma Design URL (`figma.com/design/...`), not a Make URL. If the ticket has the wrong form, ask before guessing.

## DO

```elixir
# After reading the design via MCP, translate to project framework + components
def render(assigns) do
  ~H"""
  <.card>
    <.card_header>
      <.card_title>Account Settings</.card_title>
      <.card_description>Manage account preferences and security.</.card_description>
    </.card_header>

    <.card_content>
      <.form for={@form} phx-change="update_form">
        <.input field={@form[:email]} label="Email" />
        <.input field={@form[:notifications]} type="checkbox" label="Email notifications" />
      </.form>
    </.card_content>

    <.card_footer>
      <.button type="submit" phx-click="save">Save changes</.button>
    </.card_footer>
  </.card>
  """
end
```

## DON'T

```elixir
# Why wrong: pasted React reference into HEEx with className and div soup.
def render(assigns) do
  ~H"""
  <div className="rounded-lg border bg-card text-card-foreground shadow-sm">
    <div className="flex flex-col space-y-1.5 p-6">
      <h3 className="text-2xl font-semibold leading-none tracking-tight">Account Settings</h3>
    </div>
    <div className="p-6 pt-0">
      <input type="email" />
    </div>
  </div>
  """
end
```

```
# Wrong workflow:
1. Read the ticket's prose.
2. Build a settings page from primitives.
3. PR review reveals layout, component variants, and notes panel are wrong.
4. Rework.
```

## Applies To
- `apps/*/lib/**/live/**/*.ex`
- `apps/*/lib/**/components/**/*.ex`
- `lib/**/live/**/*.ex`
- `lib/**/components/**/*.ex`
