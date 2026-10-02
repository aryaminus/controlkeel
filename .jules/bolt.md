## 2024-06-25 - Single-pass Enum.reduce optimization
**Learning:** Found a sequence of `Enum.filter` followed by three separate `Enum.count` iterations over the same list (`health` calculation in `observability.ex`).
**Action:** Replaced multiple passes with a single-pass `Enum.reduce` to avoid intermediate list allocations (saving memory) and reduce CPU overhead from multiple passes.
