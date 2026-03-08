# Changelog

## Unreleased
- Elixir: `a` inserts a `def` template after the current module-level form and
  places point on the function name placeholder.
- Elixir: `A` inserts an `@attribute_name value` template after the current
  module-level form and places point on the attribute name placeholder.
- Elixir: `i` inserts a `defmodule` template after the current module-level
  form and places point on the module name placeholder.
- Elixir: `d` deletes the current module-level form (and its trailing newline).
  Point moves to the next sibling, or to the previous sibling if none exists.
- Elixir: `J`/`K` swap the current module-level form with its next/previous
  named sibling in the `do_block`, preserving inter-form whitespace.
- Editing handler registry added to `esc-mode`: `esc-register-edit-handler`
  registers a language-specific editing handler; `esc-edit-handlers` is the
  backing alist.  Handlers receive an operation symbol (`add-method',
  `add-module', `add-attribute', `move-up', `move-down', `delete').
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