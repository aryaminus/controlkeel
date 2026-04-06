# Claw4S Submission Notes

This directory contains the ControlKeel Claw4S submission package.

## What This Submission Is

- An executable **computer-science** submission for Claw4S
- A benchmarked note about the **governance layer** around coding agents
- A reproducible calibration run over ControlKeel's shipped public benchmark suites

## What This Submission Is Not

- Not a claim that ControlKeel fully solves coding-agent safety
- Not a universal benchmark across all coding-agent hosts
- Not a bioinformatics method paper
- Not an autonomous deployment or enterprise-compliance claim

## Venue Compliance Checklist

- `SKILL.md` is step-by-step and executable
- research note is provided in LaTeX and Markdown
- the artifact is reproducible without external provider keys
- the benchmark uses shipped public suites rather than hidden data
- the visible author line includes `Claw` as a co-author
- the research note stays within the conference's 1-4 page LaTeX note format

## Benchmark Validity Notes

- `vibe_failures_v1` is the public positive suite
- `benign_baseline_v1` is the paired public benign suite
- the repo's benchmark playbook explicitly reserves public suites for comparable external reporting
- the submission evaluates one shipped subject: `controlkeel_validate`
- that fixed subject isolates the governance core from host-specific attach or plugin quality
- the underlying benchmark method still generalizes to `controlkeel_proxy`, `manual_import`, and `shell`
- the artifact is therefore a **calibration benchmark**, not a leaderboard
- this is deliberate because Claw4S rewards executability and rigor before breadth

## Authorship and Payload Notes

- `human_names` is omitted from the clawRxiv payload on purpose because clawRxiv reserves it for human collaborators
- satisfy the venue's `Claw` co-author rule through the visible paper author line and the registered claw name, for example `controlkeel-claw`

## Recommended Publication Flow

1. Review `paper.md`, `research_note.tex`, and `SKILL.md`
2. Rebuild `submission_payload.json`
3. Register a clawRxiv agent name that visibly includes `Claw`
4. Publish the payload to `https://clawrxiv.io/api/posts`

Use:

```bash
mix run submissions/claw4s-controlkeel/scripts/build_submission_payload.exs
```

If you want a one-command publish helper later, add it only after choosing the final claw name and API key handling strategy.
