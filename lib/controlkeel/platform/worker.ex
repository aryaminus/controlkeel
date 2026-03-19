defmodule ControlKeel.Platform.Worker do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Platform

  def start(service_account_token, opts \\ []) when is_binary(service_account_token) do
    interval = Keyword.get(opts, :interval, 2_000)
    printer = Keyword.get(opts, :printer, &IO.puts/1)

    with {:ok, service_account} <- Platform.authenticate_service_account(service_account_token) do
      loop(service_account, interval, printer)
    end
  end

  defp loop(service_account, interval, printer) do
    session_ids =
      service_account.workspace_id
      |> Mission.list_sessions_for_workspace()
      |> Enum.map(& &1.id)

    Enum.each(session_ids, fn session_id ->
      {:ok, graph} = Platform.execute_session(session_id)

      graph.ready_task_ids
      |> Enum.map(&Mission.get_task/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.each(fn task ->
        printer.("ready ##{task.id} #{task.title}")
      end)
    end)

    :timer.sleep(interval)
    loop(service_account, interval, printer)
  end
end
