defmodule ControlKeel.Findings.PlainEnglish do
  @moduledoc false

  @translations %{
    "security.sql_injection" => %{
      title: "Database attack vulnerability",
      explanation:
        "Your code builds a database query by directly inserting user input. An attacker could type special characters to trick your database into running harmful commands — like deleting data, stealing passwords, or accessing private information.",
      fix:
        "Use parameterized queries (also called prepared statements) instead of string concatenation.",
      risk_if_ignored: "Attackers could steal, modify, or delete all data in your database."
    },
    "security.xss_unsafe_html" => %{
      title: "Unsafe content display",
      explanation:
        "Your code shows user-provided text directly on a web page without cleaning it first. Someone could inject harmful scripts that run when other users view the page.",
      fix:
        "Always escape or sanitize user input before displaying it. Use your framework's built-in escaping.",
      risk_if_ignored:
        "Attackers could steal login sessions, redirect users to fake sites, or deface your application."
    },
    "security.hardcoded_secret" => %{
      title: "Password or key left in code",
      explanation:
        "Your code contains a password, API key, or secret token written directly in the source code. Anyone who can see the code can see and misuse this secret.",
      fix:
        "Move all secrets to environment variables (.env files for local development, your hosting platform's secret manager for production).",
      risk_if_ignored:
        "Anyone with access to your code repository can steal your credentials and access your systems."
    },
    "security.insecure_dependency" => %{
      title: "Outdated or vulnerable package",
      explanation:
        "Your project uses a library or package that has a known security flaw. The package maintainers have released a fix, but your project is still using the old version.",
      fix: "Update the package to the latest version using your package manager.",
      risk_if_ignored:
        "Attackers can exploit the known vulnerability to compromise your application."
    },
    "security.csrf_token_missing" => %{
      title: "Missing form protection",
      explanation:
        "A form in your application doesn't have CSRF protection. Without it, a malicious website could trick your users into submitting forms they didn't intend to.",
      fix: "Add CSRF token protection to all forms using your framework's built-in form helpers.",
      risk_if_ignored: "Attackers could trick logged-in users into performing unwanted actions."
    },
    "security.insecure_deserialization" => %{
      title: "Unsafe data parsing",
      explanation:
        "Your code reads external data in a way that could allow an attacker to run arbitrary code.",
      fix: "Use safe data formats like JSON. Always validate external data before using it.",
      risk_if_ignored: "Attackers could take full control of your server."
    },
    "security.path_traversal" => %{
      title: "File access vulnerability",
      explanation:
        "Your code uses user input to build file paths without checking it first. An attacker could use special characters to access files they shouldn't see.",
      fix:
        "Validate and sanitize all file path inputs. Never trust user input when constructing file paths.",
      risk_if_ignored:
        "Attackers could read sensitive files like passwords, configs, or user data."
    },
    "security.open_redirect" => %{
      title: "Unsafe redirect",
      explanation:
        "Your application redirects users to a URL from user input without checking where it leads. Attackers can use this to send users to malicious websites.",
      fix:
        "Whitelist allowed redirect destinations. Never redirect to URLs from untrusted input.",
      risk_if_ignored:
        "Attackers could trick users into visiting phishing sites that look like yours."
    },
    "security.semgrep.ssrf_metadata_endpoint" => %{
      title: "Cloud metadata endpoint access",
      explanation:
        "Your code references a cloud instance metadata endpoint (such as 169.254.169.254). These endpoints are common SSRF targets used to steal credentials.",
      fix:
        "Block access to link-local and metadata hosts by default. Only allow explicitly approved outbound hosts.",
      risk_if_ignored:
        "Attackers may retrieve cloud credentials and use them to access internal systems or data."
    },
    "security.semgrep.ssrf_user_controlled_url" => %{
      title: "User-controlled outbound request",
      explanation:
        "An outbound HTTP call appears to use URL input that may come from users. This can enable SSRF to internal services or sensitive endpoints.",
      fix:
        "Validate URLs with strict parsing and enforce a host allowlist. Deny private, loopback, and link-local address ranges.",
      risk_if_ignored:
        "Attackers can force your server to call internal services and exfiltrate sensitive data."
    },
    "security.semgrep.axios_absolute_url_override" => %{
      title: "Axios baseURL bypass risk",
      explanation:
        "Your Axios usage appears to combine a trusted baseURL with user-controlled URL input. Absolute URLs can bypass baseURL expectations and forward sensitive headers.",
      fix:
        "Accept only relative paths for trusted clients, reject absolute URLs from untrusted input, and apply host allowlists before sending requests.",
      risk_if_ignored:
        "Credentials or API keys may be sent to attacker-controlled hosts, enabling account or data compromise."
    },
    "security.semgrep.tls_verification_disabled" => %{
      title: "TLS verification disabled",
      explanation:
        "Your code appears to disable TLS certificate verification. This removes protection against man-in-the-middle interception.",
      fix:
        "Re-enable certificate verification in all environments. If needed for development, isolate and guard that configuration from production paths.",
      risk_if_ignored:
        "Attackers on the network path can intercept or alter traffic, including credentials and sensitive data."
    },
    "security.semgrep.prompt_injection_indicator" => %{
      title: "Prompt injection marker detected",
      explanation:
        "Text includes known prompt override markers (for example, instructions to ignore prior rules). This is a common LLM prompt injection pattern.",
      fix:
        "Treat prompt content as untrusted input, isolate system instructions from user content, and require policy/human approval for high-risk actions.",
      risk_if_ignored:
        "Model behavior may be hijacked to leak sensitive data, bypass safeguards, or trigger unsafe actions."
    },
    "security.semgrep.known_compromised_dependency" => %{
      title: "Known compromised dependency version",
      explanation:
        "Your dependency manifest or lockfile includes a version associated with an active malware or supply-chain incident.",
      fix:
        "Remove the compromised version immediately, pin to a known safe release, regenerate lockfiles from trusted sources, and verify integrity/provenance.",
      risk_if_ignored:
        "Malicious install hooks or payloads may execute during dependency installation and compromise build agents or developer machines."
    },
    "security.semgrep.suspicious_lifecycle_script" => %{
      title: "Suspicious package lifecycle script",
      explanation:
        "A package lifecycle script (such as postinstall) runs network/download or shell tooling. This is a frequent malware delivery mechanism in supply-chain attacks.",
      fix:
        "Review the script manually, remove unnecessary lifecycle hooks, and enforce least-privilege CI with script execution restrictions.",
      risk_if_ignored:
        "Installing dependencies could execute attacker-controlled code and lead to credential theft or remote access."
    },
    "security.semgrep.untrusted_dependency_source" => %{
      title: "Untrusted dependency source",
      explanation:
        "A dependency is pulled from a direct URL, git source, or local file/link path instead of the normal registry flow. This increases provenance risk.",
      fix:
        "Prefer registry-published packages with verified provenance, pin exact versions, and use lockfile integrity checks in CI.",
      risk_if_ignored:
        "Unverified sources can introduce tampered code that bypasses normal package trust controls."
    },
    "security.semgrep.leak_derived_dependency_source" => %{
      title: "Leak-derived dependency source",
      explanation:
        "A dependency appears to reference a known leak-derived mirror or port of Claude Code. Leak-derived repos can carry unclear provenance and legal/security uncertainty.",
      fix:
        "Replace the source with an official upstream release or a verified clean-room package, then regenerate lockfiles and enforce provenance checks in CI.",
      risk_if_ignored:
        "Your build could ingest untrusted code, increasing malware, tampering, and compliance exposure in the supply chain."
    },
    "security.weak_password_hash" => %{
      title: "Weak password storage",
      explanation:
        "Passwords are being stored using an outdated or weak hashing method. This makes it easy for attackers to recover the original passwords if they get access to your database.",
      fix:
        "Use bcrypt, scrypt, or Argon2 for password hashing. These are designed to be slow and resist cracking.",
      risk_if_ignored:
        "If your database is leaked, all user passwords could be easily cracked and used."
    },
    "security.mass_assignment" => %{
      title: "Unsafe data update",
      explanation:
        "Your code lets users update more fields than they should be able to. An attacker could change sensitive fields like their role, balance, or admin status.",
      fix:
        "Only allow specific permitted fields to be updated. Never pass raw user input directly to your database update.",
      risk_if_ignored:
        "Users could escalate their permissions, change other users' data, or access features they shouldn't."
    },
    "cost.budget_warning" => %{
      title: "Spending approaching limit",
      explanation:
        "Your AI service spending is getting close to your budget limit. You've used about 80% of what you set aside.",
      fix:
        "Consider switching to a less expensive AI model for simple tasks, or increase your budget if needed.",
      risk_if_ignored:
        "You may run out of budget and your AI tools could stop working mid-project."
    },
    "cost.budget_guard" => %{
      title: "Budget limit reached",
      explanation:
        "Your AI service spending has reached your budget limit. New AI requests are being blocked to prevent unexpected charges.",
      fix:
        "Increase your budget, switch to free/local AI models, or review your spending to find savings.",
      risk_if_ignored: "Your AI-powered features will stop working until the budget is increased."
    },
    "privacy.pii_detected" => %{
      title: "Personal information exposed",
      explanation:
        "Your code appears to be collecting or storing personal information (like names, emails, or phone numbers) in a way that may not be properly protected.",
      fix:
        "Encrypt sensitive data, minimize what you collect, and ensure you have user consent. Follow privacy regulations like GDPR.",
      risk_if_ignored:
        "You could face legal penalties and lose user trust if personal data is exposed."
    },
    "compliance.missing_consent" => %{
      title: "Missing user consent",
      explanation:
        "Your application collects user data but may not have proper consent mechanisms in place.",
      fix:
        "Add clear consent forms and cookie notices. Let users opt in (not just opt out) to data collection.",
      risk_if_ignored:
        "You could violate GDPR, CCPA, or other privacy laws, resulting in significant fines."
    }
  }

  @category_explanations %{
    "security" =>
      "This is a security issue — it could allow attackers to harm your application or steal data.",
    "privacy" => "This is a privacy issue — it could expose users' personal information.",
    "compliance" =>
      "This is a compliance issue — it could violate laws or regulations your business must follow.",
    "cost" => "This is a cost issue — it relates to how much you're spending on AI services.",
    "delivery" =>
      "This is a delivery issue — it affects the reliability and quality of your software.",
    "hygiene" => "This is a code quality issue — it makes your code harder to maintain.",
    "fraud" => "This is a fraud risk — it could allow someone to cheat your system.",
    "safety" => "This is a safety issue — it could cause your application to fail unexpectedly.",
    "quality" => "This is a quality issue — it affects how well your application works.",
    "logic" => "This is a logic issue — the code may not behave as intended.",
    "dependencies" =>
      "This is a dependency issue — a third-party package your project uses has a problem."
  }

  @severity_explanations %{
    "critical" => "This is urgent — fix it immediately before deploying.",
    "high" => "This is important — fix it before your next release.",
    "medium" => "This should be fixed soon — plan to address it in the near future.",
    "low" => "This is a minor issue — fix it when convenient."
  }

  def translate(finding) when is_map(finding) do
    rule_id = find_field(finding, "rule_id", :rule_id, "unknown")
    category = find_field(finding, "category", :category, "unknown")
    severity = find_field(finding, "severity", :severity, "unknown")
    original_message = find_field(finding, "plain_message", :plain_message, "")

    translation = Map.get(@translations, rule_id)

    base = %{
      rule_id: rule_id,
      category: category,
      severity: severity,
      category_explanation:
        Map.get(@category_explanations, category, "This is a #{category} issue."),
      severity_explanation: Map.get(@severity_explanations, severity, "This should be reviewed."),
      original_message: original_message
    }

    case translation do
      nil ->
        Map.merge(base, %{
          title: humanize_rule(rule_id),
          explanation:
            if(original_message != "",
              do: original_message,
              else: "A #{category} issue was detected in your code."
            ),
          fix: nil,
          risk_if_ignored: nil
        })

      t ->
        Map.merge(base, t)
    end
  end

  def translate_list(findings) when is_list(findings) do
    Enum.map(findings, &translate/1)
  end

  defp find_field(map, string_key, atom_key, default) do
    Map.get(map, string_key) || Map.get(map, atom_key, default)
  end

  defp humanize_rule(rule_id) do
    rule_id
    |> String.split(".")
    |> List.last()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
