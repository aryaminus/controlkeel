defmodule ControlKeel.PolicyTrainingFixtures do
  @moduledoc false

  import Ecto.Query

  alias ControlKeel.PolicyTraining.{Artifact, Run}
  alias ControlKeel.Repo

  @router_numeric_features [
    "local",
    "cost_tier_value",
    "security_tier_value",
    "swe_bench_score",
    "cap_repo_edit",
    "cap_file_write",
    "cap_bash",
    "cap_mcp",
    "cap_git",
    "cap_deploy",
    "cap_code_review",
    "cap_spec_gen",
    "cap_multi_agent",
    "cap_workflow",
    "historical_catch_rate",
    "historical_block_rate",
    "expected_rule_hit_rate",
    "median_latency_ms",
    "average_overhead_percent"
  ]
  @router_categorical_features [
    "task_type",
    "risk_tier",
    "domain_pack",
    "budget_tier",
    "subject_id",
    "subject_type"
  ]
  @budget_numeric_features [
    "input_tokens",
    "output_tokens",
    "cached_input_tokens",
    "estimated_cost_cents",
    "session_spend_ratio",
    "rolling_24h_spend_ratio",
    "active_findings_count"
  ]
  @budget_categorical_features [
    "source",
    "tool",
    "provider",
    "model",
    "domain_pack",
    "risk_tier"
  ]

  def policy_training_run_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        artifact_type: "router",
        status: "trained",
        training_scope: "benchmark_matrix",
        dataset_summary: %{"rows" => 4},
        training_metrics: %{"reward" => 1.1},
        validation_metrics: %{"reward" => 1.0},
        held_out_metrics: %{"reward" => 1.0},
        metadata: %{}
      })

    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert!()
  end

  def policy_artifact_fixture(attrs \\ %{}) do
    artifact_type = attrs[:artifact_type] || "router"

    training_run =
      Map.get_lazy(attrs, :training_run, fn ->
        policy_training_run_fixture(%{artifact_type: artifact_type})
      end)

    artifact_payload =
      Map.get_lazy(attrs, :artifact, fn ->
        default_artifact_payload(artifact_type)
      end)

    version =
      Map.get_lazy(attrs, :version, fn ->
        next_version_for(artifact_type)
      end)

    metrics =
      Map.get(attrs, :metrics, %{
        "held_out" => %{"reward" => 1.1, "precision" => 0.9, "false_positive_rate" => 0.1},
        "baseline" => %{"held_out" => %{"reward" => 1.0}},
        "gates" => %{"eligible" => true, "reasons" => []}
      })

    changes =
      attrs
      |> Enum.into(%{
        training_run_id: training_run.id,
        artifact_type: artifact_type,
        version: version,
        status: "candidate",
        model_family: artifact_payload["model_family"],
        artifact: artifact_payload,
        feature_spec: artifact_payload["feature_spec"],
        metrics: metrics,
        metadata: %{}
      })
      |> Map.delete(:training_run)

    %Artifact{}
    |> Artifact.changeset(changes)
    |> Repo.insert!()
    |> Repo.preload(:training_run)
  end

  def default_artifact_payload("router") do
    %{
      "schema_version" => 1,
      "artifact_type" => "router",
      "model_family" => "portable_linear_fallback",
      "feature_spec" => %{
        "numeric_features" => @router_numeric_features,
        "categorical_features" => @router_categorical_features
      },
      "categorical_vocab" => %{
        "task_type" => ["backend", "ui", "__unknown__"],
        "risk_tier" => ["low", "moderate", "high", "critical", "__unknown__"],
        "domain_pack" => ["software", "healthcare", "__unknown__"],
        "budget_tier" => ["free", "low", "medium", "high", "__unknown__"],
        "subject_id" => ["ollama", "openai", "__unknown__"],
        "subject_type" => ["agent", "__unknown__"]
      },
      "normalization" =>
        Enum.into(@router_numeric_features, %{}, fn feature ->
          {feature, %{"mean" => 0.0, "scale" => 1.0}}
        end),
      "network" => %{
        "layers" => [
          %{
            "weights" => [
              router_weight_vector()
            ],
            "biases" => [0.0],
            "activation" => "identity"
          }
        ]
      },
      "thresholds" => %{"selection" => "max_score"},
      "metrics" => %{}
    }
  end

  def default_artifact_payload("budget_hint") do
    %{
      "schema_version" => 1,
      "artifact_type" => "budget_hint",
      "model_family" => "portable_linear_fallback",
      "feature_spec" => %{
        "numeric_features" => @budget_numeric_features,
        "categorical_features" => @budget_categorical_features
      },
      "categorical_vocab" => %{
        "source" => ["mcp", "proxy", "seed", "__unknown__"],
        "tool" => ["ck_budget", "__unknown__"],
        "provider" => ["anthropic", "openai", "unknown", "__unknown__"],
        "model" => ["claude-sonnet-4-5", "gpt-5.4", "unknown", "__unknown__"],
        "domain_pack" => ["software", "healthcare", "__unknown__"],
        "risk_tier" => ["moderate", "high", "critical", "__unknown__"]
      },
      "normalization" =>
        Enum.into(@budget_numeric_features, %{}, fn feature ->
          {feature, %{"mean" => 0.0, "scale" => 1.0}}
        end),
      "network" => %{
        "layers" => [
          %{
            "weights" => [
              budget_weight_vector()
            ],
            "biases" => [0.0],
            "activation" => "sigmoid"
          }
        ]
      },
      "thresholds" => %{"warn_probability" => 0.6},
      "metrics" => %{}
    }
  end

  def default_artifact_payload(_type), do: default_artifact_payload("router")

  defp router_weight_vector do
    numeric = [
      0.2,
      -0.1,
      0.05,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0
    ]

    categorical =
      zeros(3) ++
        zeros(5) ++
        zeros(3) ++
        zeros(5) ++
        [3.0, -3.0, 0.0] ++
        [0.0, 0.0]

    numeric ++ categorical
  end

  defp budget_weight_vector do
    numeric = [0.0, 0.0, 0.0, 0.02, 3.5, 3.0, 0.8]
    categorical = zeros(4) ++ zeros(2) ++ zeros(4) ++ zeros(4) ++ zeros(3) ++ zeros(4)
    numeric ++ categorical
  end

  defp zeros(count), do: List.duplicate(0.0, count)

  defp next_version_for(artifact_type) do
    ControlKeel.PolicyTraining.Artifact
    |> where([artifact], artifact.artifact_type == ^artifact_type)
    |> select([artifact], max(artifact.version))
    |> Repo.one()
    |> Kernel.||(0)
    |> Kernel.+(1)
  end
end
