# Security Pipeline Documentation

This document describes the complete CI/CD security pipeline used in this repository.

---

## Architecture Overview

The pipeline operates on **two layers** and **four workflows**, providing defence in depth:

```
Developer's Machine                GitHub
─────────────────────              ─────────────────────────────────────────────
                                   Every push (all branches)
git commit                    ──►  01-secret-scan.yml     🔐 Gitleaks
   │                               02-sast-sca.yml        🛡️  Semgrep + Trivy
   ▼                               │
[pre-commit hooks]                 │  Pushes to develop / master only
   • Gitleaks                 ──►  03-codeql.yml          🧬 CodeQL (C++/Py/Go)
   • detect-secrets                │
   • Bandit (Python)               │  Weekly schedule + manual trigger
   • Ruff (Python)            ──►  04-history-scan.yml    🕵️  TruffleHog
   • go vet (Go)                   │
   • clang-format (C++)            ▼
   │                         GitHub Security Tab (SARIF)
   ▼                         GitHub Issues (auto-created on findings)
[blocked or committed]        Dependabot PRs (weekly dep updates)
```

---

## Workflow Details

### `01-secret-scan.yml` — Secret Detection

**Trigger:** Every push to every branch, every PR
**Tool:** [Gitleaks](https://github.com/gitleaks/gitleaks)
**Blocking:** YES — any detected secret immediately fails the pipeline on any branch

Gitleaks scans every commit in the push against 150+ built-in patterns covering
AWS keys, GitHub tokens, private keys, database URLs, Stripe/Twilio/Slack tokens,
and more. It also uses the custom rules defined in `.gitleaks.toml`.

**On detection:**
- Job fails → pipeline shows red → commit is blocked
- A GitHub Issue is automatically opened with step-by-step remediation instructions
- Results appear in the Security tab as SARIF alerts

---

### `02-sast-sca.yml` — Static Analysis + Dependency Scanning

**Trigger:** Every push to `feature/**`, `develop`, `master` + weekly schedule
**Tools:** [Semgrep](https://semgrep.dev) (SAST) + [Trivy](https://trivy.dev) (SCA)

#### Semgrep (SAST — Static Application Security Testing)

Semgrep performs pattern-based code analysis. Unlike a compiler, it understands
code structure (AST) rather than just text, so it can find issues like:

- Python: SQL injection, insecure `eval()`, weak hash algorithms (`md5`, `sha1`),
  command injection via `subprocess`, insecure deserialization (`pickle.loads`)
- C++: format string vulnerabilities, buffer sizing errors, use of deprecated
  unsafe functions (`strcpy`, `sprintf`, `gets`)
- Go: SQL injection, SSRF, path traversal, insecure TLS configuration,
  weak random number generation

**Rulesets active:** `p/default`, `p/python`, `p/cpp`, `p/golang`, `p/owasp-top-ten`,
`p/cwe-top-25`, `p/secrets`, `p/supply-chain`

#### Trivy (SCA — Software Composition Analysis)

Trivy scans your dependency manifests against vulnerability databases (NVD, OSV,
GitHub Advisory) to find known CVEs in your third-party libraries.

Manifests scanned automatically:
- **Python:** `requirements.txt`, `Pipfile.lock`, `poetry.lock`, `pyproject.toml`
- **Go:** `go.mod`, `go.sum`
- **C++:** `conanfile.txt`, `conanfile.py`, `vcpkg.json`
- **General:** `Dockerfile`, `docker-compose*.yml`, `*.tf` (IaC misconfigurations)

Trivy also runs its own secret scanner and misconfiguration checks as additional layers.

#### Branch-aware severity thresholds

| Branch | Blocks on | Behaviour |
|---|---|---|
| `master` | CRITICAL + HIGH | Strict — no vulnerable code reaches stable |
| `develop` | CRITICAL + HIGH | Strict — integration branch is kept clean |
| `feature/**` | CRITICAL only | Relaxed — allows WIP without blocking progress |

`ignore-unfixed: true` is set globally — CVEs with no available patch are reported
but do not block (there is nothing you can do about them yet).

---

### `03-codeql.yml` — Deep Semantic Analysis

**Trigger:** Push to `develop`/`master`, PRs to those branches, weekly schedule
**Tool:** [CodeQL](https://codeql.github.com/) (GitHub's own analysis engine)
**Query suite:** `security-and-quality`

CodeQL is fundamentally different from Semgrep. Instead of pattern matching, it:
1. Compiles your code into a relational database representing every variable,
   function, call, and data flow path
2. Runs Datalog queries against this database
3. Can find vulnerabilities that span multiple files, function calls, and
   data transformations — things pattern matching cannot see

Examples of what CodeQL finds that Semgrep cannot:
- A user-controlled HTTP parameter that flows through 5 function calls and
  eventually reaches an SQL query without sanitisation (taint tracking)
- A buffer allocated in one function with a size calculated from untrusted input
  in a different module (interprocedural analysis)
- Format string vulnerabilities where the format specifier is constructed
  dynamically across multiple code paths

**C++ note:** CodeQL must observe a real compilation. The `autobuild` step handles
standard `cmake`/`make`/`ninja` projects. For non-standard build systems, replace
the autobuild step with your actual build commands.

Results appear in **GitHub → Security → Code scanning alerts**.

---

### `04-history-scan.yml` — Historical Secret Scan

**Trigger:** Weekly (Saturday 01:00 UTC) + manual `workflow_dispatch`
**Tool:** [TruffleHog](https://github.com/trufflesecurity/trufflehog)

This workflow solves a specific and often overlooked problem:

> You committed a secret two months ago, noticed it, deleted the file,
> and moved on. The file is gone from `HEAD` — but **every commit where it
> existed is still in the git history**, readable by `git log -p` or
> by cloning the repo.

TruffleHog scans from the first commit to `HEAD`, checking every file change
in every commit.

**`--only-verified` mode (default):** TruffleHog actually calls the service API
to confirm that the detected credential still works. A verified result means
a **live, active, compromised credential**. This dramatically reduces false
positives — you only get alerted about things that are actually dangerous right now.

You can disable verification via the manual trigger input to see all detections
including expired/invalid secrets (useful for compliance audits).

---

## Local Pre-commit Hooks

### Setup

```bash
pip install pre-commit
pre-commit install
pre-commit install --hook-type commit-msg  # for conventional commit enforcement
pre-commit install --hook-type pre-push    # for pre-push hooks
```

### First run (scan all existing files)

```bash
pre-commit run --all-files
```

### Creating the detect-secrets baseline

```bash
detect-secrets scan > .secrets.baseline
git add .secrets.baseline
git commit -m "chore: add detect-secrets baseline"
```

If detect-secrets flags something that is intentionally in the codebase
(a test fixture, an example in docs):
```bash
detect-secrets audit .secrets.baseline
# Follow interactive prompts to mark items as false positives
```

### Hooks installed

| Hook | Purpose |
|---|---|
| Gitleaks | Secret detection (same engine as CI) |
| detect-secrets | Entropy-based secondary secret detection |
| Bandit | Python security linter |
| Ruff | Python linter with security rules (S category) |
| go vet + go fmt | Go analysis and formatting |
| clang-format | C/C++ formatting |
| detect-private-key | Blocks RSA/EC/DSA private key files |
| check-added-large-files | Blocks files > 1 MB |
| conventional-pre-commit | Enforces commit message format |

---

## GitHub Security Tab

All four workflows upload results as SARIF files to GitHub's Security tab.
Navigate to: **Repository → Security → Code scanning alerts**

This gives you a single dashboard with:
- All open findings across all tools
- Severity classification
- File and line number
- CWE/CVE reference
- Ability to dismiss findings with a reason (false positive, accepted risk, etc.)
- Trend graphs over time

Dismissed alerts are remembered — the same finding won't alert again unless the
code changes.

---

## Dependabot

Dependabot runs weekly and opens Pull Requests for:
- Python packages (`requirements.txt`, `pyproject.toml`, etc.)
- Go modules (`go.mod`)
- GitHub Actions versions (the `uses:` pins in workflow files)

**Important:** Dependabot PRs themselves trigger `02-sast-sca.yml`. Trivy
rescans the updated manifest before you merge, so even Dependabot's updates
are validated.

Minor and patch updates are grouped into a single PR per ecosystem to reduce
notification noise. Major version updates are always separate PRs (they may
contain breaking changes requiring manual review).

C++ dependency updates (Conan, vcpkg) are handled by Trivy in the SCA workflow
rather than Dependabot, which does not yet support those ecosystems.

---

## Enabling Required Status Checks (Recommended)

Even without mandatory PRs, you can make GitHub block direct pushes to `master`
and `develop` if the security pipeline fails:

1. Go to **Repository → Settings → Branches**
2. Add a branch protection rule for `master` and `develop`
3. Enable **"Require status checks to pass before merging"**
4. Add these checks:
   - `Gitleaks — Secret Scan`
   - `Security Gate`
   - `CodeQL — cpp` / `CodeQL — python` / `CodeQL — go`
5. Leave **"Require a pull request before merging"** DISABLED (solo workflow)
6. Enable **"Do not allow bypassing the above settings"** if you want hard enforcement

This lets you push directly (no PR required) but blocks the push if any
security check fails — the best of both worlds for a solo developer.

---

## Adding a New Project

Copy these files into the new repository:

```
.github/
  workflows/
    01-secret-scan.yml
    02-sast-sca.yml
    03-codeql.yml
    04-history-scan.yml
  dependabot.yml
.pre-commit-config.yaml
.gitleaks.toml
SECURITY.md
```

Then:
1. Run `pre-commit install` on your local clone
2. Run `detect-secrets scan > .secrets.baseline` and commit the baseline
3. Push — all workflows will activate automatically
4. Configure required status checks in Branch Protection (see above)
5. For C++ projects: verify the CodeQL autobuild step works, or replace it
   with your actual build commands

No tokens or secrets are required. All tools run on public GitHub-hosted runners
for free on public repositories.

---

## Secrets Required in Repository Settings

None required for basic operation. All tools run without additional credentials
on public repositories.

**Optional enhancements:**
- `SEMGREP_APP_TOKEN` — links Semgrep results to [Semgrep Cloud](https://semgrep.dev)
  dashboard for team collaboration and historical trend tracking. Free tier available.
