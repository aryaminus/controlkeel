## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2026-08-20 - Multi-Metric Accumulation in Elixir
**Learning:** Performing multiple independent `Enum.count/2` or `Enum.filter/2` operations on the same list degrades CPU performance by repeating list traversals, even if it avoids intermediate list allocations compared to chaining.
**Action:** When counting multiple attributes from a single collection, use a single-pass `Enum.reduce/3` to accumulate all metrics concurrently.
