defmodule ControlKeel.TestSupport.AuthorizedProtocol do
  @moduledoc false

  alias ControlKeel.MCP.Protocol

  def handle_request(request, opts \\ []) do
    Protocol.handle_request(request, Keyword.put_new(opts, :authorize, fn _, _ -> :ok end))
  end

  defdelegate tool_schemas(opts \\ []), to: Protocol
end
