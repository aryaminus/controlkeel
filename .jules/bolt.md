## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-05-18 - Single-pass Enum.reduce over Enum.count
**Learning:** When counting multiple conditions from the same Elixir list, making multiple passes with Enum.count/2 is inefficient in both memory and CPU time.
**Action:** Use a single-pass Enum.reduce/3 to accumulate multiple counts simultaneously.
