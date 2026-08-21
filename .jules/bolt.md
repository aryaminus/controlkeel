## 2025-02-18 - Elixir list operations optimization
**Learning:** Chaining `Enum.map |> Enum.uniq |> length` and `Enum.filter |> length` creates unnecessary intermediate list allocations, adding performance overhead.
**Action:** Prefer `Enum.count/2` over `length(Enum.filter/2)`, and `MapSet.new/2 |> MapSet.size()` over `Enum.map/2 |> Enum.uniq/1 |> length/1` to avoid intermediate list allocations and improve performance overhead.
