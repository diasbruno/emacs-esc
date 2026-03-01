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
| `?` | Open node inspector           |

If the requested relative node does not exist (e.g. no parent, no sibling),
the command does nothing and shows a brief message in the echo area.

## Node Inspector

Press `?` in any `esc-mode` buffer to open the `*esc-nodes*` inspector.  It
shows all Tree-sitter nodes relevant to the current cursor position:

- **Current** – the node directly under point
- **Parent** – immediate parent of the current node
- **Ancestors** – chain from the immediate parent up to the root
- **Children** – all first-level children of the current node
- **Siblings** – previous and next sibling nodes

Each entry shows:
- Node type
- Whether the node is named or anonymous
- Source range (start–end positions)
- A short text preview (up to 60 characters)

### Inspector keybindings

| Key   | Action                                         |
|-------|------------------------------------------------|
| `RET` | Jump to the node in the source buffer          |
| `g`   | Refresh the inspector at the current position  |
| `q`   | Quit (close) the inspector window              |

The inspector buffer is read-only; no editing side-effects occur.

## License

Unlicense (public domain). See LICENSE.
