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

      open_result =
        maybe_open_browser(
          browser_url(review),
          open_target,
          Keyword.get(opts, :auto_open, auto_open_reviews?())
        )

      {:ok,
       %{
         review: review,
         url: browser_url(review),
         browser_embed: embed,
         remote: remote_mode?(),
         open_target: open_target,
         opened: open_result.opened,
         open_error: open_result.open_error
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

  def browser_command do
    System.get_env("CONTROLKEEL_BROWSER") ||
      System.get_env("BROWSER")
  end

  def agent_feedback(%Review{status: "denied"} = review) do
    plan_file_rule =
      case get_in(review.metadata || %{}, ["body_file"]) do
        path when is_binary(path) and path != "" ->
          "- Your plan is saved at: #{path}\n  Edit this file to make targeted changes before resubmitting.\n"

        _ ->
          ""
      end

    feedback = review.feedback_notes || "Plan changes requested."

    """
    YOUR PLAN WAS NOT APPROVED.

    You MUST revise the plan to address ALL feedback below before submitting it again.

    Rules:
    #{plan_file_rule}- Do not resubmit the same plan unchanged.
    - Keep the plan title stable unless a human explicitly asks you to rename it.
    - Do not begin implementation until the review is approved.

    #{feedback}
    """
    |> String.trim()
  end

  def agent_feedback(_review), do: nil

  def remote_mode? do
    System.get_env("CONTROLKEEL_REMOTE") in ["1", "true", "TRUE"]
  end

  def auto_open_reviews? do
    case System.get_env("CONTROLKEEL_AUTO_OPEN_REVIEWS") do
      value when value in ["0", "false", "FALSE"] ->
        false

      value when value in ["1", "true", "TRUE"] ->
        true

      _ ->
        not mix_test_env?()
    end
  end

  defp mix_test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
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

  defp maybe_open_browser(_url, _open_target, false), do: %{opened: false, open_error: nil}
  defp maybe_open_browser(_url, "manual", _auto_open), do: %{opened: false, open_error: nil}

  defp maybe_open_browser(_url, "vscode_webview", _auto_open),
    do: %{opened: false, open_error: nil}

  defp maybe_open_browser(url, "external_browser", _auto_open) do
    case open_browser(url) do
      :ok -> %{opened: true, open_error: nil}
      {:error, reason} -> %{opened: false, open_error: reason}
    end
  end

  defp open_browser(url) do
    cond do
      browser = present_browser_command() ->
        open_with_configured_browser(browser, url)

      wsl?() ->
        run_browser_command("cmd.exe", ["/c", "start", "", url])

      match?({:win32, _}, :os.type()) ->
        run_browser_command("cmd", ["/c", "start", "", url])

      match?({:unix, :darwin}, :os.type()) ->
        run_browser_command("open", [url])

      true ->
        run_browser_command("xdg-open", [url])
    end
  end

  defp open_with_configured_browser(browser, url) do
    cond do
      match?({:unix, :darwin}, :os.type()) and String.contains?(browser, "/") and
          not String.ends_with?(browser, ".app") ->
        run_browser_command(browser, [url], resolve_executable?: false)

      match?({:unix, :darwin}, :os.type()) ->
        run_browser_command("open", ["-a", browser, url])

      wsl?() ->
        run_browser_command("cmd.exe", ["/c", "start", "", browser, url])

      match?({:win32, _}, :os.type()) ->
        run_browser_command("cmd", ["/c", "start", "", browser, url])

      true ->
        run_browser_command(browser, [url], resolve_executable?: false)
    end
  end

  defp run_browser_command(command, args, opts \\ []) do
    executable =
      if Keyword.get(opts, :resolve_executable?, true) do
        System.find_executable(command) || command
      else
        command
      end

    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        {:error, "browser open failed with exit #{status}: #{String.trim(output)}"}
    end
  rescue
    error ->
      {:error, Exception.message(error)}
  end

  defp wsl? do
    match?({:unix, :linux}, :os.type()) and
      case File.read("/proc/version") do
        {:ok, content} -> String.contains?(String.downcase(content), "microsoft")
        _ -> false
      end
  end

  defp present_browser_command do
    case browser_command() do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
