# Runtime evidence

This document separates three kinds of evidence that are easy to conflate: server-side integration tests, browser journeys, and performance baselines. A green LiveView test does not prove browser rendering, and an agent benchmark does not prove application latency.

## Application performance

Performance tests are tagged `:performance` and excluded from the normal suite so machine variance does not make every pull request flaky. Run them explicitly on a quiet machine:

```sh
mix test --only performance test/performance
```

Each test must assert the behavior as well as elapsed time, use a conservative operator-facing budget, and report the measured value on failure. Tight microbenchmarks belong in Benchee or a dedicated profiler, not ExUnit wall-clock assertions.

For a slow BEAM path, start with telemetry and then use `:cprof` to locate call volume. Use `:eprof` or `:fprof` only on a narrow reproduction because their instrumentation changes timing. Record the command, fixture size, runtime environment, before/after measurements, and variance with any performance claim.

Use the repository-local comparators, generated test inventory, and bounded profiling planner documented in [harness-tools.md](harness-tools.md). These tools fail closed on stale commit evidence and never update baselines automatically.

## Browser and visual evidence

The repository currently has controller, LiveView, self-host, and release smoke coverage, but no browser-driving dependency. Adding Playwright would introduce a root JavaScript package surface, browser downloads, fixture lifecycle, CI caching, and screenshot approval policy, so it requires a separate reviewed change.

The first browser slice should remain small:

1. Start Phoenix with deterministic seed data on an isolated port.
2. Drive one stable review journey in Chromium.
3. Check keyboard navigation and obvious accessibility violations.
4. Capture fixed-viewport light and dark screenshots for stable pages only.
5. Upload failed diffs as CI artifacts; never update baselines automatically.
6. Record the external result through `ck_regression_result` before claiming browser proof.

Do not treat screenshots as behavioral assertions. The journey must still assert meaningful state transitions, and baseline changes require human review.
