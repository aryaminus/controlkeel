defmodule ControlKeel.Runtime do
  @moduledoc false

  def mode do
    Application.get_env(:controlkeel, :runtime_mode, :local)
  end

  def local?, do: mode() == :local
  def cloud?, do: mode() == :cloud

  def bus do
    Application.get_env(:controlkeel, :bus, default_bus())
  end

  def bus_module do
    case bus() do
      :nats -> ControlKeel.Bus.Nats
      _ -> ControlKeel.Bus.Local
    end
  end

  def pdf_renderer do
    case Application.get_env(:controlkeel, :pdf_renderer, :chromic) do
      :chromic -> ControlKeel.AuditExports.Renderer.Chromic
      module when is_atom(module) -> module
      _ -> ControlKeel.AuditExports.Renderer.Chromic
    end
  end

  def cloud_repo_enabled? do
    cloud?() and Application.get_env(:controlkeel, ControlKeel.CloudRepo, []) != []
  end

  def memory_store_mode do
    if cloud_repo_enabled?(), do: :pgvector, else: :sqlite
  end

  defp default_bus do
    if cloud?(), do: :nats, else: :local
  end
end
