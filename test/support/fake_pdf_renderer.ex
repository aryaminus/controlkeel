defmodule ControlKeel.TestSupport.FakePdfRenderer do
  @behaviour ControlKeel.AuditExports.Renderer

  @impl true
  def render(html) when is_binary(html) do
    {:ok, "%PDF-FAKE\n" <> html}
  end
end
