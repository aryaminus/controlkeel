## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-05-18 - Avoid Multiple Passes with Enum.count
**Learning:** Using chained `Enum.filter` and multiple `Enum.count` calls to extract various counters from a single list creates unnecessary intermediate list allocations and requires O(N) traversals per check, putting pressure on GC in tight Elixir loops like observability.
**Action:** Use a single-pass `Enum.reduce/3` to accumulate multiple counts simultaneously within the same iteration to optimize CPU time and memory allocations.
