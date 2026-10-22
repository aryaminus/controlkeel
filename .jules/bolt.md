## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-05-24 - [Efficient Line Counting in Elixir]
**Learning:** Using `length(String.split(contents, "\n", trim: false))` to count lines allocates a new string for every line, causing massive memory spikes on large files.
**Action:** Use `length(:binary.matches(contents, "\n")) + 1` to count lines directly from the binary without allocating intermediate string lists.
