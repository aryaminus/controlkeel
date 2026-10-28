## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.

## 2024-05-15 - Elixir String Split Allocation Overhead
**Learning:** Using `String.split(contents, "\n")` and then counting the length of the resulting list creates massive intermediate list allocations in memory for large files.
**Action:** Use `length(:binary.matches(contents, "\n")) + 1` to count lines efficiently without list allocation overhead.
