import { useState, useRef, useEffect, useCallback } from "react";

const INDUSTRIES = [
  { id: "web", label: "Web App / SaaS", icon: "◈", compliance: ["GDPR", "SOC 2", "OWASP Top 10"] },
  { id: "health", label: "Healthcare", icon: "✚", compliance: ["HIPAA", "HITECH", "FDA 21 CFR Part 11"] },
  { id: "finance", label: "Finance / Fintech", icon: "◇", compliance: ["PCI-DSS", "SOX", "GLBA", "AML/KYC"] },
  { id: "ecommerce", label: "E-Commerce", icon: "▣", compliance: ["PCI-DSS", "GDPR", "CCPA", "ADA/WCAG"] },
  { id: "education", label: "Education", icon: "△", compliance: ["FERPA", "COPPA", "WCAG 2.1 AA"] },
  { id: "legal", label: "Legal", icon: "§", compliance: ["Attorney-Client Privilege", "Data Retention", "eDiscovery"] },
  { id: "iot", label: "IoT / Hardware", icon: "⬡", compliance: ["IEC 62443", "NIST", "Safety-Critical Standards"] },
  { id: "general", label: "Other / General", icon: "○", compliance: ["OWASP Top 10", "GDPR"] },
];

const AGENTS = [
  { id: "claude", label: "Claude Code", file: "CLAUDE.md" },
  { id: "cursor", label: "Cursor", file: ".cursorrules" },
  { id: "codex", label: "Codex CLI", file: "AGENTS.md" },
  { id: "copilot", label: "GitHub Copilot", file: ".github/copilot-instructions.md" },
  { id: "windsurf", label: "Windsurf", file: ".windsurfrules" },
  { id: "replit", label: "Replit", file: ".replit-agent" },
  { id: "bolt", label: "Bolt / Lovable", file: "spec.md" },
  { id: "generic", label: "Other / Generic", file: "AGENT_INSTRUCTIONS.md" },
];

const INTERVIEW_QUESTIONS = [
  {
    id: "idea",
    question: "Describe your project idea in your own words. What are you trying to build and why?",
    placeholder: "e.g., I want to build a meal planning app that suggests recipes based on dietary restrictions and what's in your fridge...",
    type: "textarea",
  },
  {
    id: "users",
    question: "Who will use this? How many users do you expect initially?",
    placeholder: "e.g., Health-conscious adults, starting with maybe 100 users, growing to thousands...",
    type: "textarea",
  },
  {
    id: "data",
    question: "What kind of data will your app handle? Any sensitive information?",
    placeholder: "e.g., User accounts, dietary preferences, maybe health conditions like allergies, payment info for premium features...",
    type: "textarea",
  },
  {
    id: "features",
    question: "List the 3-5 most important features. Don't worry about technical details.",
    placeholder: "e.g., 1) Recipe suggestions based on ingredients 2) Shopping list generator 3) Meal calendar 4) Dietary restriction filters 5) Share recipes with friends",
    type: "textarea",
  },
  {
    id: "budget",
    question: "What's your hosting/infrastructure budget? Any deployment preferences?",
    placeholder: "e.g., $0-50/month to start, I've heard of Vercel and Railway but don't know which to use...",
    type: "textarea",
  },
];

