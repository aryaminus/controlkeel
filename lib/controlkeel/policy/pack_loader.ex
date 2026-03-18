defmodule ControlKeel.Policy.PackLoader do
  @moduledoc false

  alias ControlKeel.Policy.Rule

  @cache_key {__MODULE__, :packs}

  def load(pack_name) when is_binary(pack_name) do
    with {:ok, packs} <- load_cache() do
      case Map.fetch(packs, pack_name) do
        {:ok, pack} -> {:ok, pack}
        :error -> {:error, {:pack_not_found, pack_name}}
      end
    end
  end

  def load!(pack_name) do
    case load(pack_name) do
      {:ok, pack} -> pack
      {:error, reason} -> raise "unable to load policy pack #{pack_name}: #{inspect(reason)}"
    end
  end

  def load_from_path(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents),
         {:ok, rules} <- decode_rules(decoded) do
      {:ok, rules}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:decode_failed, path, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp load_cache do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        with {:ok, packs} <- load_all_packs() do
          :persistent_term.put(@cache_key, packs)
          {:ok, packs}
        end

      packs ->
        {:ok, packs}
    end
  end

  defp load_all_packs do
    Application.app_dir(:controlkeel, "priv/policy_packs/*.json")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      name = path |> Path.basename(".json")

      case load_from_path(path) do
        {:ok, rules} -> {:cont, {:ok, Map.put(acc, name, rules)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp decode_rules(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn raw_rule, {:ok, acc} ->
      case decode_rule(raw_rule) do
        {:ok, rule} -> {:cont, {:ok, [rule | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rules} -> {:ok, Enum.reverse(rules)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_rules(_other), do: {:error, :invalid_pack_format}

  defp decode_rule(%{
         "id" => id,
         "category" => category,
         "severity" => severity,
         "action" => action,
         "plain_message" => plain_message,
         "matcher" => matcher
       })
       when is_map(matcher) do
    {:ok,
     %Rule{
       id: id,
       category: category,
       severity: severity,
       action: action,
       plain_message: plain_message,
       matcher: matcher
     }}
  end

  defp decode_rule(_other), do: {:error, :invalid_rule}
end
