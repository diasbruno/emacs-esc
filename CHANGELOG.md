# Changelog

## Unreleased
- Elixir: `j`/`k` navigate through named top-level forms within a `do_block`
  (e.g. `use`, `alias`, `import`, module attributes, `def`/`defp`).
  Pressing `k` at the first form returns point to the `do_block` node,
  resuming the existing `defmodule` navigation sequence.

## 0.1.0 - 2026-02-28
- Repository bootstrap (README, license, initial package skeleton).