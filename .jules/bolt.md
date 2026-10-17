## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-05-24 - Elixir String.split Overhead
**Learning:** Counting lines with `length(String.split(contents, "\n", trim: false))` creates a massive intermediate list in memory for large files.
**Action:** Use `length(:binary.matches(contents, "\n")) + 1` to count lines without list allocation.
