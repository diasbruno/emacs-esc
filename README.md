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

Once enabled, the buffer becomes **read-only** and the following keys navigate
the syntax tree:

| Key | Action                        |
|-----|-------------------------------|
| `n` | Move forward through the AST  |
| `p` | Move backward through the AST |

And the following keys perform **editing operations** on the current context:

| Key | Action                                        |
|-----|-----------------------------------------------|
| `a` | Add a method (`def`) after the current form   |
| `A` | Add a module attribute (`@attr`) after the current form |
| `i` | Add an internal module (`defmodule`) after the current form |
| `d` | Delete the current form                       |
| `J` | Move the current form down (swap with next sibling)    |
| `K` | Move the current form up (swap with previous sibling)  |

`n` navigates forward: into the first child when at a leaf-like position, or
to the next semantic part / sibling within structured constructs.
`p` navigates backward: up to the parent, or to the previous semantic part /
sibling.

If the requested relative node does not exist (e.g. no parent, no sibling),
the command does nothing and shows a brief message in the echo area.

## Elixir: structure-aware `n`/`p` for `defmodule`

In Elixir's Tree-sitter grammar, constructs such as `defmodule` are encoded as
`(call ...)` nodes whose semantic meaning is determined by the `(identifier)`
child.  Raw first-child / parent traversal therefore does not correspond to
meaningful Elixir structure.

When `esc-mode` is active in an Elixir buffer (`elixir-ts-mode`) and the cursor
is anywhere inside a `defmodule` call, `n` and `p` navigate the **semantic
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

- **`n`** steps forward through parts 1 → 2 → 3 → 4.  At the last part,
  a message is shown instead.
- **`p`** steps backward through parts 4 → 3 → 2 → 1.  At part 1 (or when
  the cursor is outside all known parts), it falls back to the generic parent
  navigation behaviour from Step 1.

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

## Elixir: structure-aware `n`/`p` inside a `do_block`

When the cursor is inside any named child of a `do_block` (e.g. a `use`,
`alias`, `import`, module attribute, or `def`/`defp` form), `n` and `p`
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

- **`n`** moves to the **next** top-level form in the `do_block`.  At the
  last form, a message is shown instead.
- **`p`** moves to the **previous** top-level form in the `do_block`.  At
  the first form, point jumps back to the `do_block` node itself (resuming
  the `defmodule` navigation sequence).

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
leaf nodes — `n`/`p` navigates between them as siblings without descending
into their bodies.

## Elixir: structure-aware `n`/`p` for first-level `do_block` forms

When the cursor is inside a `alias`, `use`, or `import` call, or a
`module_attribute`, that is a direct child of a module's `do_block`, `n`
and `p` navigate the **semantic parts** of that form rather than jumping
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

- **`n`** steps forward: `use` identifier → `SomeLib` argument.
  At the argument (last part), `n` advances to the **next** top-level form.
- **`p`** steps backward: `SomeLib` → `use` identifier.
  At the identifier (first part), `p` moves to the **previous** top-level
  form in the `do_block` (or the `do_block` node itself at the first form).

The same pattern applies to `alias` and `import`.

### Navigation behaviour for `module_attribute`

When point is on `@moduledoc "Hello"`:

- **`n`** steps forward: attribute name (`moduledoc`) → attribute value (`"Hello"`).
  At the value (last part), `n` advances to the next top-level form.
- **`p`** steps backward through the parts, then to the previous form.

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
this navigation level.  `n`/`p` continues to navigate between sibling forms
in the `do_block`.

## Elixir: module context editing operations

When `esc-mode` is active in an Elixir buffer, the editing keys (`a`, `A`, `i`,
`d`, `J`, `K`) operate on the **current form** within a module's `do_block`.
The current form is the direct named child of the module-level `do_block` that
contains point.  This works wherever point is inside that form — at any depth
of nesting within it.

### Add method (`a`)

Inserts a `def` template immediately after the current form and places point
on the `function_name` placeholder:

```elixir
def function_name do
  
end
```

### Add internal module (`i`)

Inserts a `defmodule` template immediately after the current form and places
point on the `ModuleName` placeholder:

```elixir
defmodule ModuleName do
end
```

### Add module attribute (`A`)

Inserts an `@attribute_name value` template immediately after the current form
and places point on the `attribute_name` placeholder.

### Delete form (`d`)

Removes the current form (including its trailing newline) from the `do_block`.
Point moves to the next sibling if one exists, or to the previous sibling
otherwise.

### Move form up/down (`K` / `J`)

Swaps the current form with its previous (`K`) or next (`J`) named sibling in
the `do_block`, preserving the whitespace between them.  Point follows the
current form to its new position.

## License

Unlicense (public domain). See LICENSE.
