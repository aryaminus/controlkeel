## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.

## 2026-11-01 - Elixir String.split Overhead
**Learning:** Counting lines with `length(String.split(contents, "\n", trim: false))` creates a massive intermediate list in memory for large files.
**Action:** Use `length(:binary.matches(contents, "\n")) + 1` to count lines without list allocation.

## 2024-05-15 - Elixir Group By Transform Allocation
**Learning:** Using `Enum.group_by/2 |> Enum.map/2 |> Map.new()` allocates intermediate lists of full structs which are then mapped over, causing extra memory allocation and GC pressure.
**Action:** Use `Enum.group_by/3` directly (which accepts a value-mapping function) to build the desired grouped structure in a single pass without allocating lists of intermediate full structs.
