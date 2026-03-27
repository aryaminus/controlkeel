defmodule ControlKeel.Proxy.PayloadTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Proxy.{Payload, SSE}

  test "extracts openai responses input text and metadata" do
    payload = %{
      "model" => "gpt-5.4-mini",
      "input" => [
        %{"role" => "user", "content" => [%{"type" => "input_text", "text" => "Build an API"}]}
      ],
      "stream" => true,
      "max_output_tokens" => 256
    }

    extracted = Payload.extract_request(:openai, :responses, payload)

    assert extracted.text =~ "Build an API"
    assert extracted.model == "gpt-5.4-mini"
    assert extracted.stream? == true
    assert extracted.max_output_tokens == 256
  end

  test "extracts openai chat completions messages" do
    payload = %{
      "model" => "gpt-5.4-mini",
      "messages" => [
        %{"role" => "system", "content" => "Keep it short"},
        %{"role" => "user", "content" => [%{"type" => "text", "text" => "Ship this"}]}
      ]
    }

    extracted = Payload.extract_request(:openai, :chat_completions, payload)
    assert extracted.text =~ "Keep it short"
    assert extracted.text =~ "Ship this"
  end

  test "extracts anthropic messages request text" do
    payload = %{
      "model" => "claude-sonnet-4.6",
      "system" => "Act as a reviewer",
      "messages" => [
        %{"role" => "user", "content" => [%{"type" => "text", "text" => "Audit this"}]}
      ]
    }

    extracted = Payload.extract_request(:anthropic, :messages, payload)
    assert extracted.text =~ "Act as a reviewer"
    assert extracted.text =~ "Audit this"
  end

  test "extracts openai completions prompt text" do
    payload = %{
      "model" => "gpt-5.4-mini",
      "prompt" => "Finish this migration",
      "max_tokens" => 128
    }

    extracted = Payload.extract_request(:openai, :completions, payload)

    assert extracted.text =~ "Finish this migration"
    assert extracted.model == "gpt-5.4-mini"
    assert extracted.max_output_tokens == 128
  end

  test "extracts openai embeddings input text" do
    payload = %{
      "model" => "text-embedding-3-large",
      "input" => ["search this customer note", "and this policy"]
    }

    extracted = Payload.extract_request(:openai, :embeddings, payload)

    assert extracted.text =~ "search this customer note"
    assert extracted.text =~ "and this policy"
    assert extracted.stream? == false
  end

  test "extracts openai models response ids" do
    payload = %{"data" => [%{"id" => "gpt-5.4-mini"}, %{"id" => "gpt-5.4"}]}

    assert Payload.extract_response(:openai, :models, payload).text =~ "gpt-5.4-mini"
    assert Payload.extract_response(:openai, :models, payload).text =~ "gpt-5.4"
  end

  test "parses SSE frames across chunk boundaries" do
    state = SSE.new()

    {events, state} =
      SSE.push(state, "data: {\"type\":\"response.output_text.delta\",\"text\":\"hel")

    assert events == []

    {events, _state} = SSE.push(state, "lo\"}\n\ndata: [DONE]\n\n")

    assert Enum.map(events, & &1.data) == [
             "{\"type\":\"response.output_text.delta\",\"text\":\"hello\"}",
             "[DONE]"
           ]
  end
end
