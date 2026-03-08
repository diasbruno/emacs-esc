# Changelog

## Unreleased
- Elixir: `n`/`p` navigate between expressions inside `def`/`defp`/`defmacro`/`defmacrop`
  function bodies.  When the cursor is anywhere inside a function body after
  clicking into one, `n` moves to the next expression in the body and `p` moves
  to the previous one.  At the first expression, `p` returns point to the
  `do_block` node, resuming upward navigation through the enclosing structure.
- Elixir: `j`/`k` navigate through named top-level forms within a `do_block`
  (e.g. `use`, `alias`, `import`, module attributes, `def`/`defp`).
  Pressing `k` at the first form returns point to the `do_block` node,
  resuming the existing `defmodule` navigation sequence.
- Elixir: `j`/`k` navigate into the semantic parts of `alias`, `use`, and
  `import` call nodes at module level (identifier → first argument).
  At the last part, `j` advances to the next sibling in the `do_block`;
  at the first part, `k` moves to the previous sibling (or the `do_block`).
- Elixir: `j`/`k` navigate into the semantic parts of `module_attribute`
  nodes at module level (attribute name → value).
  At the last part, `j` advances to the next sibling in the `do_block`;
  at the first part, `k` moves to the previous sibling (or the `do_block`).
- Elixir: `def`/`defp` and other macro forms at module level are treated as
  leaf nodes; `j`/`k` navigates between siblings without entering their bodies.

## 0.1.0 - 2026-02-28
- Repository bootstrap (README, license, initial package skeleton).