defmodule ControlKeel.Cloud.RuntimeDispatcher do
  @moduledoc """
  Behavior + lookup for the runtime-specific dispatch step that moves a
  `RunPackage` from `pending` to `dispatched`.

  Per architectural decision D1 (roadmap §5), dispatch is intentionally
  *out of band* from the run-package row: ControlKeel issues the package
  and a single-use callback token, and a runtime-specific implementation
  delivers that envelope to its target runtime (Devin's web/API, an
  Open SWE worker, a Cloudflare Worker queue, etc.).

  Each implementation receives the package and the raw callback token and
  returns either `{:ok, dispatch_metadata}` — an arbitrary JSON-safe map
  describing what happened (provider ticket id, queue URL, dashboard link)
  — or `{:error, reason}`.

  The default mapping for every runtime target is `Manual`, which records
  that a human operator will hand-deliver the package out of band. Real
  runtime modules register themselves through application config:

      config :controlkeel, :cloud_dispatchers, %{
        "devin" => MyApp.DevinDispatcher,
        "devin" => MyApp.DevinDispatcher
      }

  Unmapped runtimes fall back to `Manual` so the audit trail still shows
  a clean `pending → dispatched` transition for human-driven workflows.
  """

  alias ControlKeel.Cloud.RunPackage

  @type dispatch_metadata :: map()

  @callback dispatch(RunPackage.t(), keyword()) ::
              {:ok, dispatch_metadata()} | {:error, term()}

  @doc """
  Resolve the dispatcher module for a runtime target.

  Returns the configured module from `:cloud_dispatchers`, or the `Manual`
  default if no override is registered.
  """
  @spec for_runtime(String.t()) :: module()
  def for_runtime(runtime_target) when is_binary(runtime_target) do
    configured = Application.get_env(:controlkeel, :cloud_dispatchers, %{})

    case Map.fetch(configured, runtime_target) do
      {:ok, module} -> module
      :error -> fallback_dispatcher()
    end
  end

  defp fallback_dispatcher do
    if ControlKeel.Runtime.remote?(), do: __MODULE__.RemoteRequired, else: __MODULE__.Manual
  end
end
