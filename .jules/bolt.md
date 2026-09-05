## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2026-08-19 - Elixir List Allocation Overhead - frequencies_by
**Learning:** Chaining `Enum.group_by/2` and then transforming the grouped values into counts with `length/1` forces unnecessary intermediate list allocations in Elixir, adding hidden overhead, particularly when grouping large collections.
**Action:** Use `Enum.frequencies_by/2` which computes the frequency map directly without allocating intermediate lists.
