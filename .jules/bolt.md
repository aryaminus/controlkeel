## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-10-24 - Elixir Unique Count Optimization
**Learning:** In Elixir, using length(Enum.uniq(list)) creates an intermediate list allocation which adds overhead.
**Action:** Use MapSet.new(list) |> MapSet.size() instead for better performance when only the count of unique items is needed.
