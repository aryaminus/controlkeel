defmodule ControlKeel.Governance.PreCommitHook do
  @moduledoc false

  alias ControlKeel.Scanner

  def install(project_root, opts \\ []) do
    hook_type = Keyword.get(opts, :type, :git_pre_commit)
    enforce = Keyword.get(opts, :enforce, false)

    case hook_type do
      :git_pre_commit ->
        install_git_hook(project_root, enforce)

      :mix_task ->
        {:ok, :mix_task_available}

      :github_action ->
        {:ok, :github_action_available}
    end
  end

  def check(project_root, opts \\ []) do
    domain_pack = Keyword.get(opts, :domain_pack)
    enforce = Keyword.get(opts, :enforce, false)

    staged_files = get_staged_files(project_root)

    if staged_files == [] do
      {:ok, %{decision: "allow", summary: "No staged files to check.", findings: []}}
    else
      findings =
        staged_files
        |> Enum.flat_map(fn file_path ->
          absolute_path = Path.join(project_root, file_path)

          case File.read(absolute_path) do
            {:ok, content} ->
              scan_file(file_path, content, domain_pack)

            {:error, _} ->
              []
          end
        end)

      decision =
        if enforce and Enum.any?(findings, fn f -> f.decision == "block" end) do
          "block"
        else
          if length(findings) > 0, do: "warn", else: "allow"
        end

      {:ok,
       %{
         decision: decision,
         summary: "#{length(findings)} finding(s) in #{length(staged_files)} staged file(s)",
         findings: findings,
         staged_files: staged_files,
         enforce: enforce
       }}
    end
  end

  def uninstall(project_root) do
    hook_path = Path.join([project_root, ".git", "hooks", "pre-commit"])

    case File.read(hook_path) do
      {:ok, content} ->
        if String.contains?(content, "controlkeel") do
          File.rm(hook_path)
          {:ok, :uninstalled}
        else
          {:ok, :not_controlkeel_hook}
        end

      {:error, _} ->
        {:ok, :no_hook_found}
    end
  end

  defp install_git_hook(project_root, enforce) do
    hooks_dir = Path.join([project_root, ".git", "hooks"])

    unless File.dir?(hooks_dir) do
      File.mkdir_p!(hooks_dir)
    end

    hook_path = Path.join(hooks_dir, "pre-commit")
    enforce_flag = if enforce, do: "--enforce", else: ""

    hook_content = """
    #!/bin/sh
    # ControlKeel pre-commit hook
    # Scans staged files for policy violations before allowing the commit
    controlkeel precommit-check #{enforce_flag}
    exit $?
    """

    case File.read(hook_path) do
      {:ok, existing} when byte_size(existing) > 0 ->
        if String.contains?(existing, "controlkeel") do
          File.write!(hook_path, hook_content)
          {:ok, :updated}
        else
          {:error, :hook_exists}
        end

      _ ->
        File.write!(hook_path, hook_content)
        :ok = File.chmod(hook_path, 0o755)
        {:ok, :installed}
    end
  end

  defp get_staged_files(project_root) do
    case System.cmd("git", ["diff", "--cached", "--name-only", "--diff-filter=ACMR"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, ".git"))

      _ ->
        []
    end
  end

  defp scan_file(file_path, content, domain_pack) do
    input = %{
      content: content,
      path: file_path,
      session_id: nil,
      project_root: nil,
      domain_pack: domain_pack
    }

    packs =
      if domain_pack do
        ["baseline", domain_pack]
      else
        ["baseline"]
      end

    case Scanner.FastPath.scan(input, packs: packs) do
      %{findings: findings} -> findings
    end
  rescue
    _ -> []
  end
end
