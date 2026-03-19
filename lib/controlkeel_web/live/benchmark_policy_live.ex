defmodule ControlKeelWeb.BenchmarkPolicyLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.PolicyTraining
  alias ControlKeel.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Policy Artifact")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case PolicyTraining.get_artifact(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Policy artifact not found.")
         |> push_navigate(to: ~p"/benchmarks")}

      artifact ->
        {:noreply,
         socket
         |> assign(:artifact, artifact)
         |> assign(:page_title, "Policy Artifact v#{artifact.version}")}
    end
  end

  @impl true
  def handle_event("promote", _params, socket) do
    case PolicyTraining.promote_artifact(socket.assigns.artifact.id) do
      {:ok, artifact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Artifact promoted to active.")
         |> assign(:artifact, artifact)}

      {:error, {:promotion_failed, reasons}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Promotion gate failed: #{Enum.join(List.wrap(reasons), "; ")}"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Promotion failed: #{inspect(reason)}")}
    end
  end

  def handle_event("archive", _params, socket) do
    case PolicyTraining.archive_artifact(socket.assigns.artifact.id) do
      {:ok, artifact} ->
        {:noreply,
         socket
         |> put_flash(:info, "Artifact archived.")
         |> assign(:artifact, Repo.preload(artifact, :training_run))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Archive failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight" id="policy-detail">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Policy artifact</p>
            <h1 class="ck-section-title">
              {String.replace(@artifact.artifact_type, "_", " ") |> String.capitalize()} v{@artifact.version}
            </h1>
            <p class="ck-lead ck-lead-tight">
              Review held-out metrics, feature spec, and promotion status before activating a learned runtime policy.
            </p>
          </div>
          <div class="ck-action-row">
            <.link navigate={~p"/benchmarks"} class="ck-link">Back to benchmarks</.link>
            <button
              :if={promotion_eligible?(@artifact)}
              id="policy-promote"
              type="button"
              phx-click="promote"
              class="ck-button-primary"
            >
              Promote
            </button>
            <button id="policy-archive" type="button" phx-click="archive" class="ck-link">
              Archive
            </button>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Status</p>
            <strong>{@artifact.status}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Model family</p>
            <strong>{@artifact.model_family}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Train run</p>
            <strong>##{@artifact.training_run_id}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Eligible</p>
            <strong>{if promotion_eligible?(@artifact), do: "yes", else: "no"}</strong>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Held-out comparison</p>
            <div class="ck-brief-grid">
              <div>
                <h3>Learned held-out</h3>
                <p class="ck-note">{format_metrics(@artifact.metrics["held_out"] || %{})}</p>
              </div>
              <div>
                <h3>Heuristic baseline</h3>
                <p class="ck-note">
                  {format_metrics(get_in(@artifact.metrics, ["baseline", "held_out"]) || %{})}
                </p>
              </div>
              <div>
                <h3>Promotion gates</h3>
                <p class="ck-note">{Enum.join(gate_reasons(@artifact), "; ")}</p>
              </div>
            </div>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Feature spec</p>
            <pre class="ck-code-block" phx-no-curly-interpolation>{Jason.encode!(@artifact.feature_spec, pretty: true)}</pre>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard" style="margin-top: 1.5rem;">
          <div class="ck-card">
            <p class="ck-mini-label">Artifact metadata</p>
            <pre class="ck-code-block" phx-no-curly-interpolation>{Jason.encode!(@artifact.metadata, pretty: true)}</pre>
          </div>
          <div class="ck-card">
            <p class="ck-mini-label">Artifact network</p>
            <pre class="ck-code-block" phx-no-curly-interpolation>{Jason.encode!(@artifact.artifact, pretty: true)}</pre>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp promotion_eligible?(artifact) do
    get_in(artifact.metrics, ["gates", "eligible"]) == true
  end

  defp gate_reasons(artifact) do
    reasons = get_in(artifact.metrics, ["gates", "reasons"]) || []
    if reasons == [], do: ["All promotion gates passed."], else: reasons
  end

  defp format_metrics(metrics) when metrics == %{}, do: "n/a"

  defp format_metrics(metrics) do
    metrics
    |> Enum.map(fn {key, value} ->
      formatted =
        cond do
          is_float(value) -> Float.round(value, 3)
          true -> value
        end

      "#{key}: #{formatted}"
    end)
    |> Enum.join(" · ")
  end
end
