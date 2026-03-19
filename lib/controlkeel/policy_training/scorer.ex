defmodule ControlKeel.PolicyTraining.Scorer do
  @moduledoc false

  def score_router(artifact, features) do
    with {:ok, value} <- score(artifact, features) do
      {:ok, value}
    end
  end

  def score_budget_hint(artifact, features) do
    with {:ok, value} <- score(artifact, features) do
      {:ok, clamp_probability(value)}
    end
  end

  def score(artifact, features) when is_map(features) do
    artifact_payload = artifact_payload(artifact)
    feature_spec = feature_spec(artifact)

    with %{} = payload <- artifact_payload,
         %{} = spec <- feature_spec,
         input <- vectorize(features, spec, payload),
         {:ok, [value | _rest]} <- forward(input, payload["network"]) do
      {:ok, value}
    else
      nil -> {:error, :invalid_artifact}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_artifact}
    end
  end

  defp artifact_payload(%{artifact: artifact}) when is_map(artifact), do: artifact
  defp artifact_payload(artifact) when is_map(artifact), do: artifact
  defp artifact_payload(_artifact), do: nil

  defp feature_spec(%{feature_spec: spec}) when is_map(spec), do: spec
  defp feature_spec(artifact) when is_map(artifact), do: Map.get(artifact, "feature_spec")
  defp feature_spec(_artifact), do: nil

  defp vectorize(features, spec, payload) do
    normalized = stringify_keys(features)
    numeric = Enum.map(spec["numeric_features"] || [], &numeric_value(normalized, &1, payload))

    categorical =
      Enum.flat_map(spec["categorical_features"] || [], &one_hot(normalized, &1, payload))

    numeric ++ categorical
  end

  defp numeric_value(features, name, payload) do
    value =
      case Map.get(features, name) do
        value when is_integer(value) -> value * 1.0
        value when is_float(value) -> value
        value when is_binary(value) -> parse_float(value)
        true -> 1.0
        false -> 0.0
        _other -> 0.0
      end

    normalization = get_in(payload, ["normalization", name]) || %{}
    mean = parse_float(Map.get(normalization, "mean", 0.0))
    scale = max(parse_float(Map.get(normalization, "scale", 1.0)), 1.0e-6)

    (value - mean) / scale
  end

  defp one_hot(features, name, payload) do
    vocab = get_in(payload, ["categorical_vocab", name]) || []
    raw = Map.get(features, name)

    value =
      cond do
        is_binary(raw) -> raw
        is_atom(raw) -> Atom.to_string(raw)
        is_nil(raw) -> "__unknown__"
        true -> to_string(raw)
      end

    encoded_value =
      if value in vocab do
        value
      else
        if "__unknown__" in vocab, do: "__unknown__", else: value
      end

    Enum.map(vocab, fn candidate ->
      if candidate == encoded_value, do: 1.0, else: 0.0
    end)
  end

  defp forward(input, %{"layers" => layers}) when is_list(layers) do
    Enum.reduce_while(layers, {:ok, input}, fn layer, {:ok, activations} ->
      case apply_layer(activations, layer) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp forward(_input, _network), do: {:error, :invalid_network}

  defp apply_layer(input, %{"weights" => weights, "biases" => biases} = layer)
       when is_list(weights) and is_list(biases) do
    if length(weights) != length(biases) do
      {:error, :invalid_layer}
    else
      outputs =
        Enum.zip(weights, biases)
        |> Enum.map(fn {row, bias} ->
          dot = dot_product(input, row) + parse_float(bias)
          activate(dot, Map.get(layer, "activation", "identity"))
        end)

      {:ok, outputs}
    end
  end

  defp apply_layer(_input, _layer), do: {:error, :invalid_layer}

  defp dot_product(input, weights) do
    input
    |> Enum.zip(weights)
    |> Enum.reduce(0.0, fn {left, right}, acc ->
      acc + parse_float(left) * parse_float(right)
    end)
  end

  defp activate(value, "relu"), do: max(value, 0.0)
  defp activate(value, "sigmoid"), do: clamp_probability(1.0 / (1.0 + :math.exp(-value)))
  defp activate(value, "tanh"), do: :math.tanh(value)
  defp activate(value, _identity), do: value

  defp clamp_probability(value) when value < 0.0, do: 0.0
  defp clamp_probability(value) when value > 1.0, do: 1.0
  defp clamp_probability(value), do: value

  defp parse_float(value) when is_integer(value), do: value * 1.0
  defp parse_float(value) when is_float(value), do: value

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0.0
    end
  end

  defp parse_float(_value), do: 0.0

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys(value)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
