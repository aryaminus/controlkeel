## 2025-02-14 - Elixir List Operations

**Learning:** Checking list emptiness with `length(list) == 0` or `length(list) > 0` is `O(N)` in Elixir since lists are linked lists. It forces a full traversal. Also, piping `Enum.map |> Enum.reject` or nesting `Enum.reject(Enum.map(...))` traverses the list twice and builds an intermediate list in memory, triggering unnecessary GC pressure.

**Action:** Always use `list == []` or `list != []` for `O(1)` emptiness checks. Use `for` comprehensions (e.g. `for x <- list, val = x.property, val != nil, do: val`) to combine mapping and filtering into a single pass without intermediate list allocations.
