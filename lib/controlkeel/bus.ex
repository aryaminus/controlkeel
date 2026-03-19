defmodule ControlKeel.Bus do
  @moduledoc false

  alias ControlKeel.Runtime

  def publish(topic, payload) when is_binary(topic) do
    Runtime.bus_module().publish(topic, payload)
  end

  def publish_json(topic, payload) when is_binary(topic) and is_map(payload) do
    Runtime.bus_module().publish_json(topic, payload)
  end
end
