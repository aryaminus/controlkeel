defmodule ControlKeel.Proxy.Errors do
  @moduledoc false

  @error_code "controlkeel_policy_violation"

  def http(:openai, summary) do
    %{
      "error" => %{
        "message" => summary,
        "type" => "invalid_request_error",
        "param" => nil,
        "code" => @error_code
      }
    }
  end

  def http(:anthropic, summary) do
    %{
      "type" => "error",
      "error" => %{
        "type" => "invalid_request_error",
        "message" => summary,
        "code" => @error_code
      }
    }
  end

  def sse(:openai, summary) do
    "data: " <> Jason.encode!(http(:openai, summary)) <> "\n\n"
  end

  def sse(:anthropic, summary) do
    "event: error\ndata: " <> Jason.encode!(http(:anthropic, summary)) <> "\n\n"
  end

  def websocket(summary) do
    Jason.encode!(%{
      "type" => "error",
      "error" => %{
        "type" => "invalid_request_error",
        "code" => @error_code,
        "message" => summary
      }
    })
  end
end
