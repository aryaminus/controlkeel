## 2026-08-19 - Elixir List Allocation Overhead
**Learning:** Chaining `Enum.map/2` into `Enum.uniq/1` then `length/1` (or `Enum.filter/2` into `length/1`) forces unnecessary intermediate list allocations in Elixir, adding hidden overhead.
**Action:** Use `MapSet.new/2 |> MapSet.size()` and `Enum.count/2` to skip intermediate lists and reduce GC pressure.
## 2024-05-24 - Single-pass accumulation for multiple metrics
**Learning:** Using `Enum.filter`, `Enum.count`, and `Enum.map/uniq` chained together allocates multiple intermediate lists and iterates over the same data repeatedly, causing unnecessary GC pressure and CPU usage.
**Action:** Use `Enum.reduce/3` to accumulate multiple counts and unique elements (via `MapSet`) in a single pass over the collection.
