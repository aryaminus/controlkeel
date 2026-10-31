## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.

## 2024-05-24 - Elixir String Line Counting Overhead
**Learning:** Using `length(String.split(contents, "\n", trim: false))` to count lines allocates a massive intermediate list in memory for large files, causing unnecessary GC pressure.
**Action:** Use `length(:binary.matches(contents, "\n")) + 1` to efficiently count lines by just searching for newline characters without intermediate allocations.
