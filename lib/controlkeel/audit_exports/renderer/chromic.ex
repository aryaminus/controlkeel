defmodule ControlKeel.AuditExports.Renderer.Chromic do
  @moduledoc false

  @behaviour ControlKeel.AuditExports.Renderer

  @impl true
  def render(html) when is_binary(html) do
    if Code.ensure_loaded?(ChromicPDF) do
      try do
        result = apply(ChromicPDF, :print_to_pdf, [{:html, html}])

        case result do
          {:ok, binary} when is_binary(binary) -> {:ok, binary}
          binary when is_binary(binary) -> {:ok, binary}
          {:error, _reason} = error -> error
          other -> {:error, {:unexpected_renderer_result, other}}
        end
      rescue
        error -> {:error, {:renderer_failed, Exception.message(error)}}
      end
    else
      {:error, :renderer_unavailable}
    end
  end
end
