defmodule ControlKeel.Proxy.SSE do
  @moduledoc false

  def new, do: %{buffer: ""}

  def push(%{buffer: buffer} = state, chunk) when is_binary(chunk) do
    payload = buffer <> chunk
    {frames, rest} = split_frames(payload, [])
    events = Enum.map(frames, &parse_event/1)
    {events, %{state | buffer: rest}}
  end

  def flush(%{buffer: ""} = state), do: {[], state}
  def flush(%{buffer: buffer} = state), do: {[parse_event(buffer)], %{state | buffer: ""}}

  defp split_frames(payload, acc) do
    case :binary.match(payload, "\n\n") do
      {position, 2} ->
        frame = binary_part(payload, 0, position + 2)
        rest = binary_part(payload, position + 2, byte_size(payload) - position - 2)
        split_frames(rest, [frame | acc])

      :nomatch ->
        {Enum.reverse(acc), payload}
    end
  end

  defp parse_event(raw) do
    lines =
      raw
      |> String.trim_trailing("\n")
      |> String.split("\n")

    event =
      Enum.find_value(lines, fn
        "event:" <> value -> String.trim(value)
        _line -> nil
      end)

    data =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(fn "data:" <> value -> String.trim_leading(value) end)
      |> Enum.join("\n")

    %{raw: raw, event: event, data: data}
  end
end
