defmodule ControlKeel.AutoFix do
  @moduledoc false

  alias ControlKeel.Mission.Finding
  alias ControlKeel.Scanner

  @supported_rule_ids ~w(
    secret.aws_access_key
    secret.hardcoded_credential
    secret.high_entropy_token
    security.sql_injection
    security.xss_unsafe_html
    gdpr.personal_data_logging
    gdpr.unencrypted_pii_field
    healthcare.phi_pattern
    security.semgrep.sql_injection
    hr.discriminatory_criteria
    legal.privileged_content_logging
    realestate.fair_housing_criteria
    finance.pci_pattern
    marketing.email_no_unsubscribe
    software.hardcoded_credential
  )

  def generate(%Scanner.Finding{} = finding) do
    generate_from(finding.rule_id, finding.metadata, finding.location["path"])
  end

  def generate(%Finding{} = finding) do
    generate_from(finding.rule_id, finding.metadata, finding.metadata["path"])
  end

  defp generate_from(rule_id, metadata, path) do
    location = path || rule_id
    match = metadata["matched_text_redacted"]

    case rule_id do
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

      "gdpr.personal_data_logging" ->
        %{
          "supported" => true,
          "fix_kind" => "pii_anonymisation",
          "summary" =>
            "Replace the logged personal data with an anonymised identifier (user ID or hash).",
          "why" =>
            "Logging personal data (email, name, phone) creates a GDPR audit liability and expands the blast radius of a log breach.",
          "steps" => [
            "Find the log statement that includes PII fields.",
            "Replace identifying fields (email, name, phone) with `user.id` or a pseudonymised token.",
            "Ensure the log still carries enough context for debugging without exposing real personal data.",
            "Update tests that assert on log output to use the anonymised form."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove personal data fields from the log statement#{match_clause(nil)}.
            Replace email, name, or phone with an anonymised identifier like `user.id`.
            Preserve enough context for debugging but ensure no personally identifiable information appears in the log line.
            """
            |> String.trim(),
          "example" => ~s[Logger.info("signup", user_id: user.id)],
          "requires_human" => false
        }

      "gdpr.unencrypted_pii_field" ->
        %{
          "supported" => true,
          "fix_kind" => "encrypted_field",
          "summary" =>
            "Encrypt PII fields at rest using Cloak or an equivalent encrypted field type.",
          "why" =>
            "Unencrypted PII fields expose personal data if the database is accessed directly or backups are stolen.",
          "steps" => [
            "Add `cloak_ecto` (or equivalent) to dependencies.",
            "Replace `:string` with `Cloak.Ecto.Binary` (or `EncryptedString`) for the PII field.",
            "Generate and store an encryption key in the application's secret key base or KMS.",
            "Run a migration to re-encrypt existing data.",
            "Confirm the column contains opaque ciphertext rather than plaintext in the database."
          ],
          "agent_prompt" =>
            """
            In #{location}, replace the plain `:string` PII field type with an encrypted field using `cloak_ecto` or an equivalent library.
            Add the dependency, configure a vault key, and update the schema. Include migration instructions to re-encrypt existing rows.
            """
            |> String.trim(),
          "example" => "field :email, Cloak.Ecto.Binary",
          "requires_human" => true
        }

      "healthcare.phi_pattern" ->
        %{
          "supported" => true,
          "fix_kind" => "phi_tokenisation",
          "summary" => "Mask or tokenise PHI before processing or logging.",
          "why" =>
            "Handling raw Protected Health Information in code violates HIPAA minimum-necessary and increases breach risk.",
          "steps" => [
            "Identify where PHI (name, SSN, DOB, diagnosis) is passed to a non-HIPAA system, logged, or serialised.",
            "Replace raw PHI with a tokenised reference or a de-identified surrogate value.",
            "Ensure any audit log records the operation type and the token, not the PHI itself.",
            "Review the data-flow diagram to confirm PHI never leaves the HIPAA-compliant boundary."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove the raw PHI value from the code path and replace it with a tokenised or de-identified reference.
            If the value must be stored, ensure it goes to an encrypted, HIPAA-compliant store. Document the data flow change.
            """
            |> String.trim(),
          "example" => "patient_ref = PHITokeniser.tokenise(patient.ssn)",
          "requires_human" => true
        }

      rule when rule in ["security.semgrep.sql_injection", "security.semgrep.sql-concat"] ->
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
            Refactor the SQL path in #{location} to use parameterized queries instead of string interpolation.
            Keep the query semantics the same, but pass user-controlled values through placeholders or the framework's query builder API.
            """
            |> String.trim(),
          "example" => "Repo.query!(\"SELECT * FROM users WHERE email = ?\", [email])",
          "requires_human" => false
        }

      "hr.discriminatory_criteria" ->
        %{
          "supported" => true,
          "fix_kind" => "criteria_removal",
          "summary" =>
            "Remove the discriminatory filter criterion and replace with objective, job-related criteria.",
          "why" =>
            "Filtering candidates by protected characteristics (age, gender, race, religion) is illegal in most jurisdictions and creates legal liability.",
          "steps" => [
            "Identify the filter or scoring rule that references a protected characteristic.",
            "Remove the criterion entirely or replace with an objective, skills-based equivalent.",
            "Document the business justification for any remaining criteria.",
            "Have legal review the updated criteria before re-deployment."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove the discriminatory filter criterion that references a protected characteristic.
            Replace it with an objective, job-related criterion or remove the filter entirely. Add a comment explaining the change.
            """
            |> String.trim(),
          "example" => "# removed: age_filter — use years_of_experience instead",
          "requires_human" => true
        }

      "legal.privileged_content_logging" ->
        %{
          "supported" => true,
          "fix_kind" => "log_removal",
          "summary" =>
            "Remove the log statement — no automated replacement is safe for privileged content.",
          "why" =>
            "Logging attorney-client privileged content or work-product may destroy privilege and create discovery liability.",
          "steps" => [
            "Delete the log statement that records privileged content.",
            "If audit logging is required, log only metadata (document ID, timestamp, actor) without the privileged payload.",
            "Have legal confirm what metadata can be safely retained."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove the log statement that captures privileged content.
            If an audit trail is required, replace it with a metadata-only log (document_id, actor, timestamp) that excludes the privileged payload.
            """
            |> String.trim(),
          "example" => "Logger.info(\"document accessed\", doc_id: doc.id, actor: user.id)",
          "requires_human" => true
        }

      "realestate.fair_housing_criteria" ->
        %{
          "supported" => true,
          "fix_kind" => "criteria_removal",
          "summary" =>
            "Remove the protected characteristic filter — Fair Housing Act prohibits filtering by race, color, religion, sex, national origin, disability, or familial status.",
          "why" =>
            "Filtering listings or applicants by protected characteristics violates the Fair Housing Act and can result in significant penalties.",
          "steps" => [
            "Identify the filter that references a protected Fair Housing characteristic.",
            "Remove the criterion from query, scoring, or recommendation logic.",
            "Replace with objective criteria (price range, square footage, amenities).",
            "Document the change and have compliance review the updated filtering logic."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove the protected characteristic filter that violates the Fair Housing Act.
            Replace with objective property criteria (price, size, location radius). Add a comment noting the compliance requirement.
            """
            |> String.trim(),
          "example" =>
            "# removed: neighborhood_demographic_filter — use zip_code radius search instead",
          "requires_human" => true
        }

      "finance.pci_pattern" ->
        %{
          "supported" => true,
          "fix_kind" => "payment_tokenisation",
          "summary" => "Use payment tokenisation — never store, log, or transmit raw card data.",
          "why" =>
            "Storing raw card numbers violates PCI DSS scope and exposes the business to massive fines and cardholder liability.",
          "steps" => [
            "Remove any code that stores, logs, or processes raw PAN (Primary Account Number).",
            "Integrate a PCI-compliant payment processor (Stripe, Braintree) that tokenises card data at collection.",
            "Only store the processor's opaque token — never the raw card number.",
            "Confirm PCI scope reduction by verifying raw card data never touches your infrastructure."
          ],
          "agent_prompt" =>
            """
            In #{location}, remove the raw card number handling and replace it with payment processor tokenisation.
            The card collection should happen on the processor's hosted fields or SDK. Store only the returned token.
            Never log, transmit, or persist raw card data.
            """
            |> String.trim(),
          "example" =>
            "card_token = Stripe.create_token(card_element)  # raw PAN never touches server",
          "requires_human" => true
        }

      "marketing.email_no_unsubscribe" ->
        %{
          "supported" => true,
          "fix_kind" => "unsubscribe_addition",
          "summary" =>
            "Add a mandatory unsubscribe link or List-Unsubscribe header to the email.",
          "why" =>
            "CAN-SPAM, CASL, and GDPR all require commercial emails to carry a clear unsubscribe mechanism. Omission is a compliance violation.",
          "steps" => [
            "Add a one-click `List-Unsubscribe` header to the email.",
            "Include a visible unsubscribe link in the email body pointing to your preference centre.",
            "Ensure unsubscribe requests are processed within the legally required window (10 business days under CAN-SPAM).",
            "Test that the unsubscribe link works and sets the correct opt-out flag."
          ],
          "agent_prompt" =>
            """
            In #{location}, add a `List-Unsubscribe` email header and an unsubscribe link in the body.
            The link should point to a preference-centre endpoint that records the opt-out. Ensure processing within 10 business days.
            """
            |> String.trim(),
          "example" =>
            ~S(headers: %{"List-Unsubscribe" => "<https://example.com/unsubscribe?token=#{token}>"}),
          "requires_human" => false
        }

      "software.hardcoded_credential" ->
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
          "example" => "password = System.fetch_env!(\"DB_PASSWORD\")",
          "requires_human" => true
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

  def supported?(%Scanner.Finding{} = f), do: f.rule_id in @supported_rule_ids
  def supported?(%Finding{} = f), do: f.rule_id in @supported_rule_ids
  def supported_rule_ids, do: @supported_rule_ids

  defp match_clause(nil), do: ""
  defp match_clause(match), do: " (matched snippet #{match})"
end
