defmodule ControlKeel.Cloud.BaselineAnalyzer do
  @moduledoc """
  Behavioral baselining for workspace sessions.

  Computes a rolling per-tool baseline (calls/session, tokens/call) from the
  last N days of invocations for each workspace.

  ## Baseline data shape (stored as JSON)

      %{
        "tool_name" => %{
          "mean_calls_per_session" => float,
          "mean_input_tokens"      => float,
          "mean_output_tokens"     => float,
          "sample_count"           => integer
        }
      }
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.Workspace.Baseline
  alias ControlKeel.Mission.{Invocation, Session}
  alias ControlKeel.Repo

  @default_window_days 7

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Compute the rolling baseline for `workspace_id` and persist it.

  Options:
    - `:window_days` — look-back window (default 7)
  """
  @spec compute_and_store(integer(), keyword()) ::
          {:ok, Baseline.t()} | {:error, term()}
  def compute_and_store(workspace_id, opts \\ []) when is_integer(workspace_id) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    {baseline_map, sample_sessions} = build_baseline(workspace_id, window_days)

    attrs = %{
      workspace_id: workspace_id,
      window_days: window_days,
      baseline_data: Jason.encode!(baseline_map),
      sample_sessions: sample_sessions,
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    existing = Repo.get_by(Baseline, workspace_id: workspace_id)

    changeset =
      case existing do
        nil -> Baseline.changeset(%Baseline{}, attrs)
        record -> Baseline.changeset(record, attrs)
      end

    Repo.insert_or_update(changeset)
  end

  @doc """
  Returns the stored baseline for `workspace_id`, or `nil`.
  """
  @spec get_baseline(integer()) :: Baseline.t() | nil
  def get_baseline(workspace_id), do: Repo.get_by(Baseline, workspace_id: workspace_id)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_baseline(workspace_id, window_days) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-window_days * 86_400, :second)
      |> DateTime.truncate(:second)

    rows =
      from(i in Invocation,
        join: s in Session,
        on: s.id == i.session_id,
        where: s.workspace_id == ^workspace_id,
        where: i.inserted_at >= ^since,
        where: not is_nil(i.tool),
        group_by: [i.session_id, i.tool],
        select: %{
          session_id: i.session_id,
          tool: i.tool,
          call_count: count(i.id),
          input_tokens: sum(i.input_tokens),
          output_tokens: sum(i.output_tokens)
        }
      )
      |> Repo.all()

    sample_sessions = rows |> Enum.uniq_by(& &1.session_id) |> length()

    baseline =
      rows
      |> Enum.group_by(& &1.tool)
      |> Enum.map(fn {tool, tool_rows} ->
        n = length(tool_rows)
        mean_calls = avg(Enum.map(tool_rows, & &1.call_count))
        mean_input = avg(Enum.map(tool_rows, & &1.input_tokens))
        mean_output = avg(Enum.map(tool_rows, & &1.output_tokens))

        {tool,
         %{
           "mean_calls_per_session" => mean_calls,
           "mean_input_tokens" => mean_input,
           "mean_output_tokens" => mean_output,
           "sample_count" => n
         }}
      end)
      |> Map.new()

    {baseline, sample_sessions}
  end

  defp avg([]), do: 0.0
  defp avg(values), do: Enum.sum(values) / length(values)
end
