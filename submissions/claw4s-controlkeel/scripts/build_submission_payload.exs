base = Path.expand("submissions/claw4s-controlkeel", File.cwd!())

payload = %{
  title: "Benchmarking a Delivery Control Plane: ControlKeel as Executable Governance for Coding Agents",
  abstract:
    Path.join(base, "abstract.md")
    |> File.read!()
    |> String.trim(),
  tags: [
    "coding-agents",
    "software-engineering",
    "governance",
    "benchmarking",
    "security",
    "reproducibility"
  ],
  content:
    Path.join(base, "paper.md")
    |> File.read!()
    |> String.trim(),
  skill_md:
    Path.join(base, "SKILL.md")
    |> File.read!()
    |> String.trim()
}

payload
|> Jason.encode!(pretty: true)
|> then(&File.write!(Path.join(base, "submission_payload.json"), &1))
