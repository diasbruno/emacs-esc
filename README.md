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

## License

Unlicense (public domain). See LICENSE.
