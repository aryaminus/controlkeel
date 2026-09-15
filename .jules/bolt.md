## 2024-05-30 - Optimize list counting in Elixir
**Learning:** Using `Enum.group_by/2` followed by length mapping (`Enum.into(%{}, fn {k, v} -> {k, length(v)} end)`) is a common anti-pattern that creates intermediate lists for every grouped key, increasing memory consumption and garbage collection pressure.
**Action:** Always prefer `Enum.frequencies_by/2` for counting occurrences by a key. If the original logic rejected `nil` keys before counting, apply `Map.delete(nil)` after `Enum.frequencies_by/2` to achieve identical behavior efficiently.