function generateSpecPrompt(answers, industry, agent) {
  const ind = INDUSTRIES.find((i) => i.id === industry);
  const ag = AGENTS.find((a) => a.id === agent);
  return `You are AgentHelm, an expert engineering team compressed into an AI. Generate a COMPLETE technical specification for this project.

PROJECT CONTEXT:
- Idea: ${answers.idea || "Not specified"}
- Users: ${answers.users || "Not specified"}
- Data: ${answers.data || "Not specified"}  
- Features: ${answers.features || "Not specified"}
- Budget: ${answers.budget || "Not specified"}
- Industry: ${ind?.label || "General"}
- Required Compliance: ${ind?.compliance?.join(", ") || "OWASP Top 10"}
- Target Agent: ${ag?.label || "Generic"}

Generate a JSON response with EXACTLY this structure (no markdown, no backticks, just raw JSON):
{
  "projectName": "suggested-project-name",
  "summary": "2-3 sentence project summary",
  "architecture": {
    "stack": ["list", "of", "technologies"],
    "pattern": "architecture pattern name",
    "description": "2-3 sentences on why this architecture"
  },
  "security": {
    "critical": ["list of critical security requirements"],
    "policies": ["list of security policies to enforce"],
    "threats": ["top 3-5 threat vectors to protect against"]
  },
  "compliance": {
    "requirements": ["specific compliance items needed"],
    "dataHandling": "how sensitive data must be handled",
    "auditNeeds": "what audit trails are needed"
  },
  "deployment": {
    "platform": "recommended hosting platform",
    "estimatedCost": "monthly cost estimate",
    "cicd": "CI/CD recommendation",
    "scaling": "scaling strategy"
  },
  "tasks": [
    {"id": 1, "title": "task title", "priority": "P0/P1/P2", "description": "what to implement"},
    {"id": 2, "title": "task title", "priority": "P0/P1/P2", "description": "what to implement"}
  ],
  "agentInstructions": "Complete agent instruction file content for ${ag?.file || "AGENT_INSTRUCTIONS.md"} that includes project context, coding standards, security requirements, file structure, and task sequence. Make this comprehensive - at least 40 lines.",
  "risks": ["top 3-5 project risks"],
  "timeline": "estimated timeline for MVP"
}

Be specific, opinionated, and thorough. This spec should be good enough that a coding agent can execute it without further clarification. Include specific library versions, specific security patterns (not just "use authentication" but "use bcrypt with 12 rounds for password hashing, JWT with RS256 for sessions, httpOnly secure cookies"), and specific deployment configurations.`;
}

function generateValidationPrompt(code) {
  return `You are AgentHelm Sentinel, a security and quality validation engine. Analyze this code/specification and return a JSON validation report.

CODE TO VALIDATE:
${code.substring(0, 3000)}

Return ONLY raw JSON (no markdown, no backticks):
{
  "score": 0-100,
  "grade": "A/B/C/D/F",
  "security": {
    "score": 0-100,
    "issues": [{"severity": "critical/high/medium/low", "description": "issue description", "fix": "how to fix"}]
  },
  "quality": {
    "score": 0-100,
    "issues": [{"severity": "high/medium/low", "description": "issue", "fix": "fix"}]
  },
  "compliance": {
    "score": 0-100,
    "gaps": ["list of compliance gaps"]
  },
  "recommendations": ["top 3 recommendations"]
}`;
}

async function callClaude(prompt, systemPrompt) {
  try {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 4000,
        system: systemPrompt || "You are AgentHelm, an autonomous pre-execution intelligence layer. Always respond with valid JSON only. No markdown formatting, no backticks, no explanatory text outside the JSON.",
        messages: [{ role: "user", content: prompt }],
      }),
    });
    const data = await response.json();
    const text = data.content?.map((i) => i.text || "").filter(Boolean).join("\n") || "";
    const clean = text.replace(/```json|```/g, "").trim();
    return JSON.parse(clean);
  } catch (err) {
    console.error("Claude API error:", err);
    return null;
  }
}

// ====== COMPONENTS ======

function Logo({ size = "md" }) {
  const s = size === "lg" ? "text-3xl" : size === "sm" ? "text-lg" : "text-xl";
  return (
    <div className={`flex items-center gap-2 ${s} font-bold tracking-tight`}>
      <span className="text-white">Agent</span>
      <span style={{ color: "#c4f042" }}>Helm</span>
    </div>
  );
}

