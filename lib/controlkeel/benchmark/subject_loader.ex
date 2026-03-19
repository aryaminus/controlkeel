defmodule ControlKeel.Benchmark.SubjectLoader do
  @moduledoc false

  @builtin_subjects [
    %{
      "id" => "controlkeel_validate",
      "label" => "ControlKeel Validate",
      "type" => "controlkeel_validate",
      "configured" => true
    },
    %{
      "id" => "controlkeel_proxy",
      "label" => "ControlKeel Proxy",
      "type" => "controlkeel_proxy",
      "configured" => true
    }
  ]

  def builtin_subject_ids, do: Enum.map(@builtin_subjects, & &1["id"])
  def builtin_subjects, do: @builtin_subjects

  def default_subject_ids do
    builtin_subject_ids()
  end

  def resolve(subject_ids, project_root \\ File.cwd!()) when is_list(subject_ids) do
    external_by_id =
      project_root
      |> external_subjects()
      |> Map.new(fn subject -> {subject["id"], subject} end)

    builtin_by_id = Map.new(@builtin_subjects, fn subject -> {subject["id"], subject} end)

    Enum.map(subject_ids, fn subject_id ->
      builtin_by_id[subject_id] ||
        external_by_id[subject_id] ||
        %{
          "id" => subject_id,
          "label" => humanize(subject_id),
          "type" => "unconfigured",
          "configured" => false
        }
    end)
  end

  def subject_config_hash(subjects) when is_list(subjects) do
    subjects
    |> Enum.map(
      &Map.take(&1, [
        "id",
        "label",
        "type",
        "command",
        "args",
        "working_dir",
        "timeout_ms",
        "output_mode"
      ])
    )
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def external_subjects(project_root \\ File.cwd!()) do
    path = Path.join(Path.expand(project_root), "controlkeel/benchmark_subjects.json")

    with true <- File.exists?(path) || false,
         {:ok, payload} <- File.read(path),
         {:ok, decoded} <- Jason.decode(payload),
         subject_list when is_list(subject_list) <- decoded["subjects"] || decoded do
      Enum.map(subject_list, &normalize_external_subject/1)
    else
      _ -> []
    end
  end

  defp normalize_external_subject(subject) when is_map(subject) do
    args =
      case subject["args"] do
        args when is_list(args) -> Enum.map(args, &to_string/1)
        _ -> []
      end

    %{
      "id" => to_string(subject["id"]),
      "label" => subject["label"] || humanize(subject["id"]),
      "type" => normalize_type(subject["type"]),
      "command" => subject["command"],
      "args" => args,
      "working_dir" => subject["working_dir"],
      "timeout_ms" => normalize_timeout(subject["timeout_ms"]),
      "output_mode" => normalize_output_mode(subject["output_mode"]),
      "configured" => true
    }
  end

  defp normalize_external_subject(subject) do
    %{
      "id" => inspect(subject),
      "label" => inspect(subject),
      "type" => "unconfigured",
      "configured" => false
    }
  end

  defp normalize_type("manual_import"), do: "manual_import"
  defp normalize_type("shell"), do: "shell"
  defp normalize_type(_value), do: "shell"

  defp normalize_timeout(value) when is_integer(value) and value > 0, do: value

  defp normalize_timeout(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> 30_000
    end
  end

  defp normalize_timeout(_value), do: 30_000

  defp normalize_output_mode("directory"), do: "directory"
  defp normalize_output_mode("stdout"), do: "stdout"
  defp normalize_output_mode(_value), do: "stdout"

  defp humanize(nil), do: "Unconfigured subject"

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace(~r/[_-]+/u, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
