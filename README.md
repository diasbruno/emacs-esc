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

### Elixir: structure-aware `j`/`k` for `defmodule`

In Elixir buffers (`elixir-ts-mode`), when point is anywhere inside a
`defmodule` call, `j` and `k` navigate the semantic parts of the declaration
rather than the raw AST first-child / parent:

| Part | Description |
|------|-------------|
| `identifier` | The `defmodule` keyword itself |
| `alias` | The module name (e.g. `A`) |
| `do_block` | The module body |
| first child of `do_block` | First form inside the body (if present) |

- `j` advances forward through these parts.
- `k` moves backward; when already at the first part it falls back to the
  generic parent move.
- `h` and `l` (prev/next sibling) are unchanged.

This pattern is designed to be extended to other `call` forms in future
steps.

## License

Unlicense (public domain). See LICENSE.