function StepIndicator({ current, total, labels }) {
  return (
    <div className="flex items-center gap-1 mb-8">
      {Array.from({ length: total }).map((_, i) => (
        <div key={i} className="flex items-center gap-1">
          <div
            className="flex items-center justify-center rounded-full text-xs font-semibold transition-all duration-300"
            style={{
              width: 28,
              height: 28,
              background: i <= current ? "#c4f042" : "rgba(255,255,255,0.06)",
              color: i <= current ? "#0a0a0c" : "rgba(255,255,255,0.25)",
            }}
          >
            {i < current ? "✓" : i + 1}
          </div>
          {labels && (
            <span
              className="text-xs hidden sm:inline ml-1"
              style={{ color: i <= current ? "#c4f042" : "rgba(255,255,255,0.25)" }}
            >
              {labels[i]}
            </span>
          )}
          {i < total - 1 && (
            <div
              className="mx-1"
              style={{
                width: 24,
                height: 1,
                background: i < current ? "#c4f042" : "rgba(255,255,255,0.08)",
              }}
            />
          )}
        </div>
      ))}
    </div>
  );
}

function IndustrySelector({ selected, onSelect }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {INDUSTRIES.map((ind) => (
        <button
          key={ind.id}
          onClick={() => onSelect(ind.id)}
          className="p-4 rounded-xl text-left transition-all duration-200"
          style={{
            background: selected === ind.id ? "rgba(196,240,66,0.08)" : "rgba(255,255,255,0.03)",
            border: `1px solid ${selected === ind.id ? "rgba(196,240,66,0.4)" : "rgba(255,255,255,0.06)"}`,
          }}
        >
          <div className="text-2xl mb-2">{ind.icon}</div>
          <div className="text-sm font-medium text-white">{ind.label}</div>
          <div className="text-xs mt-1" style={{ color: "rgba(255,255,255,0.35)" }}>
            {ind.compliance[0]}
          </div>
        </button>
      ))}
    </div>
  );
}

function AgentSelector({ selected, onSelect }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {AGENTS.map((ag) => (
        <button
          key={ag.id}
          onClick={() => onSelect(ag.id)}
          className="p-4 rounded-xl text-left transition-all duration-200"
          style={{
            background: selected === ag.id ? "rgba(196,240,66,0.08)" : "rgba(255,255,255,0.03)",
            border: `1px solid ${selected === ag.id ? "rgba(196,240,66,0.4)" : "rgba(255,255,255,0.06)"}`,
          }}
        >
          <div className="text-sm font-medium text-white">{ag.label}</div>
          <div className="text-xs mt-1 font-mono" style={{ color: "rgba(255,255,255,0.3)" }}>
            {ag.file}
          </div>
        </button>
      ))}
    </div>
  );
}

function InterviewStep({ question, answer, onChange }) {
  return (
    <div className="mb-6">
      <label className="block text-base font-medium text-white mb-3">{question.question}</label>
      <textarea
        value={answer || ""}
        onChange={(e) => onChange(question.id, e.target.value)}
        placeholder={question.placeholder}
        rows={4}
        className="w-full rounded-xl p-4 text-sm resize-none focus:outline-none transition-all"
        style={{
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.08)",
          color: "#e8e6e1",
        }}
      />
    </div>
  );
}

