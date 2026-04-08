defmodule ControlKeel.TaskAugmentation do
  @moduledoc false

  alias ControlKeel.Intent
  alias ControlKeel.Mission.{Finding, Session, Task}

  @stop_words MapSet.new(
                ~w(a an and are as at be before by do for from how if in into is it keep of on or that the this to use with)
              )

  def build(%Session{} = session, task, workspace_context) do
    brief = session.execution_brief || %{}
    boundary = Intent.boundary_summary(brief)
    current_task = normalize_task(task)
    findings = assoc_list(session.findings)
    active_findings = Enum.filter(findings, &(&1.status in ["open", "blocked", "escalated"]))
    likely_paths = likely_paths(workspace_context)
    search_terms = search_terms(session, current_task, active_findings)
    validation_focus = validation_focus(session, boundary, active_findings)

    %{
      "available" => not is_nil(current_task),
      "task_title" => current_task && current_task.title,
      "objective" => (current_task && current_task.title) || session.objective,
      "augmented_brief" =>
        augmented_brief(session, current_task, likely_paths, search_terms, validation_focus),
      "likely_paths" => likely_paths,
      "search_terms" => search_terms,
      "validation_focus" => validation_focus,
      "evidence_sources" => evidence_sources(workspace_context, active_findings),
      "active_finding_count" => length(active_findings),
      "risk_tier" => session.risk_tier,
      "reason" => if(is_nil(current_task), do: "no_active_task", else: "derived_contextual_brief")
    }
  end

  def build(_session, _task, _workspace_context) do
    %{
      "available" => false,
      "task_title" => nil,
      "objective" => nil,
      "augmented_brief" => "No active task is available for augmentation yet.",
      "likely_paths" => [],
      "search_terms" => [],
      "validation_focus" => [],
      "evidence_sources" => [],
      "active_finding_count" => 0,
      "risk_tier" => nil,
      "reason" => "session_missing"
    }
  end

  defp normalize_task(%Task{} = task), do: task
  defp normalize_task(_task), do: nil

  defp likely_paths(workspace_context) when is_map(workspace_context) do
    paths =
      workspace_context["instruction_files"] ++
        workspace_context["key_files"] ++
        get_in(workspace_context, ["design_drift", "recent_hotspots"]) ++
        get_in(workspace_context, ["design_drift", "large_files"])

    paths
    |> Enum.map(&Map.get(&1, "path"))
    |> Enum.reject(&is_nil_or_blank/1)
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp likely_paths(_workspace_context), do: []

  defp search_terms(%Session{} = session, task, active_findings) do
    sources =
      [
        session.objective,
        task && task.title,
        get_in(session.execution_brief || %{}, ["objective"]),
        Enum.join(get_in(session.execution_brief || %{}, ["key_features"]) || [], " "),
        Enum.join(Enum.map(active_findings, &finding_search_text/1), " ")
      ]

    sources
    |> Enum.reject(&is_nil_or_blank/1)
    |> Enum.flat_map(&tokenize/1)
    |> Enum.uniq()
    |> Enum.take(8)
  end

  defp validation_focus(%Session{} = session, boundary, active_findings) do
    blocked = Enum.count(active_findings, &(&1.status == "blocked"))
    categories = active_findings |> Enum.map(& &1.category) |> Enum.uniq()

    []
    |> maybe_add_focus(
      session.risk_tier in ["high", "critical"],
      "Keep changes small and reviewable because this session is #{session.risk_tier} risk."
    )
    |> maybe_add_focus(
      blocked > 0,
      "Resolve or account for #{blocked} blocked finding(s) before calling the task done."
    )
    |> maybe_add_focus(
      "security" in categories,
      "Preserve security behavior and avoid regressing active security findings."
    )
    |> Kernel.++(
      boundary["constraints"]
      |> List.wrap()
      |> Enum.map(&"Honor constraint: #{&1}")
      |> Enum.take(3)
    )
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp evidence_sources(workspace_context, active_findings) do
    []
    |> maybe_add_source(
      is_map(workspace_context) and workspace_context["available"] == true,
      "workspace_context"
    )
    |> maybe_add_source(active_findings != [], "active_findings")
    |> maybe_add_source(
      get_in(workspace_context || %{}, ["design_drift", "recent_hotspots"]) != [],
      "recent_hotspots"
    )
    |> maybe_add_source(
      get_in(workspace_context || %{}, ["instruction_files"]) != [],
      "repo_instructions"
    )
  end

  defp augmented_brief(session, nil, likely_paths, search_terms, validation_focus) do
    base = session.objective || "No task title is available yet."
    render_augmented_brief(base, likely_paths, search_terms, validation_focus)
  end

  defp augmented_brief(_session, task, likely_paths, search_terms, validation_focus) do
    render_augmented_brief(task.title, likely_paths, search_terms, validation_focus)
  end

  defp render_augmented_brief(base, likely_paths, search_terms, validation_focus) do
    path_text =
      case likely_paths do
        [] -> "No likely file paths were derived yet."
        paths -> "Start by checking #{Enum.join(paths, ", ")}."
      end

    search_text =
      case search_terms do
        [] -> "No strong search terms were derived yet."
        terms -> "Use search terms like #{Enum.join(terms, ", ")}."
      end

    focus_text =
      case validation_focus do
        [] -> "No extra validation focus was derived."
        focus -> Enum.join(focus, " ")
      end

    Enum.join([base, path_text, search_text, focus_text], " ")
  end

  defp finding_search_text(%Finding{} = finding) do
    [finding.title, finding.rule_id, finding.plain_message]
    |> Enum.reject(&is_nil_or_blank/1)
    |> Enum.join(" ")
  end

  defp tokenize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_]+/, trim: true)
    |> Enum.reject(&(String.length(&1) < 4))
    |> Enum.reject(&MapSet.member?(@stop_words, &1))
  end

  defp tokenize(_text), do: []

  defp assoc_list(%Ecto.Association.NotLoaded{}), do: []
  defp assoc_list(nil), do: []
  defp assoc_list(list) when is_list(list), do: list
  defp assoc_list(_value), do: []

  defp maybe_add_focus(focus, true, item), do: focus ++ [item]
  defp maybe_add_focus(focus, false, _item), do: focus

  defp maybe_add_source(sources, true, item), do: sources ++ [item]
  defp maybe_add_source(sources, false, _item), do: sources

  defp is_nil_or_blank(nil), do: true
  defp is_nil_or_blank(text) when is_binary(text), do: String.trim(text) == ""
  defp is_nil_or_blank(_text), do: false
end
