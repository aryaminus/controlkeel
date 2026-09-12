defmodule ControlKeel.MCP.Tools.CkSessionDigest do
  @moduledoc false

  alias ControlKeel.Governance.SessionDigest, as: DigestEngine
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Session digest failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    with {:ok, session} <- Arguments.fetch_session(arguments) do
      id = session.id
      mode = Map.get(arguments, "mode", "generate")

      case mode do
        "generate" ->
          digest_type = Map.get(arguments, "digest_type", "session")

          case DigestEngine.generate(id, digest_type: digest_type) do
            {:ok, digest} ->
              {:ok, format_digest(digest)}

            {:error, reason} ->
              {:error, reason}
          end

        "latest" ->
          case DigestEngine.latest(id) do
            nil -> {:ok, %{"message" => "No digest found for this session"}}
            digest -> {:ok, format_digest(digest)}
          end

        "list" ->
          digests = DigestEngine.list(id)
          {:ok, %{"digests" => Enum.map(digests, &format_digest/1), "count" => length(digests)}}

        _ ->
          {:error, {:invalid_arguments, "mode must be generate, latest, or list"}}
      end
    end
  end

  defp format_digest(digest) do
    %{
      "id" => digest.id,
      "session_id" => digest.session_id,
      "digest_type" => digest.digest_type,
      "period_start" => digest.period_start,
      "period_end" => digest.period_end,
      "tasks_completed" => digest.tasks_completed,
      "tasks_failed" => digest.tasks_failed,
      "findings_raised" => digest.findings_raised,
      "findings_blocked" => digest.findings_blocked,
      "reviews_pending" => digest.reviews_pending,
      "reviews_approved" => digest.reviews_approved,
      "budget_spent_cents" => digest.budget_spent_cents,
      "budget_remaining_cents" => digest.budget_remaining_cents,
      "top_rule_ids" => digest.top_rule_ids,
      "top_categories" => digest.top_categories,
      "highlights" => digest.highlights,
      "needs_attention" => digest.needs_attention,
      "generated_at" => digest.generated_at,
      "metadata" => digest.metadata
    }
  end
end
