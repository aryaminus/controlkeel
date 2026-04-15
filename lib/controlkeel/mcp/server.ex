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
    payload = Jason.encode!(response, escape: :unicode_safe)
    frame = encode_frame(payload)
    write_binary(output, frame)
  end

  defp start_reader(input) do
    parent = self()

    Task.start_link(fn ->
      # MCP stdio: newline-delimited JSON-RPC (modelcontextprotocol.io). Also accept
      # legacy Content-Length framing for older clients / tests.
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
        line = String.trim_trailing(line, "\r")

        cond do
          line == "" or line == "\n" ->
            read_frame(input)

          line |> String.trim() |> String.downcase() |> String.starts_with?("content-length:") ->
            read_content_length_framed(input, [String.trim(line)])

          true ->
            trimmed = String.trim(line)
            if trimmed == "", do: read_frame(input), else: {:ok, trimmed}
        end
    end
  end

  defp read_content_length_framed(input, acc) do
    case read_headers_until_blank(input, acc) do
      {:ok, headers} ->
        with {:ok, length} <- content_length(headers),
             payload when is_binary(payload) <- IO.binread(input, length) do
          {:ok, payload}
        else
          :eof -> :eof
          {:error, reason} -> {:error, reason}
          _ -> {:error, :short_body}
        end

      other ->
        other
    end
  end

  defp read_headers_until_blank(input, acc) do
    case IO.read(input, :line) do
      :eof ->
        if acc == [], do: :eof, else: {:error, :unexpected_eof}

      line when line in ["\n", "\r\n"] ->
        {:ok, Enum.reverse(acc)}

      line when is_binary(line) ->
        read_headers_until_blank(input, [String.trim(line) | acc])
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

  @doc """
  Encodes one MCP stdio message: JSON bytes plus a trailing newline (MCP spec).
  Tests and legacy tools may still send Content-Length-framed input; `read_frame/1`
  accepts both.
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
end
