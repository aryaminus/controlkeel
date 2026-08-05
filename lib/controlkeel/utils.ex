defmodule ControlKeel.Utils do
  @moduledoc false

  @doc """
  Shallow key stringification: converts top-level keys to strings, leaves values untouched.
  """
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  @doc """
  Deep key stringification: recursively converts map keys to strings, recursing into
  nested maps and lists. Non-map/non-list values pass through unchanged.
  """
  def stringify_keys_deep(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_map(value) -> {to_string(key), stringify_keys_deep(value)}
      {key, value} -> {to_string(key), value}
    end)
  end

  def stringify_keys_deep(value), do: value

  @doc """
  Deep key stringification with list recursion: recursively converts map keys to
  strings, recursing into nested maps and lists. Non-map/non-list values pass
  through unchanged. Returns `%{}` for non-map inputs.
  """
  def stringify_keys_deep_list(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_keys_deep_list_value(value)}
    end)
  end

  def stringify_keys_deep_list(_other), do: %{}

  defp stringify_keys_deep_list_value(value) when is_map(value),
    do: stringify_keys_deep_list(value)

  defp stringify_keys_deep_list_value(value) when is_list(value),
    do: Enum.map(value, &stringify_keys_deep_list_value/1)

  defp stringify_keys_deep_list_value(value), do: value

  @doc """
  Converts nil and empty strings to nil, passes through all other values.
  """
  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  @doc """
  Normalizes a value against an allowed list. Returns the trimmed value if valid, otherwise the default.
  """
  def normalize_enum(nil, _allowed, default), do: default

  def normalize_enum(value, allowed, default) when is_binary(value) do
    normalized = String.trim(value)
    if normalized in allowed, do: normalized, else: default
  end

  def normalize_enum(_value, _allowed, default), do: default

  @doc """
  Returns true for truthy values: true, "true", "True", 1, "1", "yes".
  """
  def truthy?(value) when value in [true, "true", "True", 1, "1", "yes"], do: true
  def truthy?(_value), do: false

  @doc """
  Returns true for falsey values: false, "false", "False", 0, "0", "no".
  """
  def falsey?(value) when value in [false, "false", "False", 0, "0", "no"], do: true
  def falsey?(_value), do: false

  @doc """
  Ensures the input is a map; returns %{} for non-map values.
  """
  def ensure_map(value) when is_map(value), do: value
  def ensure_map(_value), do: %{}

  @doc """
  Normalizes tags from a list, comma-separated string, or other value into a list of strings.
  """
  def normalize_tags(tags) when is_list(tags), do: Enum.map(tags, &to_string/1)

  def normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def normalize_tags(_tags), do: []

  @doc """
  Formats Ecto changeset errors into a human-readable string.
  """
  def format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field}: #{msg}" end)
    |> Enum.join("; ")
  end

  @doc """
  Fetches a session by ID. Returns {:ok, session} or {:error, {:invalid_arguments, reason}}.
  """
  def fetch_session(session_id) do
    case ControlKeel.Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end
end
