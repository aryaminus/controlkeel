defmodule ControlKeel.Intent.RouterTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Intent
  alias ControlKeel.Intent.ExecutionBrief
  alias ControlKeel.Intent.Prompt
  alias ControlKeel.Intent.Providers.{Anthropic, Ollama, OpenAI, OpenRouter}

  import ControlKeel.IntentFixtures

  setup do
    original = Application.get_env(:controlkeel, ControlKeel.Intent)

    on_exit(fn ->
      if original do
        Application.put_env(:controlkeel, ControlKeel.Intent, original)
      else
        Application.delete_env(:controlkeel, ControlKeel.Intent)
      end
    end)

    :ok
  end

  test "openai adapter maps structured output to the shared brief schema" do
    bypass = Bypass.open()

    payload =
      provider_brief_payload(%{
        "occupation" => "Founder / Product Builder",
        "domain_pack" => "software",
        "risk_tier" => "high"
      })

    Bypass.expect_once(bypass, "POST", "/v1/responses", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{"model" => "gpt-5.4", "output_text" => Jason.encode!(payload)})
      )
    end)

    put_intent_config(%{
      providers: %{
        openai: %{api_key: "openai-test", base_url: base_url(bypass), model: "gpt-5.4"}
      }
    })

    assert {:ok, brief_map, %{"model" => "gpt-5.4"}} =
             OpenAI.compile(Prompt.build(sample_intent_attrs(%{"occupation" => "founder"})), [])

    assert {:ok, brief} =
             ExecutionBrief.from_provider_response(
               brief_map,
               compiler_metadata(%{
                 "provider" => "openai",
                 "model" => "gpt-5.4",
                 "occupation" => "founder",
                 "domain_pack" => "software"
               })
             )

    assert brief.domain_pack == "software"
    assert brief.risk_tier == "high"
  end

  test "anthropic adapter maps tool output to the shared brief schema" do
    bypass = Bypass.open()
    payload = provider_brief_payload()

    Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "claude-sonnet-4-5",
          "content" => [%{"type" => "tool_use", "input" => payload}]
        })
      )
    end)

    put_intent_config(%{
      providers: %{
        anthropic: %{
          api_key: "anthropic-test",
          base_url: base_url(bypass),
          model: "claude-sonnet-4-5"
        }
      }
    })

    assert {:ok, brief_map, %{"model" => "claude-sonnet-4-5"}} =
             Anthropic.compile(Prompt.build(sample_intent_attrs()), [])

    assert {:ok, brief} =
             ExecutionBrief.from_provider_response(
               brief_map,
               compiler_metadata(%{"provider" => "anthropic", "model" => "claude-sonnet-4-5"})
             )

    assert brief.domain_pack == "healthcare"
    assert brief.risk_tier == "critical"
  end

  test "openrouter adapter maps structured output to the shared brief schema" do
    bypass = Bypass.open()

    payload =
      provider_brief_payload(%{
        "occupation" => "Education",
        "domain_pack" => "education",
        "risk_tier" => "moderate"
      })

    Bypass.expect_once(bypass, "POST", "/api/v1/chat/completions", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "openrouter/claude",
          "choices" => [%{"message" => %{"content" => Jason.encode!(payload)}}]
        })
      )
    end)

    put_intent_config(%{
      providers: %{
        openrouter: %{
          api_key: "openrouter-test",
          base_url: base_url(bypass),
          model: "openrouter/claude"
        }
      }
    })

    assert {:ok, brief_map, %{"model" => "openrouter/claude"}} =
             OpenRouter.compile(
               Prompt.build(sample_intent_attrs(%{"occupation" => "education"})),
               []
             )

    assert {:ok, brief} =
             ExecutionBrief.from_provider_response(
               brief_map,
               compiler_metadata(%{
                 "provider" => "openrouter",
                 "model" => "openrouter/claude",
                 "occupation" => "education",
                 "domain_pack" => "education"
               })
             )

    assert brief.domain_pack == "education"
  end

  test "ollama adapter maps structured output to the shared brief schema" do
    bypass = Bypass.open()

    payload =
      provider_brief_payload(%{
        "occupation" => "Founder / Product Builder",
        "domain_pack" => "software",
        "risk_tier" => "moderate"
      })

    Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "llama3.2",
          "message" => %{"content" => Jason.encode!(payload)}
        })
      )
    end)

    put_intent_config(%{
      providers: %{
        ollama: %{base_url: base_url(bypass), model: "llama3.2"}
      }
    })

    assert {:ok, brief_map, %{"model" => "llama3.2"}} =
             Ollama.compile(Prompt.build(sample_intent_attrs(%{"occupation" => "founder"})), [])

    assert {:ok, brief} =
             ExecutionBrief.from_provider_response(
               brief_map,
               compiler_metadata(%{
                 "provider" => "ollama",
                 "model" => "llama3.2",
                 "occupation" => "founder",
                 "domain_pack" => "software"
               })
             )

    assert brief.domain_pack == "software"
  end

  test "invalid schema retries once on the same provider then falls back to the next provider" do
    openai = Bypass.open()
    anthropic = Bypass.open()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    invalid = %{"objective" => "Too small"}
    valid = provider_brief_payload()

    Bypass.expect(openai, "POST", "/v1/responses", fn conn ->
      Agent.update(counter, &(&1 + 1))

      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{"model" => "gpt-5.4", "output_text" => Jason.encode!(invalid)})
      )
    end)

    Bypass.expect_once(anthropic, "POST", "/v1/messages", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "claude-sonnet-4-5",
          "content" => [%{"type" => "tool_use", "input" => valid}]
        })
      )
    end)

    put_intent_config(%{
      default_provider: nil,
      dev_fallback: false,
      providers: %{
        openai: %{api_key: "openai-test", base_url: base_url(openai), model: "gpt-5.4"},
        anthropic: %{
          api_key: "anthropic-test",
          base_url: base_url(anthropic),
          model: "claude-sonnet-4-5"
        },
        openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
        ollama: %{base_url: "http://127.0.0.1:1", model: "unused"}
      }
    })

    assert {:ok, brief} =
             Intent.compile(sample_intent_attrs(),
               providers: [:openai, :anthropic],
               allow_dev_fallback: false
             )

    assert brief.compiler["provider"] == "anthropic"
    assert Agent.get(counter, & &1) == 2
  end

  test "missing credentials skip a provider cleanly" do
    anthropic = Bypass.open()

    Bypass.expect_once(anthropic, "POST", "/v1/messages", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "claude-sonnet-4-5",
          "content" => [%{"type" => "tool_use", "input" => provider_brief_payload()}]
        })
      )
    end)

    put_intent_config(%{
      providers: %{
        openai: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "gpt-5.4"},
        anthropic: %{
          api_key: "anthropic-test",
          base_url: base_url(anthropic),
          model: "claude-sonnet-4-5"
        },
        openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
        ollama: %{base_url: "http://127.0.0.1:1", model: "unused"}
      }
    })

    assert {:ok, brief} =
             Intent.compile(sample_intent_attrs(),
               providers: [:openai, :anthropic],
               allow_dev_fallback: false
             )

    assert brief.compiler["provider"] == "anthropic"
  end

  test "ollama unavailability does not crash the compile path" do
    anthropic = Bypass.open()

    Bypass.expect_once(anthropic, "POST", "/v1/messages", fn conn ->
      Plug.Conn.resp(
        conn,
        200,
        Jason.encode!(%{
          "model" => "claude-sonnet-4-5",
          "content" => [%{"type" => "tool_use", "input" => provider_brief_payload()}]
        })
      )
    end)

    put_intent_config(%{
      providers: %{
        ollama: %{base_url: "http://127.0.0.1:1", model: "llama3.2"},
        anthropic: %{
          api_key: "anthropic-test",
          base_url: base_url(anthropic),
          model: "claude-sonnet-4-5"
        },
        openai: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"},
        openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "unused"}
      }
    })

    assert {:ok, brief} =
             Intent.compile(sample_intent_attrs(),
               providers: [:ollama, :anthropic],
               allow_dev_fallback: false
             )

    assert brief.compiler["provider"] == "anthropic"
  end

  defp put_intent_config(overrides) do
    Application.put_env(:controlkeel, ControlKeel.Intent, deep_merge(base_config(), overrides))
  end

  defp base_config do
    %{
      default_provider: nil,
      dev_fallback: false,
      providers: %{
        anthropic: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "claude-sonnet-4-5"},
        openai: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "gpt-5.4"},
        openrouter: %{api_key: nil, base_url: "http://127.0.0.1:1", model: "openrouter/test"},
        ollama: %{base_url: "http://127.0.0.1:1", model: "llama3.2"}
      }
    }
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp base_url(bypass), do: "http://127.0.0.1:#{bypass.port}"
end
