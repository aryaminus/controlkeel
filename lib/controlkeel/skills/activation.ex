defmodule ControlKeel.Skills.Activation do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def mark_loaded(name, project_root, session_id) do
    GenServer.call(@name, {:mark_loaded, key(name, project_root, session_id)})
  end

  def reset do
    GenServer.call(@name, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_call({:mark_loaded, key}, _from, loaded) do
    if MapSet.member?(loaded, key) do
      emit_activation(key, :duplicate)
      {:reply, :duplicate, loaded}
    else
      emit_activation(key, :new)
      {:reply, :new, MapSet.put(loaded, key)}
    end
  end

  def handle_call(:reset, _from, _loaded), do: {:reply, :ok, MapSet.new()}

  defp key(name, project_root, session_id) do
    {
      to_string(name),
      project_root && Path.expand(project_root),
      session_id && to_string(session_id)
    }
  end

  defp emit_activation({name, project_root, session_id}, state) do
    :telemetry.execute(
      [:controlkeel, :skills, :activated],
      %{count: 1},
      %{
        skill_name: name,
        project_root: project_root,
        session_id: session_id,
        activation: to_string(state)
      }
    )
  end
end
