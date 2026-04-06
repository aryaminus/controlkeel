# Proof Workflow

- Before completion, verify that the latest proof bundle reflects the current task state.
- When resuming paused work, use the resume packet plus memory hits, explicit memory search, workspace context, context reacquisition signals, and recent transcript events before making changes.
- If external QA systems report browser or regression failures, record them through `ck_regression_result` before treating the proof as deploy-ready.
- Treat proof bundles as immutable evidence snapshots, not editable state.
