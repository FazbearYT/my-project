# =============================================================================
# setup-repo.ps1 — Run once per new project, after first push to GitHub
# =============================================================================
# Requirements:
#   - GitHub CLI installed and authenticated (gh auth login)
#   - Run from inside your repository directory
#   - Repository must already exist on GitHub with at least one push
#
# Usage (from PowerShell inside your repo directory):
#   .\scripts\setup-repo.ps1
#
# If blocked by execution policy, run this once first:
#   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
# =============================================================================

param(
    [switch]$DryRun  # Pass -DryRun to preview actions without executing them
)

$ErrorActionPreference = "Stop"

# ── Colour helpers ────────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Write-Step    { param($msg) Write-Host "`n──── $msg ────`n" -ForegroundColor White }

if ($DryRun) { Write-Host "[DRY RUN MODE — no changes will be made]`n" -ForegroundColor Magenta }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
Write-Step "Pre-flight checks"

if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { Write-Fail "GitHub CLI not found.  Run: winget install GitHub.cli" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Fail "git not found.         Run: winget install Git.Git" }
if (-not (Get-Command jq  -ErrorAction SilentlyContinue)) { Write-Fail "jq not found.          Run: winget install jqlang.jq" }

git rev-parse --git-dir 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Not inside a git repository." }

$repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
if (-not $repo -or $LASTEXITCODE -ne 0) {
    Write-Fail "Could not detect GitHub repo. Have you pushed at least once? Is 'gh auth login' done?"
}
Write-Info "Repository : $repo"

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "Not authenticated. Run: gh auth login" }
Write-Success "All pre-flight checks passed."

# ── Step 1: GitHub labels ─────────────────────────────────────────────────────
Write-Step "Step 1 — Create GitHub labels"

$labels = [ordered]@{
    "security"          = @{ color = "0075ca"; desc = "General security findings" }
    "critical"          = @{ color = "d93f0b"; desc = "Critical severity — immediate action required" }
    "secret-detected"   = @{ color = "e11d48"; desc = "A secret or credential was found in code" }
    "historical-secret" = @{ color = "f97316"; desc = "Secret found in git history" }
    "dependencies"      = @{ color = "0075ca"; desc = "Dependency updates from Dependabot" }
    "python"            = @{ color = "3572A5"; desc = "Python dependency update" }
    "go"                = @{ color = "00ADD8"; desc = "Go dependency update" }
    "github-actions"    = @{ color = "2088FF"; desc = "GitHub Actions workflow update" }
}

foreach ($name in $labels.Keys) {
    $color = $labels[$name].color
    $desc  = $labels[$name].desc

    if ($DryRun) { Write-Info "[DRY RUN] Would create label: $name ($color)"; continue }

    gh label create $name --color $color --description $desc --repo $repo 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Created  : $name"
    } else {
        gh label edit $name --color $color --description $desc --repo $repo 2>$null | Out-Null
        Write-Success "Updated  : $name"
    }
}

# ── Step 2: develop branch ────────────────────────────────────────────────────
Write-Step "Step 2 — Create 'develop' branch"

$currentBranch = git symbolic-ref --short HEAD
Write-Info "Current branch: $currentBranch"

$developExists = git ls-remote --exit-code --heads origin develop 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Success "'develop' already exists on remote."
} else {
    if (-not $DryRun) {
        # Create locally and push
        $switchResult = git checkout -b develop 2>&1
        if ($LASTEXITCODE -ne 0) { git checkout develop 2>&1 | Out-Null }
        git push -u origin develop
        git checkout $currentBranch 2>&1 | Out-Null
    }
    Write-Success "'develop' branch created and pushed."
}

# ── Step 3: Branch protection ─────────────────────────────────────────────────
Write-Step "Step 3 — Configure branch protection (master + develop)"

# These names must EXACTLY match the job names in the workflow YAML files
$requiredChecks = @("Gitleaks — Secret Scan", "Security Gate")
Write-Info "Required checks : $($requiredChecks -join ', ')"
Write-Info "PRs required    : NO (solo developer mode)"

function Set-BranchProtection {
    param([string]$branchName)

    $exists = git ls-remote --exit-code --heads origin $branchName 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Branch '$branchName' not found on remote — skipping."
        return
    }

    if ($DryRun) { Write-Info "[DRY RUN] Would protect branch: $branchName"; return }

    # Build JSON payload — null values are important here (disables PR requirement)
    $payload = @{
        required_status_checks = @{
            strict   = $false
            contexts = $requiredChecks
        }
        enforce_admins                = $false
        required_pull_request_reviews = $null
        restrictions                  = $null
        allow_force_pushes            = $false
        allow_deletions               = $false
    } | ConvertTo-Json -Depth 5 -Compress

    $payload | gh api `
        --method PUT `
        "repos/$repo/branches/$branchName/protection" `
        --input - 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Protected : $branchName"
        Write-Info "  Required checks  : $($requiredChecks -join ', ')"
        Write-Info "  Force push       : BLOCKED"
        Write-Info "  Branch deletion  : BLOCKED"
        Write-Info "  PR required      : NO"
    } else {
        Write-Warn "Could not set protection on '$branchName'. Run the script again after the first workflow run completes."
    }
}

Set-BranchProtection "master"
Set-BranchProtection "develop"

# ── Step 4: Dependabot ────────────────────────────────────────────────────────
Write-Step "Step 4 — Enable Dependabot security features"

if (-not $DryRun) {
    gh api --method PUT "repos/$repo/vulnerability-alerts"    2>$null | Out-Null
    Write-Success "Vulnerability alerts    : enabled"

    gh api --method PUT "repos/$repo/automated-security-fixes" 2>$null | Out-Null
    Write-Success "Automated security fixes: enabled"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Repository security setup complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "What was configured:" -ForegroundColor White
Write-Host "  Labels created   : $($labels.Count)"
Write-Host "  Branches         : master (protected), develop (protected)"
Write-Host "  Required checks  : $($requiredChecks -join ', ')"
Write-Host "  Dependabot       : enabled"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Push any commit to trigger the first workflow run"
Write-Host "  2. Open Actions tab and verify all 3 workflows start"
Write-Host "  3. After they pass, branch protection is fully active"
Write-Host "  4. Run:  pre-commit run --all-files"
Write-Host ""
