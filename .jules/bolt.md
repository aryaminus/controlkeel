## 2024-08-05 - Elixir Map Creation Optimization
**Learning:** Replaced `Enum.into(..., %{}, fn)` with `Map.new(..., fn)`. `Map.new/2` is generally faster and more idiomatic for creating maps from enumerables in Elixir.
**Action:** Default to `Map.new/2` when building maps from enumerables with transformations.
