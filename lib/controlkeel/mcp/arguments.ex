defmodule ControlKeel.MCP.Arguments do
  @moduledoc false

  alias ControlKeel.LocalProject
  alias ControlKeel.Mission

  @current_aliases ["current", "active"]

  def required_integer(arguments, key) when is_map(arguments) do
    case Map.get(arguments, key) do
      nil -> {:error, {:invalid_arguments, "`#{key}` is required"}}
      value -> normalize_integer(value, key)
    end
  end

  def optional_integer(arguments, key) when is_map(arguments) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  def normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  def normalize_integer(value, key) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  def normalize_integer(value, key) when is_float(value) do
    if finite_float?(value) and value == trunc(value) do
      {:ok, trunc(value)}
    else
      {:error, {:invalid_arguments, "`#{key}` must be a finite integer if provided"}}
    end
  end

  def normalize_integer(_value, key),
    do: {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}

  def optional_top_k(arguments, opts \\ []) when is_map(arguments) do
    default = Keyword.get(opts, :default, 5)
    max = Keyword.get(opts, :max, 20)

    case Map.get(arguments, "top_k", default) do
      value when is_integer(value) and value > 0 and value <= max ->
        {:ok, value}

      value when is_binary(value) ->
        parse_top_k(value, max)

      value when is_float(value) and value > 0 and value <= max and value == trunc(value) ->
        {:ok, trunc(value)}

      _other ->
        {:error, {:invalid_arguments, "`top_k` must be between 1 and #{max}"}}
    end
  end

  def fetch_session(arguments, opts \\ []) when is_map(arguments) do
    preload_context? = Keyword.get(opts, :preload_context, false)

    with {:ok, session_id} <- resolve_session_id(arguments) do
      session =
        if preload_context?,
          do: Mission.get_session_context(session_id),
          else: Mission.get_session(session_id)

      case session do
        nil -> {:error, {:invalid_arguments, "Session not found"}}
        session -> {:ok, session}
      end
    end
  end

  def validate_task(nil, _session_id), do: :ok

  def validate_task(task_id, session_id) do
    case Mission.get_task(task_id) do
      %{session_id: ^session_id} -> :ok
      nil -> {:error, {:invalid_arguments, "`task_id` was not found"}}
      _other -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  end

  def resolve_session_id(arguments) when is_map(arguments) do
    case Map.get(arguments, "session_id") do
      nil -> resolve_active_session_id(arguments)
      value when is_binary(value) -> resolve_binary_session_id(String.trim(value), arguments)
      value -> normalize_integer(value, "session_id")
    end
  end

  def project_root(arguments) when is_map(arguments) do
    case Map.get(arguments, "project_root") do
      value when is_binary(value) and value != "" -> Path.expand(value)
      _ -> File.cwd!()
    end
  end

  defp resolve_binary_session_id(value, arguments) do
    if String.downcase(value) in @current_aliases do
      resolve_active_session_id(arguments)
    else
      normalize_integer(value, "session_id")
    end
  end

  defp resolve_active_session_id(arguments) do
    case LocalProject.load(project_root(arguments)) do
      {:ok, _binding, session} ->
        {:ok, session.id}

      _ ->
        {:error,
         {:invalid_arguments,
          "`session_id` must be an integer. For `current`, run from a bound project or pass `project_root` with an active binding."}}
    end
  end

  defp parse_top_k(value, max) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 and parsed <= max -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`top_k` must be between 1 and #{max}"}}
    end
  end

  defp finite_float?(value), do: value == value and value not in [:infinity, :negative_infinity]
end
