## 2024-08-14 - Optimize Elixir List Counting Operations
**Learning:** Elixir's `length(Enum.filter(...))` and `Enum.map(...) |> Enum.uniq() |> length()` cause unnecessary intermediate list allocations, which can add overhead on large collections.
**Action:** Use `Enum.count/2` instead of `length(Enum.filter/2)`, and use `MapSet.new/2 |> MapSet.size()` instead of `Enum.map/2 |> Enum.uniq/1 |> length/1` to compute unique counts efficiently without intermediate lists.
