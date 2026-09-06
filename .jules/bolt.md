## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2026-08-19 - Elixir Group By Allocation Overhead
**Learning:** Chaining `Enum.group_by/2` into `Enum.into(%{}, fn {k, v} -> {k, length(v)} end)` allocates memory for intermediate lists containing all grouped elements, adding hidden memory overhead.
**Action:** Use `Enum.frequencies_by/2` which increments integer counts during a single traversal without allocating intermediate lists.
