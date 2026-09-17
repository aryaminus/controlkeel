## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2026-09-17 - Optimize map counting by field
**Learning:** Using `Enum.group_by/2` followed by `Enum.map/2` with `length/1` allocates large intermediate lists and puts pressure on the garbage collector.
**Action:** Use `Enum.frequencies_by/2` to compute frequencies without building large lists, which is more memory efficient and reduces GC overhead.
