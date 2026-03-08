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

## Elixir: structure-aware `j`/`k` inside a `do_block`

When the cursor is inside any named child of a `do_block` (e.g. a `use`,
`alias`, `import`, module attribute, or `def`/`defp` form), `j` and `k`
navigate **between the top-level forms** of that block rather than walking
raw AST children or parent pointers.

### Navigation behaviour

Given the following Elixir source:

```elixir
defmodule MyApp do
  use SomeLib
  alias MyApp.Helper
  @moduledoc "Hello"
  def greet(name), do: "Hi, #{name}!"
  defp helper, do: :ok
end
```

When point is anywhere inside one of the top-level forms in the `do_block`
(`use SomeLib`, `alias MyApp.Helper`, `@moduledoc …`, `def greet …`,
`defp helper …`):

- **`j`** moves to the **next** top-level form in the `do_block`.  At the
  last form, a message is shown instead.
- **`k`** moves to the **previous** top-level form in the `do_block`.  At
  the first form, point jumps back to the `do_block` node itself (resuming
  the `defmodule` navigation sequence).
- **`h` / `l`** (prev/next sibling) are unchanged.

### Underlying AST

```
(do_block
  (call)             ;; use SomeLib
  (call)             ;; alias MyApp.Helper
  (module_attribute) ;; @moduledoc "Hello"
  (call)             ;; def greet …
  (call))            ;; defp helper …
```

Note: `def`/`defp` and other macro forms at module level are treated as
leaf nodes — `j`/`k` navigates between them as siblings without descending
into their bodies.

## Elixir: structure-aware `j`/`k` for first-level `do_block` forms

When the cursor is inside a `alias`, `use`, or `import` call, or a
`module_attribute`, that is a direct child of a module's `do_block`, `j`
and `k` navigate the **semantic parts** of that form rather than jumping
to the next sibling.

### Navigation behaviour for `alias`/`use`/`import`

Given the following Elixir source:

```elixir
defmodule MyApp do
  use SomeLib
  alias MyApp.Helper
  import MyApp.Utils
  @moduledoc "Hello"
  def greet(name), do: "Hi, #{name}!"
  defp helper, do: :ok
end
```

When point is on `use SomeLib`:

- **`j`** steps forward: `use` identifier → `SomeLib` argument.
  At the argument (last part), `j` advances to the **next** top-level form.
- **`k`** steps backward: `SomeLib` → `use` identifier.
  At the identifier (first part), `k` moves to the **previous** top-level
  form in the `do_block` (or the `do_block` node itself at the first form).

The same pattern applies to `alias` and `import`.

### Navigation behaviour for `module_attribute`

When point is on `@moduledoc "Hello"`:

- **`j`** steps forward: attribute name (`moduledoc`) → attribute value (`"Hello"`).
  At the value (last part), `j` advances to the next top-level form.
- **`k`** steps backward through the parts, then to the previous form.

### Underlying AST

```
(call              ;; use SomeLib
  (identifier)     ;; "use" keyword           — part 1
  (arguments
    (alias)))      ;; SomeLib                 — part 2

(module_attribute  ;; @moduledoc "Hello"
  (identifier)     ;; "moduledoc" name        — part 1
  (string))        ;; "Hello" value           — part 2
```

`def`/`defp` and other macro forms have no parts — they are leaf nodes at
this navigation level.  `j`/`k` continues to navigate between sibling forms
in the `do_block`.

## License

Unlicense (public domain). See LICENSE.
