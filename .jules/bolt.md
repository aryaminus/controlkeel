## 2024-08-12 - Optimize Elixir intermediate list allocations
**Learning:** Operations like length(Enum.filter(...)) and length(Enum.uniq(...)) create intermediate list allocations which add memory overhead. Using Enum.count/2 and MapSet is more efficient.
**Action:** Always prefer Enum.count/2 over length(Enum.filter/2), and MapSet over length(Enum.uniq/1) when dealing with lists to avoid unnecessary memory allocation.
