## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2023-11-20 - Map grouping overhead
**Learning:** `Enum.group_by(mapper) |> Enum.reject(nil) |> Enum.into(%{}, count)` creates intermediate lists for all matched values.
**Action:** Use `Enum.frequencies_by(mapper) |> Map.delete(nil)` for faster processing and lower memory allocation.
