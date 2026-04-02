defmodule ControlKeel.ReviewBridge do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Mission.Review
  alias ControlKeelWeb.Endpoint

  def browser_url(%Review{id: id}), do: browser_url(id)

  def browser_url(review_id) when is_integer(review_id),
    do: Endpoint.url() <> "/reviews/#{review_id}"

  def open_review(review_or_id, opts \\ []) do
    with {:ok, review} <- fetch_review(review_or_id) do
      embed = Keyword.get(opts, :browser_embed, browser_embed())
      open_target = open_target(embed, remote_mode?())

      {:ok,
       %{
         review: review,
         url: browser_url(review),
         browser_embed: embed,
         remote: remote_mode?(),
         open_target: open_target
       }}
    end
  end

  def wait_for_review(review_or_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 120_000)
    interval_ms = Keyword.get(opts, :interval_ms, 1_000)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_wait(review_or_id, deadline, interval_ms)
  end

  def browser_embed do
    System.get_env("CONTROLKEEL_REVIEW_EMBED") ||
      System.get_env("CONTROLKEEL_BROWSER_EMBED") ||
      "external"
  end

  def remote_mode? do
    System.get_env("CONTROLKEEL_REMOTE") in ["1", "true", "TRUE"]
  end

  defp do_wait(review_or_id, deadline, interval_ms) do
    case fetch_review(review_or_id) do
      {:ok, %Review{status: status} = review} when status in ["approved", "denied"] ->
        {:ok, review}

      {:ok, review} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {:timeout, review}}
        else
          Process.sleep(interval_ms)
          do_wait(review.id, deadline, interval_ms)
        end

      error ->
        error
    end
  end

  defp fetch_review(%Review{} = review), do: {:ok, review}

  defp fetch_review(review_id) when is_integer(review_id) do
    case Mission.get_review_with_context(review_id) do
      nil -> {:error, :not_found}
      review -> {:ok, review}
    end
  end

  defp fetch_review(_review_id), do: {:error, :not_found}

  defp open_target(_embed, true), do: "manual"
  defp open_target("vscode_webview", false), do: "vscode_webview"
  defp open_target(_embed, false), do: "external_browser"
end
