## 2024-05-24 - Elixir Enum.frequencies_by vs Enum.group_by
**Learning:** Using `Enum.group_by/2` followed by `Enum.into(%{}, fn {k, v} -> {k, length(v)} end)` creates unnecessary intermediate list allocations for the grouped items, which increases GC pressure.
**Action:** Use `Enum.frequencies_by/2` directly to count occurrences more efficiently without creating intermediate lists.