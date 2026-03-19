defmodule ControlKeel.Budget do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias ControlKeel.Budget.Pricing
  alias ControlKeel.Memory
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Invocation, Session}
  alias ControlKeel.PolicyTraining
  alias ControlKeel.Repo

  @warn_threshold 0.8

  def estimate_proxy(attrs) when is_map(attrs) do
    counts = proxy_token_counts(attrs)
    provider = Map.get(attrs, "provider")
    model = Map.get(attrs, "model")

    normalized_attrs =
      case {provider, model} do
        {provider, model} when is_binary(provider) and is_binary(model) ->
          Map.merge(attrs, %{
            "input_tokens" => counts.input_tokens,
            "cached_input_tokens" => counts.cached_input_tokens,
            "output_tokens" => counts.output_tokens
          })

        _ ->
          Map.put(attrs, "estimated_cost_cents", Pricing.fallback_estimate_cents(counts))
      end

    with {:ok, estimate} <- estimate(normalized_attrs) do
      {:ok,
       Map.merge(estimate, %{
         "input_tokens" => counts.input_tokens,
         "cached_input_tokens" => counts.cached_input_tokens,
         "output_tokens" => counts.output_tokens
       })}
    end
  end

  def estimate(attrs) when is_map(attrs) do
    with {:ok, session} <- fetch_session(attrs["session_id"]),
         {:ok, estimated_cost_cents} <- estimated_cost_cents(attrs) do
      rolling_24h = rolling_24h_spend_cents(session.id)
      projected_session = (session.spent_cents || 0) + estimated_cost_cents
      projected_daily = rolling_24h + estimated_cost_cents
      base_decision = decision(session, projected_session, projected_daily)
      base_summary = summary(session, base_decision, projected_session, projected_daily)
      active_findings_count = active_findings_count(session.id)

      hint =
        PolicyTraining.budget_hint(
          %{"decision" => base_decision, "summary" => base_summary},
          session,
          Map.put(attrs, "estimated_cost_cents", estimated_cost_cents),
          projected_session,
          projected_daily,
          active_findings_count
        )

      decision = hint["decision"] || base_decision
      summary = hint["summary"] || base_summary

      if decision in ["warn", "block"] do
        record_budget_memory(session, decision, summary, estimated_cost_cents, attrs)
      end

      {:ok,
       %{
         "allowed" => decision != "block",
         "decision" => decision,
         "summary" => summary,
         "estimated_cost_cents" => estimated_cost_cents,
         "projected_spend_cents" => projected_session,
         "remaining_session_cents" => remaining(projected_session, session.budget_cents),
         "rolling_24h_spend_cents" => projected_daily,
         "remaining_daily_cents" => remaining(projected_daily, session.daily_budget_cents),
         "recorded" => false,
         "hint_source" => hint["hint_source"],
         "hint_probability" => hint["hint_probability"],
         "artifact_version" => hint["artifact_version"]
       }}
    end
  end

  def commit(attrs) when is_map(attrs) do
    with {:ok, estimate} <- estimate(attrs),
         {:ok, task_id} <- validate_task_id(attrs["task_id"], attrs["session_id"]) do
      invocation_attrs = %{
        source: Map.get(attrs, "source", "mcp"),
        tool: Map.get(attrs, "tool", "ck_budget"),
        provider: attrs["provider"],
        model: attrs["model"],
        input_tokens: attrs["input_tokens"] || 0,
        cached_input_tokens: attrs["cached_input_tokens"] || 0,
        output_tokens: attrs["output_tokens"] || 0,
        estimated_cost_cents: estimate["estimated_cost_cents"],
        decision: estimate["decision"],
        metadata:
          %{
            "mode" => "commit",
            "projected_spend_cents" => estimate["projected_spend_cents"],
            "rolling_24h_spend_cents" => estimate["rolling_24h_spend_cents"]
          }
          |> Map.merge(Map.get(attrs, "metadata", %{})),
        session_id: attrs["session_id"],
        task_id: task_id
      }

      Multi.new()
      |> Multi.insert(:invocation, Invocation.changeset(%Invocation{}, invocation_attrs))
      |> Multi.update_all(
        :session,
        from(s in Session, where: s.id == ^attrs["session_id"]),
        inc: [spent_cents: estimate["estimated_cost_cents"]]
      )
      |> Repo.transaction()
      |> case do
        {:ok, _changes} ->
          {:ok, Map.put(estimate, "recorded", true)}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  def rolling_24h_spend_cents(session_id) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-24, :hour)
      |> DateTime.truncate(:second)

    from(i in Invocation,
      where: i.session_id == ^session_id and i.inserted_at >= ^since,
      select: coalesce(sum(i.estimated_cost_cents), 0)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp fetch_session(nil), do: {:error, {:invalid_arguments, "`session_id` is required"}}

  defp fetch_session(session_id) do
    case Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp estimated_cost_cents(%{"estimated_cost_cents" => value})
       when is_integer(value) and value >= 0,
       do: {:ok, value}

  defp estimated_cost_cents(attrs) do
    case {attrs["provider"], attrs["model"]} do
      {provider, model} when is_binary(provider) and is_binary(model) ->
        Pricing.estimate_cost_cents(provider, model, %{
          input_tokens: attrs["input_tokens"] || 0,
          cached_input_tokens: attrs["cached_input_tokens"] || 0,
          output_tokens: attrs["output_tokens"] || 0
        })
        |> case do
          {:ok, cents} ->
            {:ok, cents}

          {:error, :unknown_model} ->
            {:error,
             {:invalid_arguments,
              "Unknown model pricing. Provide `estimated_cost_cents` or use a supported provider/model pair."}}
        end

      _ ->
        {:error,
         {:invalid_arguments,
          "Provide `estimated_cost_cents` or `provider`, `model`, `input_tokens`, and `output_tokens`."}}
    end
  end

  defp validate_task_id(nil, _session_id), do: {:ok, nil}

  defp validate_task_id(task_id, session_id) do
    case Mission.get_task!(task_id) do
      %{session_id: ^session_id} -> {:ok, task_id}
      _task -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  rescue
    Ecto.NoResultsError -> {:error, {:invalid_arguments, "`task_id` was not found"}}
  end

  defp decision(session, projected_session, projected_daily) do
    session_ratio = ratio(projected_session, session.budget_cents)
    daily_ratio = ratio(projected_daily, session.daily_budget_cents)

    cond do
      exceeds_limit?(session_ratio) or exceeds_limit?(daily_ratio) -> "block"
      near_limit?(session_ratio) or near_limit?(daily_ratio) -> "warn"
      true -> "allow"
    end
  end

  defp summary(session, "block", projected_session, projected_daily) do
    case block_reason(session, projected_session, projected_daily) do
      :daily -> "Blocked: this run would exceed the rolling 24-hour budget."
      _session -> "Blocked: this run would exceed the session budget cap."
    end
  end

  defp summary(session, "warn", projected_session, projected_daily) do
    case warn_reason(session, projected_session, projected_daily) do
      :daily -> "Warning: this run would push spend close to the rolling 24-hour budget."
      _session -> "Warning: this run would push spend close to the session budget cap."
    end
  end

  defp summary(_session, _decision, _projected_session, _projected_daily) do
    "Budget is within the configured limits."
  end

  defp block_reason(session, _projected_session, projected_daily) do
    cond do
      exceeds_limit?(ratio(projected_daily, session.daily_budget_cents)) -> :daily
      true -> :session
    end
  end

  defp warn_reason(session, projected_session, projected_daily) do
    cond do
      near_limit?(ratio(projected_daily, session.daily_budget_cents)) -> :daily
      near_limit?(ratio(projected_session, session.budget_cents)) -> :session
      true -> :session
    end
  end

  defp remaining(_spent, limit) when limit in [nil, 0], do: nil
  defp remaining(spent, limit), do: max(limit - spent, 0)

  defp ratio(_spent, limit) when limit in [nil, 0], do: 0.0
  defp ratio(spent, limit), do: spent / limit

  defp exceeds_limit?(value), do: value >= 1.0
  defp near_limit?(value), do: value >= @warn_threshold

  defp active_findings_count(session_id) do
    Mission.list_session_findings(session_id)
    |> Enum.count(&(&1.status in ["open", "blocked", "escalated"]))
  end

  defp proxy_token_counts(attrs) do
    input_text = Map.get(attrs, "input_text", "")

    max_output_tokens =
      Map.get(attrs, "max_output_tokens") || Map.get(attrs, "output_tokens") || 0

    cached_input_tokens = Map.get(attrs, "cached_input_tokens") || 0

    %{
      input_tokens: approximate_tokens(input_text),
      cached_input_tokens: cached_input_tokens,
      output_tokens: normalize_proxy_token_count(max_output_tokens)
    }
  end

  defp approximate_tokens(nil), do: 0

  defp approximate_tokens(text) when is_binary(text) do
    text
    |> String.trim()
    |> case do
      "" -> 0
      trimmed -> Float.ceil(byte_size(trimmed) / 4) |> trunc()
    end
  end

  defp normalize_proxy_token_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_proxy_token_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp normalize_proxy_token_count(_value), do: 0

  defp record_budget_memory(session, decision, summary, estimated_cost_cents, attrs) do
    Memory.record(%{
      workspace_id: session.workspace_id,
      session_id: session.id,
      task_id: attrs["task_id"],
      record_type: "budget",
      title: "Budget #{decision}: #{session.title}",
      summary: summary,
      body: "Estimated cost #{estimated_cost_cents} cents for #{attrs["tool"] || "ck_budget"}",
      tags: [decision, "budget"],
      source_type: "budget",
      source_id: "#{session.id}:#{decision}:#{attrs["tool"] || "ck_budget"}",
      metadata: %{
        "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"]),
        "decision" => decision,
        "estimated_cost_cents" => estimated_cost_cents,
        "tool" => attrs["tool"],
        "source" => attrs["source"]
      }
    })
  end
end
