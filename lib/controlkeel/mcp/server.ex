defmodule ControlKeel.MCP.Server do
  @moduledoc false

  use GenServer

  alias ControlKeel.MCP.Protocol

  @doc false
  def stdio_registered_name, do: :controlkeel_mcp_stdio

  def start_link(opts) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, gen_opts)
  end

  def dispatch_request(server, request) do
    GenServer.call(server, {:dispatch, request})
  end

  @impl true
  def init(opts) do
    state = %{
      input: Keyword.get(opts, :input, :stdio),
      output: Keyword.get(opts, :output, :stdio),
      read_task: nil
    }

    state =
      if Keyword.get(opts, :start_reader, true) do
        %{state | read_task: start_reader(state.input)}
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:dispatch, request}, _from, state) do
    try do
      # Include project_root in opts for adaptive tool group behavior
      opts = [project_root: stdio_project_root()]
      {:reply, Protocol.handle_request(request, opts), state}
    rescue
      e ->
        require Logger
        Logger.error("MCP dispatch failed: #{Exception.message(e)}")
        {:reply, {:error, "Internal server error"}, state}
    catch
      :exit, e ->
        require Logger
        Logger.error("MCP dispatch exited: #{inspect(e)}")
        {:reply, {:error, "Internal server error"}, state}

      :throw, e ->
        require Logger
        Logger.error("MCP dispatch threw: #{inspect(e)}")
        {:reply, {:error, "Internal server error"}, state}
    end
  end

  @impl true
  def handle_info({:mcp_payload, payload}, state) do
    try do
      # Include project_root in opts for adaptive tool group behavior
      opts = [project_root: stdio_project_root()]

      payload
      |> Protocol.handle_json(opts)
      |> maybe_write_frame(state.output)

      {:noreply, state}
    rescue
      e ->
        require Logger
        Logger.error("MCP payload handling failed: #{Exception.message(e)}")
        {:noreply, state}
    catch
      :exit, e ->
        require Logger
        Logger.error("MCP payload handling exited: #{inspect(e)}")
        {:noreply, state}

      :throw, e ->
        require Logger
        Logger.error("MCP payload handling threw: #{inspect(e)}")
        {:noreply, state}
    end
  end

  def handle_info(:mcp_eof, state) do
    {:stop, :normal, state}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | read_task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{read_task: {_, ref}} = state) do
    {:noreply, %{state | read_task: nil}}
  end

  defp maybe_write_frame(:no_response, _output), do: :ok

  defp maybe_write_frame(response, output) do
    payload = Jason.encode!(response, escape: :unicode_safe)
    frame = encode_frame(payload)
    write_binary(output, frame)
  end

  defp start_reader(input) do
    parent = self()

    Task.start_link(fn ->
      # MCP stdio: newline-delimited JSON-RPC (modelcontextprotocol.io).
      _ = :io.setopts(binary: true, encoding: :utf8)
      read_loop(parent, input)
    end)
    |> case do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        {pid, ref}

      other ->
        other
    end
  end

  defp read_loop(parent, input) do
    case read_frame(input) do
      {:ok, payload} ->
        send(parent, {:mcp_payload, payload})
        read_loop(parent, input)

      :eof ->
        send(parent, :mcp_eof)

      {:error, reason} ->
        send(
          parent,
          {:mcp_payload,
           Jason.encode!(%{
             "jsonrpc" => "2.0",
             "id" => nil,
             "error" => %{"code" => -32700, "message" => "Invalid frame: #{inspect(reason)}"}
           })}
        )

        send(parent, :mcp_eof)
    end
  end

  defp read_frame(input) do
    case IO.read(input, :line) do
      :eof ->
        :eof

      line when is_binary(line) ->
        line = String.trim(line)
        if line == "", do: read_frame(input), else: {:ok, line}
    end
  end

  @doc """
  Encodes one MCP stdio message: JSON bytes plus a trailing newline (MCP spec).
  """
  def encode_frame(payload) when is_binary(payload) do
    payload <> "\n"
  end

  # Use IO.binwrite/2 for :stdio so data goes through the same user I/O path as
  # IO.read/2 in the reader task. :file.write + :file.sync on :standard_io has
  # caused long stalls on some piped MCP hosts (Cursor ~10s abort window).
  defp write_binary(:stdio, data) do
    case IO.binwrite(:stdio, data) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp write_binary(device, data) do
    case :file.write(device, data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp stdio_project_root do
    try do
      case System.get_env("CK_PROJECT_ROOT") do
        v when is_binary(v) and v != "" ->
          v |> String.trim() |> Path.expand()

        _ ->
          File.cwd!()
      end
    rescue
      _ -> System.tmp_dir!()
    catch
      :exit, _ -> System.tmp_dir!()
      :throw, _ -> System.tmp_dir!()
    end
  end
end