function SpecDisplay({ spec, agent }) {
  const [activeTab, setActiveTab] = useState("overview");
  const ag = AGENTS.find((a) => a.id === agent);
  if (!spec) return null;

  const tabs = [
    { id: "overview", label: "Overview" },
    { id: "security", label: "Security" },
    { id: "compliance", label: "Compliance" },
    { id: "deploy", label: "Deployment" },
    { id: "tasks", label: "Tasks" },
    { id: "agent", label: ag?.file || "Agent File" },
  ];

  return (
    <div>
      <div className="flex gap-1 mb-6 overflow-x-auto pb-2" style={{ borderBottom: "1px solid rgba(255,255,255,0.06)" }}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className="px-4 py-2 text-sm font-medium whitespace-nowrap transition-all rounded-t-lg"
            style={{
              color: activeTab === tab.id ? "#c4f042" : "rgba(255,255,255,0.35)",
              background: activeTab === tab.id ? "rgba(196,240,66,0.06)" : "transparent",
              borderBottom: activeTab === tab.id ? "2px solid #c4f042" : "2px solid transparent",
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {activeTab === "overview" && (
        <div className="space-y-4">
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h3 className="text-lg font-bold text-white mb-1">{spec.projectName}</h3>
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.55)" }}>{spec.summary}</p>
          </div>
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h4 className="text-sm font-semibold mb-3" style={{ color: "#c4f042" }}>Architecture</h4>
            <p className="text-sm text-white font-medium mb-1">{spec.architecture?.pattern}</p>
            <p className="text-sm mb-3" style={{ color: "rgba(255,255,255,0.5)" }}>{spec.architecture?.description}</p>
            <div className="flex flex-wrap gap-2">
              {spec.architecture?.stack?.map((t, i) => (
                <span key={i} className="px-3 py-1 rounded-full text-xs font-medium" style={{ background: "rgba(196,240,66,0.1)", color: "#c4f042" }}>{t}</span>
              ))}
            </div>
          </div>
          {spec.risks && (
            <div className="p-5 rounded-xl" style={{ background: "rgba(255,107,107,0.04)", border: "1px solid rgba(255,107,107,0.12)" }}>
              <h4 className="text-sm font-semibold mb-2" style={{ color: "#ff6b6b" }}>Risks identified</h4>
              {spec.risks.map((r, i) => (
                <div key={i} className="text-sm py-1" style={{ color: "rgba(255,255,255,0.55)" }}>▸ {r}</div>
              ))}
            </div>
          )}
          <div className="flex gap-4">
            <div className="flex-1 p-4 rounded-xl text-center" style={{ background: "rgba(255,255,255,0.03)" }}>
              <div className="text-xs mb-1" style={{ color: "rgba(255,255,255,0.35)" }}>Timeline</div>
              <div className="text-sm font-semibold text-white">{spec.timeline || "N/A"}</div>
            </div>
            <div className="flex-1 p-4 rounded-xl text-center" style={{ background: "rgba(255,255,255,0.03)" }}>
              <div className="text-xs mb-1" style={{ color: "rgba(255,255,255,0.35)" }}>Est. cost</div>
              <div className="text-sm font-semibold text-white">{spec.deployment?.estimatedCost || "N/A"}</div>
            </div>
            <div className="flex-1 p-4 rounded-xl text-center" style={{ background: "rgba(255,255,255,0.03)" }}>
              <div className="text-xs mb-1" style={{ color: "rgba(255,255,255,0.35)" }}>Tasks</div>
              <div className="text-sm font-semibold text-white">{spec.tasks?.length || 0}</div>
            </div>
          </div>
        </div>
      )}

      {activeTab === "security" && (
        <div className="space-y-4">
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,107,107,0.04)", border: "1px solid rgba(255,107,107,0.12)" }}>
            <h4 className="text-sm font-semibold mb-3" style={{ color: "#ff6b6b" }}>Critical security requirements</h4>
            {spec.security?.critical?.map((item, i) => (
              <div key={i} className="flex items-start gap-2 py-1.5">
                <span className="text-xs mt-0.5 shrink-0" style={{ color: "#ff6b6b" }}>●</span>
                <span className="text-sm" style={{ color: "rgba(255,255,255,0.65)" }}>{item}</span>
              </div>
            ))}
          </div>
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h4 className="text-sm font-semibold mb-3" style={{ color: "#c4f042" }}>Security policies</h4>
            {spec.security?.policies?.map((p, i) => (
              <div key={i} className="flex items-start gap-2 py-1.5">
                <span className="text-xs mt-0.5 shrink-0" style={{ color: "#c4f042" }}>◈</span>
                <span className="text-sm" style={{ color: "rgba(255,255,255,0.65)" }}>{p}</span>
              </div>
            ))}
          </div>
          <div className="p-5 rounded-xl" style={{ background: "rgba(180,122,255,0.04)", border: "1px solid rgba(180,122,255,0.12)" }}>
            <h4 className="text-sm font-semibold mb-3" style={{ color: "#b47aff" }}>Threat vectors</h4>
            {spec.security?.threats?.map((t, i) => (
              <div key={i} className="flex items-start gap-2 py-1.5">
                <span className="text-xs mt-0.5 shrink-0" style={{ color: "#b47aff" }}>⚠</span>
                <span className="text-sm" style={{ color: "rgba(255,255,255,0.65)" }}>{t}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === "compliance" && (
        <div className="space-y-4">
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h4 className="text-sm font-semibold mb-3" style={{ color: "#c4f042" }}>Compliance requirements</h4>
            {spec.compliance?.requirements?.map((r, i) => (
              <div key={i} className="flex items-start gap-2 py-1.5">
                <span className="text-xs mt-0.5 shrink-0" style={{ color: "#c4f042" }}>✓</span>
                <span className="text-sm" style={{ color: "rgba(255,255,255,0.65)" }}>{r}</span>
              </div>
            ))}
          </div>
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h4 className="text-sm font-semibold mb-3 text-white">Data handling</h4>
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.55)" }}>{spec.compliance?.dataHandling}</p>
          </div>
          <div className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
            <h4 className="text-sm font-semibold mb-3 text-white">Audit requirements</h4>
            <p className="text-sm" style={{ color: "rgba(255,255,255,0.55)" }}>{spec.compliance?.auditNeeds}</p>
          </div>
        </div>
      )}

      {activeTab === "deploy" && (
        <div className="space-y-4">
          {[
            { label: "Platform", value: spec.deployment?.platform, color: "#6bb3ff" },
            { label: "Estimated monthly cost", value: spec.deployment?.estimatedCost, color: "#c4f042" },
            { label: "CI/CD", value: spec.deployment?.cicd, color: "#b47aff" },
            { label: "Scaling strategy", value: spec.deployment?.scaling, color: "#4ae8c4" },
          ].map((item, i) => (
            <div key={i} className="p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
              <div className="text-xs font-semibold mb-1" style={{ color: item.color }}>{item.label}</div>
              <div className="text-sm text-white">{item.value}</div>
            </div>
          ))}
        </div>
      )}

      {activeTab === "tasks" && (
        <div className="space-y-3">
          {spec.tasks?.map((task) => (
            <div key={task.id} className="p-4 rounded-xl flex gap-4" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
              <div className="shrink-0">
                <span
                  className="px-2 py-0.5 rounded text-xs font-bold"
                  style={{
                    background: task.priority === "P0" ? "rgba(255,107,107,0.15)" : task.priority === "P1" ? "rgba(255,140,107,0.15)" : "rgba(255,255,255,0.06)",
                    color: task.priority === "P0" ? "#ff6b6b" : task.priority === "P1" ? "#ff8c6b" : "rgba(255,255,255,0.4)",
                  }}
                >
                  {task.priority}
                </span>
              </div>
              <div>
                <div className="text-sm font-medium text-white">{task.title}</div>
                <div className="text-xs mt-1" style={{ color: "rgba(255,255,255,0.45)" }}>{task.description}</div>
              </div>
            </div>
          ))}
        </div>
      )}

      {activeTab === "agent" && (
        <div className="rounded-xl overflow-hidden" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
          <div className="flex items-center justify-between px-4 py-3" style={{ background: "rgba(255,255,255,0.03)", borderBottom: "1px solid rgba(255,255,255,0.06)" }}>
            <span className="text-xs font-mono font-medium" style={{ color: "#c4f042" }}>{ag?.file}</span>
            <button
              onClick={() => navigator.clipboard?.writeText(spec.agentInstructions || "")}
              className="text-xs px-3 py-1 rounded-lg transition-all"
              style={{ background: "rgba(196,240,66,0.1)", color: "#c4f042" }}
            >
              Copy
            </button>
          </div>
          <pre className="p-4 text-xs overflow-auto" style={{ color: "rgba(255,255,255,0.6)", maxHeight: 500, fontFamily: "'JetBrains Mono', monospace", whiteSpace: "pre-wrap", lineHeight: 1.7 }}>
            {spec.agentInstructions}
          </pre>
        </div>
      )}
    </div>
  );
}

function ValidationDisplay({ validation }) {
  if (!validation) return null;
  const gradeColor = { A: "#c4f042", B: "#4ae8c4", C: "#ffc107", D: "#ff8c6b", F: "#ff6b6b" };
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-6 p-5 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid rgba(255,255,255,0.06)" }}>
        <div className="text-center">
          <div className="text-5xl font-bold" style={{ color: gradeColor[validation.grade] || "#fff", fontFamily: "'DM Serif Display', serif" }}>{validation.grade}</div>
          <div className="text-xs mt-1" style={{ color: "rgba(255,255,255,0.35)" }}>Overall</div>
        </div>
        <div className="flex-1 grid grid-cols-3 gap-3">
          {[
            { label: "Security", score: validation.security?.score },
            { label: "Quality", score: validation.quality?.score },
            { label: "Compliance", score: validation.compliance?.score },
          ].map((m, i) => (
            <div key={i} className="text-center">
              <div className="text-lg font-bold text-white">{m.score}%</div>
              <div className="text-xs" style={{ color: "rgba(255,255,255,0.35)" }}>{m.label}</div>
              <div className="mt-2 h-1.5 rounded-full overflow-hidden" style={{ background: "rgba(255,255,255,0.06)" }}>
                <div className="h-full rounded-full transition-all" style={{ width: `${m.score}%`, background: m.score >= 80 ? "#c4f042" : m.score >= 60 ? "#ffc107" : "#ff6b6b" }} />
              </div>
            </div>
          ))}
        </div>
      </div>
      {validation.security?.issues?.length > 0 && (
        <div className="p-5 rounded-xl" style={{ background: "rgba(255,107,107,0.04)", border: "1px solid rgba(255,107,107,0.12)" }}>
          <h4 className="text-sm font-semibold mb-3" style={{ color: "#ff6b6b" }}>Security issues</h4>
          {validation.security.issues.map((issue, i) => (
            <div key={i} className="py-2" style={{ borderTop: i > 0 ? "1px solid rgba(255,255,255,0.04)" : "none" }}>
              <div className="flex items-center gap-2">
                <span className="text-xs px-2 py-0.5 rounded font-semibold" style={{ background: issue.severity === "critical" ? "rgba(255,107,107,0.2)" : "rgba(255,140,107,0.15)", color: issue.severity === "critical" ? "#ff6b6b" : "#ff8c6b" }}>{issue.severity}</span>
                <span className="text-sm text-white">{issue.description}</span>
              </div>
              <div className="text-xs mt-1 ml-12" style={{ color: "rgba(196,240,66,0.7)" }}>Fix: {issue.fix}</div>
            </div>
          ))}
        </div>
      )}
      {validation.recommendations?.length > 0 && (
        <div className="p-5 rounded-xl" style={{ background: "rgba(196,240,66,0.03)", border: "1px solid rgba(196,240,66,0.12)" }}>
          <h4 className="text-sm font-semibold mb-3" style={{ color: "#c4f042" }}>Recommendations</h4>
          {validation.recommendations.map((r, i) => (
            <div key={i} className="text-sm py-1" style={{ color: "rgba(255,255,255,0.6)" }}>▸ {r}</div>
          ))}
        </div>
      )}
    </div>
  );
}

// ====== MAIN APP ======
export default function AgentHelm() {
  const [step, setStep] = useState(0); // 0=industry, 1=agent, 2=interview, 3=generating, 4=results, 5=validating, 6=validation
  const [industry, setIndustry] = useState(null);
  const [agent, setAgent] = useState(null);
  const [answers, setAnswers] = useState({});
  const [currentQ, setCurrentQ] = useState(0);
  const [spec, setSpec] = useState(null);
  const [validation, setValidation] = useState(null);
  const [loadingMsg, setLoadingMsg] = useState("");

  const loadingMessages = [
    "Analyzing project requirements...",
    "Mapping security threat vectors...",
    "Checking compliance requirements...",
    "Designing system architecture...",
    "Estimating infrastructure costs...",
    "Generating task breakdown...",
    "Compiling agent instructions...",
    "Running pre-execution checks...",
  ];

  useEffect(() => {
    if (step === 3 || step === 5) {
      let i = 0;
      const interval = setInterval(() => {
        setLoadingMsg(loadingMessages[i % loadingMessages.length]);
        i++;
      }, 2200);
      return () => clearInterval(interval);
    }
  }, [step]);

  const handleGenerate = async () => {
    setStep(3);
    const prompt = generateSpecPrompt(answers, industry, agent);
    const result = await callClaude(prompt);
    if (result) {
      setSpec(result);
      setStep(4);
    } else {
      setSpec({
        projectName: "generation-failed",
        summary: "Spec generation encountered an error. This may be due to API limits. Try again or use the interview answers as a starting point.",
        architecture: { stack: [], pattern: "N/A", description: "Error during generation" },
        security: { critical: [], policies: [], threats: [] },
        compliance: { requirements: [], dataHandling: "N/A", auditNeeds: "N/A" },
        deployment: { platform: "N/A", estimatedCost: "N/A", cicd: "N/A", scaling: "N/A" },
        tasks: [],
        agentInstructions: "# Error: Spec generation failed\n# Please try again",
        risks: ["Generation failed - retry recommended"],
        timeline: "N/A",
      });
      setStep(4);
    }
  };

  const handleValidate = async () => {
    setStep(5);
    const prompt = generateValidationPrompt(spec?.agentInstructions || JSON.stringify(spec));
    const result = await callClaude(prompt);
    if (result) {
      setValidation(result);
    } else {
      setValidation({
        score: 0, grade: "?",
        security: { score: 0, issues: [{ severity: "high", description: "Validation failed", fix: "Retry" }] },
        quality: { score: 0, issues: [] },
        compliance: { score: 0, gaps: [] },
        recommendations: ["Retry validation"],
      });
    }
    setStep(6);
  };

  const handleAnswerChange = (id, value) => setAnswers((prev) => ({ ...prev, [id]: value }));

  const allAnswered = INTERVIEW_QUESTIONS.every((q) => answers[q.id]?.trim());

  return (
    <div style={{ minHeight: "100vh", background: "#0a0a0c", color: "#e8e6e1", fontFamily: "'Outfit', sans-serif" }}>
      <link href="https://fonts.googleapis.com/css2?family=DM+Serif+Display&family=Outfit:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />

      {/* Header */}
      <div style={{ borderBottom: "1px solid rgba(255,255,255,0.05)", padding: "1rem 0" }}>
        <div style={{ maxWidth: 900, margin: "0 auto", padding: "0 1.5rem", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <Logo />
          {step >= 4 && (
            <button
              onClick={() => { setStep(0); setIndustry(null); setAgent(null); setAnswers({}); setSpec(null); setValidation(null); setCurrentQ(0); }}
              className="text-xs px-3 py-1.5 rounded-lg"
              style={{ background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.5)" }}
            >
              Start over
            </button>
          )}
        </div>
      </div>

      {/* Main content */}
      <div style={{ maxWidth: 900, margin: "0 auto", padding: "2rem 1.5rem 4rem" }}>

        {step < 4 && (
          <StepIndicator
            current={step}
            total={4}
            labels={["Industry", "Agent", "Interview", "Generate"]}
          />
        )}

        {/* Step 0: Industry */}
        {step === 0 && (
          <div>
            <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.75rem", marginBottom: "0.5rem" }}>What are you building?</h2>
            <p style={{ color: "rgba(255,255,255,0.45)", marginBottom: "1.5rem", fontWeight: 300 }}>
              Select your industry. AgentHelm will apply the right compliance frameworks, security patterns, and best practices automatically.
            </p>
            <IndustrySelector selected={industry} onSelect={(id) => { setIndustry(id); setTimeout(() => setStep(1), 300); }} />
          </div>
        )}

        {/* Step 1: Agent */}
        {step === 1 && (
          <div>
            <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.75rem", marginBottom: "0.5rem" }}>Which coding tool will you use?</h2>
            <p style={{ color: "rgba(255,255,255,0.45)", marginBottom: "1.5rem", fontWeight: 300 }}>
              AgentHelm generates agent-specific instruction files. Pick your tool and we'll format everything for it.
            </p>
            <AgentSelector selected={agent} onSelect={(id) => { setAgent(id); setTimeout(() => setStep(2), 300); }} />
          </div>
        )}

        {/* Step 2: Interview */}
        {step === 2 && (
          <div>
            <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.75rem", marginBottom: "0.5rem" }}>Tell us about your project</h2>
            <p style={{ color: "rgba(255,255,255,0.45)", marginBottom: "1.5rem", fontWeight: 300 }}>
              Answer in plain English. No technical knowledge needed — AgentHelm will translate your intent into a complete technical specification.
            </p>
            {INTERVIEW_QUESTIONS.map((q) => (
              <InterviewStep key={q.id} question={q} answer={answers[q.id]} onChange={handleAnswerChange} />
            ))}
            <div className="flex gap-3 mt-6">
              <button
                onClick={() => setStep(1)}
                className="px-5 py-3 rounded-xl text-sm"
                style={{ background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.5)" }}
              >
                Back
              </button>
              <button
                onClick={handleGenerate}
                disabled={!allAnswered}
                className="flex-1 py-3 rounded-xl text-sm font-semibold transition-all"
                style={{
                  background: allAnswered ? "#c4f042" : "rgba(255,255,255,0.05)",
                  color: allAnswered ? "#0a0a0c" : "rgba(255,255,255,0.2)",
                  cursor: allAnswered ? "pointer" : "not-allowed",
                }}
              >
                Generate specification
              </button>
            </div>
          </div>
        )}

        {/* Step 3: Loading */}
        {step === 3 && (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="relative mb-8">
              <div style={{ width: 64, height: 64, border: "2px solid rgba(196,240,66,0.2)", borderTopColor: "#c4f042", borderRadius: "50%", animation: "spin 1s linear infinite" }} />
            </div>
            <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.5rem", marginBottom: "0.75rem" }}>
              AgentHelm is working
            </h2>
            <p style={{ color: "#c4f042", fontSize: "0.9rem", fontWeight: 300, minHeight: 24, transition: "all 0.3s" }}>
              {loadingMsg}
            </p>
            <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
          </div>
        )}

        {/* Step 4: Results */}
        {step === 4 && spec && (
          <div>
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.75rem", marginBottom: "0.25rem" }}>
                  Specification ready
                </h2>
                <p style={{ color: "rgba(255,255,255,0.45)", fontWeight: 300, fontSize: "0.9rem" }}>
                  Review your spec, then validate or export the agent instruction file.
                </p>
              </div>
              <button
                onClick={handleValidate}
                className="px-5 py-2.5 rounded-xl text-sm font-semibold transition-all shrink-0"
                style={{ background: "rgba(74,232,196,0.12)", color: "#4ae8c4", border: "1px solid rgba(74,232,196,0.25)" }}
              >
                Run validation
              </button>
            </div>
            <SpecDisplay spec={spec} agent={agent} />
          </div>
        )}

        {/* Step 5: Validating */}
        {step === 5 && (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="relative mb-8">
              <div style={{ width: 64, height: 64, border: "2px solid rgba(74,232,196,0.2)", borderTopColor: "#4ae8c4", borderRadius: "50%", animation: "spin 1s linear infinite" }} />
            </div>
            <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.5rem", marginBottom: "0.75rem" }}>Sentinel is scanning</h2>
            <p style={{ color: "#4ae8c4", fontSize: "0.9rem", fontWeight: 300 }}>{loadingMsg}</p>
          </div>
        )}

        {/* Step 6: Validation results */}
        {step === 6 && (
          <div>
            <div className="flex items-center justify-between mb-6">
              <div>
                <h2 style={{ fontFamily: "'DM Serif Display', serif", fontSize: "1.75rem", marginBottom: "0.25rem" }}>Validation report</h2>
                <p style={{ color: "rgba(255,255,255,0.45)", fontWeight: 300, fontSize: "0.9rem" }}>Sentinel has analyzed your specification for security, quality, and compliance.</p>
              </div>
              <button
                onClick={() => setStep(4)}
                className="px-5 py-2.5 rounded-xl text-sm font-semibold transition-all shrink-0"
                style={{ background: "rgba(255,255,255,0.05)", color: "rgba(255,255,255,0.5)" }}
              >
                Back to spec
              </button>
            </div>
            <ValidationDisplay validation={validation} />
          </div>
        )}
      </div>
    </div>
  );
}
