## 2024-08-11 - Optimize List Allocations in Elixir
**Learning:** Using `length(Enum.filter(...))` or `enumerable |> Enum.map(...) |> Enum.uniq() |> length()` in Elixir creates unnecessary intermediate list allocations and traverses the list multiple times, which adds performance overhead.
**Action:** When counting filtered items, prefer `Enum.count/2` over `length(Enum.filter/2)`. When counting unique items after mapping, prefer `enumerable |> MapSet.new(fun) |> MapSet.size()` to avoid intermediate lists and improve performance.
