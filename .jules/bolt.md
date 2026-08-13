## 2026-08-13 - Elixir List Allocation Overhead
**Learning:** Using `length(Enum.filter/2)` and `Enum.map/2 |> Enum.uniq/1 |> length/1` causes unnecessary intermediate list allocations in Elixir, adding performance overhead compared to more direct counting methods.
**Action:** Always prefer `Enum.count/2` over `length(Enum.filter/2)` and use `MapSet.new/2 |> MapSet.size()` instead of `Enum.map/2 |> Enum.uniq/1 |> length/1` when counting unique items to avoid creating intermediate list allocations.
