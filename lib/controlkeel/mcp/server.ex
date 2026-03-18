defmodule ControlKeel.MCP.Server do
  @moduledoc false

  use GenServer

  alias ControlKeel.MCP.Protocol

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
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
    {:reply, Protocol.handle_request(request), state}
  end

  @impl true
  def handle_info({:mcp_payload, payload}, state) do
    payload
    |> Protocol.handle_json()
    |> maybe_write_frame(state.output)

    {:noreply, state}
  end

  def handle_info(:mcp_eof, state) do
    {:stop, :normal, state}
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | read_task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{read_task: {pid, ref}} = state) do
    {:noreply, %{state | read_task: {pid, ref}}}
  end

  defp maybe_write_frame(:no_response, _output), do: :ok

  defp maybe_write_frame(response, output) do
    payload = Jason.encode!(response)
    IO.binwrite(output, encode_frame(payload))
  end

  defp start_reader(input) do
    parent = self()

    Task.start_link(fn ->
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
    with {:ok, headers} <- read_headers(input),
         {:ok, length} <- content_length(headers),
         payload when is_binary(payload) <- IO.binread(input, length) do
      {:ok, payload}
    else
      :eof -> :eof
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_headers(input, acc \\ [])

  defp read_headers(input, acc) do
    case IO.read(input, :line) do
      :eof ->
        if acc == [], do: :eof, else: {:error, :unexpected_eof}

      line when line in ["\n", "\r\n"] ->
        {:ok, Enum.reverse(acc)}

      line when is_binary(line) ->
        read_headers(input, [String.trim(line) | acc])
    end
  end

  defp content_length(headers) do
    case Enum.find(headers, &String.starts_with?(String.downcase(&1), "content-length:")) do
      nil ->
        {:error, :missing_content_length}

      header ->
        header
        |> String.split(":", parts: 2)
        |> List.last()
        |> String.trim()
        |> Integer.parse()
        |> case do
          {value, ""} -> {:ok, value}
          _ -> {:error, :invalid_content_length}
        end
    end
  end

  def encode_frame(payload) when is_binary(payload) do
    "Content-Length: #{byte_size(payload)}\r\n\r\n#{payload}"
  end
end
