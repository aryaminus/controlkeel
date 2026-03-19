#!/usr/bin/env python3

import json
import math
import statistics
import sys
from pathlib import Path


def load_payload(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_payload(path, payload):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


def build_vocab(rows, categorical_features):
    vocab = {}
    for feature in categorical_features:
        values = []
        for row in rows:
            value = row["features"].get(feature, "__unknown__")
            values.append(str(value) if value is not None else "__unknown__")

        unique = sorted(set(values))
        if "__unknown__" not in unique:
            unique.append("__unknown__")
        vocab[feature] = unique
    return vocab


def build_normalization(rows, numeric_features):
    normalization = {}
    for feature in numeric_features:
        values = [float(row["features"].get(feature, 0.0) or 0.0) for row in rows]
        mean = sum(values) / len(values) if values else 0.0
        variance = sum((value - mean) ** 2 for value in values) / len(values) if values else 0.0
        scale = math.sqrt(variance) or 1.0
        normalization[feature] = {"mean": mean, "scale": scale}
    return normalization


def vectorize_row(row, feature_spec, categorical_vocab, normalization):
    output = []

    for feature in feature_spec["numeric_features"]:
        stats = normalization.get(feature, {"mean": 0.0, "scale": 1.0})
        raw = row["features"].get(feature, 0.0)
        value = float(raw or 0.0)
        output.append((value - stats["mean"]) / max(stats["scale"], 1.0e-6))

    for feature in feature_spec["categorical_features"]:
        value = row["features"].get(feature, "__unknown__")
        value = str(value) if value is not None else "__unknown__"
        vocab = categorical_vocab.get(feature, [])
        if value not in vocab:
            value = "__unknown__" if "__unknown__" in vocab else value
        output.extend(1.0 if candidate == value else 0.0 for candidate in vocab)

    return output


def sigmoid(value):
    return 1.0 / (1.0 + math.exp(-value))


def dot(left, right):
    return sum(a * b for a, b in zip(left, right))


def transpose(matrix):
    return [list(row) for row in zip(*matrix)]


def split_rows(rows):
    splits = {"train": [], "validation": [], "held_out": []}
    for row in rows:
        splits.setdefault(row.get("split", "train"), []).append(row)
    return splits


def linear_fallback(artifact_type, rows, feature_spec, categorical_vocab, normalization):
    vectors = [vectorize_row(row, feature_spec, categorical_vocab, normalization) for row in rows]
    targets = [float(row.get("target", 0.0)) for row in rows]
    dimensions = len(vectors[0]) if vectors else 0

    means = [sum(vector[index] for vector in vectors) / len(vectors) for index in range(dimensions)] if vectors else []
    mean_target = sum(targets) / len(targets) if targets else 0.0

    weights = []
    for index in range(dimensions):
        series = [vector[index] for vector in vectors]
        mean_series = means[index] if means else 0.0
        covariance = sum((value - mean_series) * (target - mean_target) for value, target in zip(series, targets))
        variance = sum((value - mean_series) ** 2 for value in series) or 1.0
        weights.append(covariance / variance)

    bias = mean_target - dot(weights, means) if means else mean_target

    activation = "sigmoid" if artifact_type == "budget_hint" else "identity"
    network = {"layers": [{"weights": [weights], "biases": [bias], "activation": activation}]}

    predictions = [forward(network, vector)[0] for vector in vectors]
    return network, fallback_metrics(artifact_type, targets, predictions), "portable_linear_fallback"


def forward(network, vector):
    activations = vector
    for layer in network["layers"]:
        next_activations = []
        for weights, bias in zip(layer["weights"], layer["biases"]):
            value = dot(activations, weights) + bias
            activation = layer.get("activation", "identity")
            if activation == "relu":
                value = max(value, 0.0)
            elif activation == "sigmoid":
                value = sigmoid(value)
            elif activation == "tanh":
                value = math.tanh(value)
            next_activations.append(value)
        activations = next_activations
    return activations


def fallback_metrics(artifact_type, targets, predictions):
    if not targets:
        return {"count": 0}

    if artifact_type == "budget_hint":
        warnings = [1.0 if prediction >= 0.6 else 0.0 for prediction in predictions]
        correct = sum(1 for predicted, target in zip(warnings, targets) if predicted == target)
        return {"count": len(targets), "accuracy": correct / len(targets)}

    absolute_error = [abs(prediction - target) for prediction, target in zip(predictions, targets)]
    return {"count": len(targets), "mae": sum(absolute_error) / len(absolute_error)}


def sklearn_train(artifact_type, rows, feature_spec, categorical_vocab, normalization):
    try:
        from sklearn.neural_network import MLPClassifier, MLPRegressor
    except Exception:
        return None

    if not rows:
        return None

    vectors = [vectorize_row(row, feature_spec, categorical_vocab, normalization) for row in rows]
    targets = [float(row.get("target", 0.0)) for row in rows]
    splits = split_rows(rows)

    train_rows = splits["train"] or rows
    train_vectors = [vectorize_row(row, feature_spec, categorical_vocab, normalization) for row in train_rows]
    train_targets = [float(row.get("target", 0.0)) for row in train_rows]

    if artifact_type == "budget_hint":
      model = MLPClassifier(hidden_layer_sizes=(8,), activation="relu", random_state=7, max_iter=400)
      model.fit(train_vectors, [1 if value >= 0.5 else 0 for value in train_targets])

      def predict(values):
          if not values:
              return []
          probabilities = model.predict_proba(values)
          return [float(row[-1]) for row in probabilities]

      model_family = "sklearn_mlp_classifier"
      output_activation = getattr(model, "out_activation_", "sigmoid")
    else:
      model = MLPRegressor(hidden_layer_sizes=(8,), activation="relu", random_state=7, max_iter=400)
      model.fit(train_vectors, train_targets)

      def predict(values):
          if not values:
              return []
          return [float(value) for value in model.predict(values)]

      model_family = "sklearn_mlp_regressor"
      output_activation = "identity"

    layers = []
    for index, (weights, biases) in enumerate(zip(model.coefs_, model.intercepts_)):
        activation = "relu"
        if index == len(model.coefs_) - 1:
            activation = "sigmoid" if output_activation in {"logistic", "softmax"} else "identity"

        layers.append(
            {
                "weights": transpose(weights.tolist()),
                "biases": [float(value) for value in biases.tolist()],
                "activation": activation,
            }
        )

    metrics = {}
    for split, split_rows_list in splits.items():
        split_vectors = [vectorize_row(row, feature_spec, categorical_vocab, normalization) for row in split_rows_list]
        split_targets = [float(row.get("target", 0.0)) for row in split_rows_list]
        split_predictions = predict(split_vectors)
        metrics[split] = fallback_metrics(artifact_type, split_targets, split_predictions)

    return {"layers": layers}, metrics, model_family


def build_artifact(payload):
    artifact_type = payload["artifact_type"]
    feature_spec = payload["feature_spec"]
    rows = payload["rows"]
    categorical_vocab = build_vocab(rows, feature_spec["categorical_features"])
    normalization = build_normalization(rows, feature_spec["numeric_features"])

    trained = sklearn_train(artifact_type, rows, feature_spec, categorical_vocab, normalization)

    if trained is None:
        network, metrics, model_family = linear_fallback(
            artifact_type, rows, feature_spec, categorical_vocab, normalization
        )
    else:
        network, metrics, model_family = trained

    thresholds = {"warn_probability": 0.6} if artifact_type == "budget_hint" else {"selection": "max_score"}

    return {
        "schema_version": 1,
        "artifact_type": artifact_type,
        "model_family": model_family,
        "feature_spec": feature_spec,
        "categorical_vocab": categorical_vocab,
        "normalization": normalization,
        "network": network,
        "thresholds": thresholds,
        "metrics": metrics,
    }


def main():
    if len(sys.argv) != 3:
        print("usage: train_policy.py <input.json> <output.json>", file=sys.stderr)
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    payload = load_payload(input_path)
    artifact = build_artifact(payload)
    save_payload(output_path, artifact)
    print(json.dumps({"ok": True, "model_family": artifact["model_family"]}))


if __name__ == "__main__":
    main()
