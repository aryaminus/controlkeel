## 2024-05-24 - Elixir Enum optimization to avoid intermediate allocations
**Learning:** In Elixir, piping `Enum.group_by/2` into `Enum.map/2` (with `length/1`) or piping `Enum.map/2` (with `Enum.reject/2`) into `Enum.frequencies/1` creates intermediate lists that increase garbage collection pressure.
**Action:** Use `Enum.frequencies_by/2` natively. When mimicking `Enum.reject(&is_nil/1)` after `Enum.map/2`, use `Enum.frequencies_by/2` followed by `Map.delete(nil)` to retain exact behavior without intermediate allocations.
