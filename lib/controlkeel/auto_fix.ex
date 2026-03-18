defmodule ControlKeel.AutoFix do
  @moduledoc false

  alias ControlKeel.Mission.Finding

  @supported_rule_ids ~w(
    secret.aws_access_key
    secret.hardcoded_credential
    secret.high_entropy_token
    security.sql_injection
    security.xss_unsafe_html
  )

  def generate(%Finding{} = finding) do
    location = location_hint(finding)
    match = finding.metadata["matched_text_redacted"]

    case finding.rule_id do
      "secret.aws_access_key" ->
        %{
          "supported" => true,
          "fix_kind" => "secret_env_migration",
          "summary" => "Move the AWS key out of source and rotate the leaked credential.",
          "why" =>
            "A committed AWS access key can be harvested quickly and used outside your control until it is rotated.",
          "steps" => [
            "Revoke or rotate the exposed AWS key in IAM before doing anything else.",
            "Replace the hardcoded value with an environment variable such as `AWS_ACCESS_KEY_ID`.",
            "Load the secret from runtime config or a secrets manager instead of source code.",
            "Re-run validation to confirm the key no longer appears in the diff or file."
          ],
          "agent_prompt" =>
            """
            Update #{location} to remove the hardcoded AWS access key#{match_clause(match)}.
            Replace it with a runtime secret reference such as `System.fetch_env!(\"AWS_ACCESS_KEY_ID\")` or the stack-equivalent secret loader.
            Do not leave any fallback literal in source. After the code change, list which environment variables must be configured and note that the leaked key must be rotated.
            """
            |> String.trim(),
          "example" => "aws_access_key_id = System.fetch_env!(\"AWS_ACCESS_KEY_ID\")",
          "requires_human" => true
        }

      "secret.hardcoded_credential" ->
        %{
          "supported" => true,
          "fix_kind" => "secret_env_migration",
          "summary" =>
            "Replace the hardcoded credential with a runtime secret reference and rotate the exposed value if it was real.",
          "why" =>
            "Hardcoded credentials spread through history, logs, and diffs and are difficult to revoke once copied.",
          "steps" => [
            "Identify whether the exposed credential was a real secret and rotate it if necessary.",
            "Replace the literal with an environment variable or secrets-manager lookup.",
            "Keep secret names explicit so deployment and local setup stay understandable.",
            "Re-run validation to confirm the literal is gone."
          ],
          "agent_prompt" =>
            """
            Remove the hardcoded credential in #{location}#{match_clause(match)}.
            Replace it with a runtime secret lookup such as `System.fetch_env!(\"APP_SECRET\")` or the framework-equivalent secret loader.
            Preserve behavior, but do not keep any literal default credential in the code.
            """
            |> String.trim(),
          "example" => "api_key = System.fetch_env!(\"THIRD_PARTY_API_KEY\")",
          "requires_human" => true
        }

      "secret.high_entropy_token" ->
        %{
          "supported" => true,
          "fix_kind" => "secret_rotation",
          "summary" =>
            "Treat the token as compromised, rotate it if it was real, and replace it with a secret-store reference.",
          "why" =>
            "High-entropy tokens are often production secrets, and exposure means you cannot trust continued confidentiality.",
          "steps" => [
            "Verify whether the token was real or a test fixture.",
            "Rotate or revoke the token if it was real.",
            "Replace it with an environment variable or secret-manager reference.",
            "Avoid logging or echoing the token in tests, scripts, or examples."
          ],
          "agent_prompt" =>
            """
            Remove the secret-like token in #{location}#{match_clause(match)} and replace it with a runtime secret reference.
            If this is example code, swap in a clearly fake placeholder that cannot be used in production.
            Return the required environment variable name and any follow-up rotation step the operator must perform.
            """
            |> String.trim(),
          "example" => "token = System.fetch_env!(\"SERVICE_TOKEN\")",
          "requires_human" => true
        }

      "security.sql_injection" ->
        %{
          "supported" => true,
          "fix_kind" => "query_parameterization",
          "summary" =>
            "Switch the query path to parameterized statements and keep all user input out of raw SQL string building.",
          "why" =>
            "Concatenating user input into SQL allows attackers to alter the query, dump data, or destroy tables.",
          "steps" => [
            "Find the query string that mixes SQL with user-controlled values.",
            "Move the user value into parameters or the ORM/query builder API.",
            "Keep the SQL template static and pass user input separately.",
            "Add a regression test that proves malicious input is treated as data, not SQL."
          ],
          "agent_prompt" =>
            """
            Refactor the SQL path in #{location} to use parameterized queries instead of string interpolation#{match_clause(match)}.
            Keep the query semantics the same, but pass user-controlled values through placeholders or the framework's query builder API.
            Add or update a test that covers a malicious input like `' OR 1=1 --` and verifies it does not change the query behavior.
            """
            |> String.trim(),
          "example" => "Repo.query!(\"SELECT * FROM users WHERE email = ?\", [email])",
          "requires_human" => false
        }

      "security.xss_unsafe_html" ->
        %{
          "supported" => true,
          "fix_kind" => "safe_rendering",
          "summary" =>
            "Replace raw HTML injection with escaped rendering or a safe text API such as `textContent`.",
          "why" =>
            "Writing untrusted HTML into the DOM can execute attacker-controlled scripts in the user’s browser.",
          "steps" => [
            "Identify where untrusted content is written into the DOM or template as raw HTML.",
            "Switch to escaped rendering or `textContent`/safe template bindings.",
            "Only keep raw HTML rendering if the content is sanitized by a trusted allowlist sanitizer.",
            "Add a regression test or fixture that proves script tags are rendered inert."
          ],
          "agent_prompt" =>
            """
            Replace the unsafe HTML rendering path in #{location}#{match_clause(match)} with escaped output or a safe DOM API like `textContent`.
            Preserve the visible output for normal text, but ensure untrusted content cannot execute scripts.
            If rich HTML is truly required, use an explicit sanitizer and document that decision in the change summary.
            """
            |> String.trim(),
          "example" => "element.textContent = userSuppliedText",
          "requires_human" => false
        }

      _unsupported ->
        %{
          "supported" => false,
          "fix_kind" => nil,
          "summary" =>
            "ControlKeel does not have a guided fix for this finding yet. Review it manually before approval or rejection.",
          "why" =>
            "This finding falls outside the current MVP auto-fix set, so the system can only preserve context and route it for review.",
          "steps" => [
            "Open the owning mission and inspect the finding context.",
            "Decide whether the issue should be approved, rejected, or escalated for manual remediation."
          ],
          "agent_prompt" => nil,
          "example" => nil,
          "requires_human" => true
        }
    end
  end

  def supported?(%Finding{} = finding), do: finding.rule_id in @supported_rule_ids
  def supported_rule_ids, do: @supported_rule_ids

  defp location_hint(%Finding{} = finding) do
    finding.metadata["path"] || finding.rule_id
  end

  defp match_clause(nil), do: ""
  defp match_clause(match), do: " (matched snippet #{match})"
end
