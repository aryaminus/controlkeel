defmodule ControlKeel.PolicyTraining.Trainer do
  @moduledoc false

  def train(dataset, opts \\ []) when is_map(dataset) do
    python = Keyword.get(opts, :python, python_bin())
    tmp_dir = Keyword.get(opts, :tmp_dir, tmp_dir())

    input_path =
      Path.join(tmp_dir, "controlkeel-policy-#{System.unique_integer([:positive])}.json")

    output_path = Path.rootname(input_path) <> "-artifact.json"
    trainer_path = trainer_path()

    with {:ok, _} <- ensure_python(python),
         :ok <- File.mkdir_p(tmp_dir),
         :ok <- File.write(input_path, Jason.encode!(dataset)),
         {output, 0} <-
           System.cmd(python, [trainer_path, input_path, output_path], stderr_to_stdout: true),
         {:ok, artifact_payload} <- read_artifact(output_path) do
      cleanup_temp_files([input_path, output_path])
      {:ok, artifact_payload, String.trim(output)}
    else
      {:error, _reason} = error ->
        cleanup_temp_files([input_path, output_path])
        error

      {output, status} when is_integer(status) ->
        cleanup_temp_files([input_path, output_path])
        {:error, {:trainer_failed, status, String.trim(output)}}
    end
  end

  def python_bin do
    System.get_env("CONTROLKEEL_POLICY_TRAINING_PYTHON") ||
      System.find_executable("python3") ||
      System.find_executable("python")
  end

  def tmp_dir do
    System.get_env("CONTROLKEEL_POLICY_TRAINING_TMP_DIR") ||
      Path.join(System.tmp_dir!(), "controlkeel-policy-training")
  end

  def trainer_path do
    Application.app_dir(:controlkeel, "priv/policy_training/train_policy.py")
  end

  defp ensure_python(nil), do: {:error, :python_not_found}

  defp ensure_python(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :python_not_found}
    end
  end

  defp read_artifact(path) do
    with true <- File.exists?(path) || {:error, :artifact_missing},
         {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded}
    else
      false -> {:error, :artifact_missing}
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_artifact_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_temp_files(paths) do
    Enum.each(paths, fn path ->
      if path do
        File.rm(path)
      end
    end)
  end
end
