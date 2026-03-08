# esc (Emacs Structured Coding)

`esc-mode` is an Emacs minor mode for structured code navigation and editing using Emacs built-in Tree-sitter (treesit).

## Status

Early development.

## Installation

(TODO)

## Usage

Enable `esc-mode` in any buffer that already has a Tree-sitter parser active
(e.g. a `*-ts-mode` buffer).  If Tree-sitter is not available for the buffer,
enabling the mode will be refused with a friendly message.

```emacs-lisp
M-x esc-mode
```

Once enabled, use the following keys to navigate the syntax tree:

| Key | Action                        |
|-----|-------------------------------|
| `h` | Move to previous sibling node |
| `l` | Move to next sibling node     |
| `j` | Move down into first child    |
| `k` | Move up to parent node        |

If the requested relative node does not exist (e.g. no parent, no sibling),
the command does nothing and shows a brief message in the echo area.

## Elixir: structure-aware `j`/`k` for `defmodule`

In Elixir's Tree-sitter grammar, constructs such as `defmodule` are encoded as
`(call ...)` nodes whose semantic meaning is determined by the `(identifier)`
child.  Raw first-child / parent traversal therefore does not correspond to
meaningful Elixir structure.

When `esc-mode` is active in an Elixir buffer (`elixir-ts-mode`) and the cursor
is anywhere inside a `defmodule` call, `j` and `k` navigate the **semantic
parts** of that call rather than the raw AST children.

### Navigable parts (in order)

Given the following Elixir source:

```elixir
defmodule MyApp.Greeter do
  def hello(name), do: "Hello, #{name}!"
end
```

The four navigable parts are:

| # | Part | Description |
|---|------|-------------|
| 1 | `defmodule` identifier | The keyword itself |
| 2 | `MyApp.Greeter` (alias) | The module name inside `arguments` |
| 3 | `do_block` | The entire `do … end` body |
| 4 | First form in `do_block` | First expression inside the block (if any) |

- **`j`** steps forward through parts 1 → 2 → 3 → 4.  At the last part,
  a message is shown instead.
- **`k`** steps backward through parts 4 → 3 → 2 → 1.  At part 1 (or when
  the cursor is outside all known parts), it falls back to the generic parent
  navigation behaviour from Step 1.
- **`h` / `l`** (prev/next sibling) are unchanged.

### Underlying AST

The tree shape targeted by this feature:

```
(call
  (identifier)          ;; "defmodule" keyword       — part 1
  (arguments
    (alias))            ;; module name e.g. MyApp.Greeter — part 2
  (do_block             ;; do … end block            — part 3
    <first-form> ...))  ;; first expression          — part 4
```

This pattern generalises to other Elixir `call` forms in future steps.

## License

Unlicense (public domain). See LICENSE.
