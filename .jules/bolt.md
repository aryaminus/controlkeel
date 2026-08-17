## 2025-02-18 - [Optimize Elixir list allocations]
**Learning:** Chaining `Enum.filter` with `length`, or `Enum.map` with `Enum.uniq` and `length`, creates unnecessary intermediate lists which adds memory overhead in Elixir.
**Action:** Use `Enum.count/2` instead of `length(Enum.filter/2)`, and `MapSet.new/2 |> MapSet.size()` instead of `Enum.map/2 |> Enum.uniq/1 |> length/1` to minimize allocations.
