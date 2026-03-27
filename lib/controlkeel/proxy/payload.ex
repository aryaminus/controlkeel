defmodule ControlKeel.Proxy.Payload do
  @moduledoc false

  @textual_part_types ~w(text input_text output_text message delta)
  @string_keys ~w(text input_text output_text instructions system prompt content)
  @container_keys ~w(content input output message messages parts delta response item)

  def extract_request(:openai, :responses, payload) when is_map(payload) do
    %{
      text: join_texts([payload["instructions"], payload["input"]]),
      model: payload["model"],
      stream?: payload["stream"] == true,
      max_output_tokens: payload["max_output_tokens"] || payload["max_completion_tokens"],
      metadata: %{}
    }
  end

  def extract_request(:openai, :chat_completions, payload) when is_map(payload) do
    %{
      text:
        join_texts([
          payload["system"],
          Enum.flat_map(payload["messages"] || [], &texts_from_message/1)
        ]),
      model: payload["model"],
      stream?: payload["stream"] == true,
      max_output_tokens:
        payload["max_completion_tokens"] || payload["max_tokens"] || payload["max_output_tokens"],
      metadata: %{}
    }
  end

  def extract_request(:openai, :completions, payload) when is_map(payload) do
    %{
      text: join_texts([payload["prompt"], payload["suffix"]]),
      model: payload["model"],
      stream?: payload["stream"] == true,
      max_output_tokens: payload["max_tokens"] || payload["max_output_tokens"],
      metadata: %{}
    }
  end

  def extract_request(:openai, :embeddings, payload) when is_map(payload) do
    %{
      text: join_texts([payload["input"]]),
      model: payload["model"],
      stream?: false,
      max_output_tokens: nil,
      metadata: %{}
    }
  end

  def extract_request(:anthropic, :messages, payload) when is_map(payload) do
    %{
      text:
        join_texts([
          payload["system"],
          Enum.flat_map(payload["messages"] || [], &texts_from_message/1)
        ]),
      model: payload["model"],
      stream?: payload["stream"] == true,
      max_output_tokens: payload["max_tokens"],
      metadata: %{}
    }
  end

  def extract_request(_provider, _tool, payload) when is_map(payload) do
    %{
      text: join_texts(texts_from_tree(payload)),
      model: payload["model"],
      stream?: payload["stream"] == true,
      max_output_tokens: payload["max_tokens"] || payload["max_output_tokens"],
      metadata: %{}
    }
  end

  def extract_response(provider, tool, payload) when is_map(payload) do
    %{
      text: response_text(provider, tool, payload),
      usage: extract_usage(payload)
    }
  end

  def extract_sse_event(_provider, _tool, %{data: "[DONE]"}) do
    %{text: "", usage: nil, done?: true}
  end

  def extract_sse_event(provider, tool, %{data: data}) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, payload} ->
        response = extract_response(provider, tool, payload)
        Map.put(response, :done?, false)

      {:error, _error} ->
        %{text: "", usage: nil, done?: false}
    end
  end

  def extract_ws_frame(payload) when is_map(payload) do
    %{
      text: join_texts(texts_from_tree(payload)),
      model: payload["model"] || get_in(payload, ["response", "model"]),
      max_output_tokens:
        payload["max_output_tokens"] || payload["max_response_output_tokens"] ||
          get_in(payload, ["response", "max_output_tokens"]),
      usage: extract_usage(payload)
    }
  end

  def response_text(:openai, :chat_completions, payload) do
    choices = payload["choices"] || []

    join_texts(
      Enum.flat_map(choices, fn choice ->
        [
          get_in(choice, ["message", "content"]),
          get_in(choice, ["delta", "content"]),
          get_in(choice, ["delta", "text"])
        ]
      end)
    )
  end

  def response_text(:openai, :completions, payload) do
    payload["choices"]
    |> List.wrap()
    |> Enum.map(&Map.get(&1, "text"))
    |> join_texts()
  end

  def response_text(:openai, :embeddings, _payload), do: ""

  def response_text(:openai, :models, payload) do
    payload["data"]
    |> List.wrap()
    |> Enum.map(&Map.get(&1, "id"))
    |> join_texts()
  end

  def response_text(:anthropic, :messages, payload) do
    join_texts([payload["content"], get_in(payload, ["delta", "text"])])
  end

  def response_text(_provider, _tool, payload) do
    join_texts(texts_from_tree(payload))
  end

  def extract_usage(payload) when is_map(payload) do
    payload
    |> locate_usage()
    |> normalize_usage()
  end

  def extract_usage(_payload), do: nil

  defp texts_from_message(message) when is_binary(message), do: [message]

  defp texts_from_message(message) when is_map(message) do
    joinable =
      [
        message["content"],
        message["text"],
        message["input_text"],
        message["output_text"]
      ]

    joinable
    |> Enum.flat_map(&texts_from_tree/1)
  end

  defp texts_from_message(message) when is_list(message),
    do: Enum.flat_map(message, &texts_from_message/1)

  defp texts_from_message(_message), do: []

  defp texts_from_tree(value) when is_binary(value), do: [value]
  defp texts_from_tree(nil), do: []
  defp texts_from_tree(value) when is_list(value), do: Enum.flat_map(value, &texts_from_tree/1)

  defp texts_from_tree(value) when is_map(value) do
    part_type = Map.get(value, "type")

    direct =
      cond do
        part_type in @textual_part_types and is_binary(value["text"]) ->
          [value["text"]]

        true ->
          []
      end

    direct ++
      Enum.flat_map(@string_keys, fn key ->
        case Map.get(value, key) do
          binary when is_binary(binary) -> [binary]
          nested -> texts_from_tree(nested)
        end
      end) ++
      Enum.flat_map(@container_keys, fn key -> texts_from_tree(Map.get(value, key)) end)
  end

  defp texts_from_tree(_value), do: []

  defp join_texts(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(&texts_from_tree/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp locate_usage(%{"usage" => usage}) when is_map(usage), do: usage

  defp locate_usage(payload) when is_map(payload) do
    Enum.find_value(payload, fn {_key, value} ->
      cond do
        is_map(value) ->
          usage = locate_usage(value)
          if usage == %{}, do: nil, else: usage

        is_list(value) ->
          Enum.find_value(value, &locate_usage/1)

        true ->
          nil
      end
    end) || %{}
  end

  defp locate_usage(_payload), do: %{}

  defp normalize_usage(%{} = usage) do
    input_tokens = usage["input_tokens"] || usage["prompt_tokens"] || 0
    output_tokens = usage["output_tokens"] || usage["completion_tokens"] || 0
    cached_input_tokens = usage["cached_input_tokens"] || 0

    if input_tokens == 0 and output_tokens == 0 and cached_input_tokens == 0 do
      nil
    else
      %{
        input_tokens: normalize_int(input_tokens),
        output_tokens: normalize_int(output_tokens),
        cached_input_tokens: normalize_int(cached_input_tokens)
      }
    end
  end

  defp normalize_usage(_usage), do: nil

  defp normalize_int(value) when is_integer(value), do: max(value, 0)

  defp normalize_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> max(parsed, 0)
      _ -> 0
    end
  end

  defp normalize_int(_value), do: 0
end
