defmodule ControlKeel.Policy.Snapshot do
  @moduledoc false

  alias ControlKeel.Policy.PackLoader
  alias ControlKeel.Policy.Rule

  @version 1

  def identity(opts \\ []) do
    requested_packs =
      opts
      |> Keyword.get(:policy_packs, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.sort()

    domain_pack = opts[:domain_pack]
    packs = PackLoader.all_packs()

    %{
      "version" => @version,
      "domain_pack" => domain_pack,
      "policy_packs" => requested_packs,
      "packs_hash" => hash(packs_payload(packs)),
      "captured_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  def artifact(content, attrs \\ [])

  def artifact(content, attrs) when is_binary(content) do
    %{
      "content_sha256" => hash(content),
      "content_bytes" => byte_size(content)
    }
    |> maybe_put("path", attrs[:path])
    |> maybe_put("kind", attrs[:kind])
    |> maybe_put("base_ref", attrs[:base_ref])
    |> maybe_put("head_ref", attrs[:head_ref])
    |> maybe_put("base_sha", attrs[:base_sha])
    |> maybe_put("head_sha", attrs[:head_sha])
  end

  def artifact(_content, attrs) do
    %{}
    |> maybe_put("path", attrs[:path])
    |> maybe_put("kind", attrs[:kind])
    |> maybe_put("base_ref", attrs[:base_ref])
    |> maybe_put("head_ref", attrs[:head_ref])
    |> maybe_put("base_sha", attrs[:base_sha])
    |> maybe_put("head_sha", attrs[:head_sha])
  end

  def hash(value) when is_binary(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  def hash(value), do: value |> :erlang.term_to_binary() |> hash()

  defp packs_payload(packs) do
    packs
    |> Enum.map(fn {name, rules} -> {name, Enum.map(rules, &rule_payload/1)} end)
    |> Enum.sort_by(fn {name, _rules} -> name end)
  end

  defp rule_payload(%Rule{} = rule) do
    %{
      id: rule.id,
      category: rule.category,
      severity: rule.severity,
      action: rule.action,
      plain_message: rule.plain_message,
      matcher: rule.matcher
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
