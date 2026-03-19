defmodule ControlKeel.Types.JsonList do
  @moduledoc false

  use Ecto.Type

  def type, do: :string

  def cast(value) when is_list(value), do: {:ok, value}

  def cast(value) when is_binary(value) do
    load(value)
  end

  def cast(_value), do: :error

  def load(nil), do: {:ok, []}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> {:ok, list}
      _ -> :error
    end
  end

  def dump(value) when is_list(value), do: {:ok, Jason.encode!(value)}
  def dump(nil), do: {:ok, Jason.encode!([])}
  def dump(_value), do: :error
end
