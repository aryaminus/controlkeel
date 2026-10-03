## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2026-10-03 - Single Pass List Optimization
**Learning:** Using Enum.count multiple times on the same list causes multiple iterations.
**Action:** Replace multiple Enum.count calls with a single Enum.reduce to accumulate multiple counts simultaneously.
