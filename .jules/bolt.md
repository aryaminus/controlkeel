## 2026-08-08 - Enum.map |> Enum.uniq() |> length() replaced by Enum.uniq_by |> length()
**Learning:** Found an inefficiency in calculating lengths of unique elements from mapped structs/maps. The idiom `Enum.map(& &1.field) |> Enum.uniq() |> length()` forces the creation of an intermediate list before deduplication and counting.
**Action:** Use `Enum.uniq_by` to do this without the intermediate map step: `Enum.uniq_by(& &1.field) |> length()`.
