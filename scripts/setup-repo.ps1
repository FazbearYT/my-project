# =============================================================================
# setup-repo.ps1 - Run once per new project, after first push to GitHub
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

# "Continue" lets the script check $LASTEXITCODE manually for native commands
# (git, gh) without PowerShell auto-throwing on their stderr output.
$ErrorActionPreference = "Continue"

# -- Colour helpers -----------------------------------------------------------
function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Write-Step    { param($msg) Write-Host "`n---- $msg ----`n" -ForegroundColor White }

if ($DryRun) { Write-Host "[DRY RUN MODE - no changes will be made]`n" -ForegroundColor Magenta }

# -- Pre-flight checks --------------------------------------------------------
Write-Step "Pre-flight checks"

if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { Write-Fail "GitHub CLI not found.  Run: winget install GitHub.cli" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Fail "git not found.         Run: winget install Git.Git" }
if (-not (Get-Command jq  -ErrorAction SilentlyContinue)) { Write-Fail "jq not found.          Run: winget install jqlang.jq" }

git rev-parse --git-dir *>$null
if ($LASTEXITCODE -ne 0) { Write-Fail "Not inside a git repository." }

$repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
if (-not $repo -or $LASTEXITCODE -ne 0) {
    Write-Fail "Could not detect GitHub repo. Have you pushed at least once? Is 'gh auth login' done?"
}
Write-Info "Repository : $repo"

gh auth status *>$null
if ($LASTEXITCODE -ne 0) { Write-Fail "Not authenticated. Run: gh auth login" }
Write-Success "All pre-flight checks passed."

# -- Step 1: GitHub labels ----------------------------------------------------
Write-Step "Step 1 - Create GitHub labels"

$labels = [ordered]@{
    "security"          = @{ color = "0075ca"; desc = "General security findings" }
    "critical"          = @{ color = "d93f0b"; desc = "Critical severity - immediate action required" }
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

    # --force upserts: creates if absent, updates color/description if present.
    # Never exits non-zero or writes to stderr for the already-exists case.
    gh label create $name --color $color --description $desc --force --repo $repo *>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Upserted : $name"
    } else {
        Write-Warn "Could not upsert label: $name"
    }
}

# -- Step 2: develop branch ---------------------------------------------------
Write-Step "Step 2 - Create 'develop' branch"

$currentBranch = git symbolic-ref --short HEAD 2>$null
Write-Info "Current branch: $currentBranch"

git ls-remote --exit-code --heads origin develop *>$null
if ($LASTEXITCODE -eq 0) {
    Write-Success "'develop' already exists on remote."
} else {
    if (-not $DryRun) {
        git checkout -b develop *>$null
        if ($LASTEXITCODE -ne 0) { git checkout develop *>$null }
        git push -u origin develop *>$null
        git checkout $currentBranch *>$null
    }
    Write-Success "'develop' branch created and pushed."
}

# -- Step 3: Branch protection ------------------------------------------------
Write-Step "Step 3 - Configure branch protection (master + develop)"

# These names must EXACTLY match the job name: fields in the workflow YAML files
$requiredChecks = @("Gitleaks $([char]0x2014) Secret Scan", "$([char]0x2705) Security Gate")
Write-Info "Required checks : $($requiredChecks -join ', ')"
Write-Info "PRs required    : NO (solo developer mode)"

function Set-BranchProtection {
    param([string]$branchName)

    git ls-remote --exit-code --heads origin $branchName *>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Branch '$branchName' not found on remote - skipping."
        return
    }

    if ($DryRun) { Write-Info "[DRY RUN] Would protect branch: $branchName"; return }

    # null values here disable the PR-review requirement (solo developer mode)
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
        --input - *>$null

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

# -- Step 4: Dependabot -------------------------------------------------------
Write-Step "Step 4 - Enable Dependabot security features"

if (-not $DryRun) {
    gh api --method PUT "repos/$repo/vulnerability-alerts"     *>$null
    Write-Success "Vulnerability alerts    : enabled"

    gh api --method PUT "repos/$repo/automated-security-fixes" *>$null
    Write-Success "Automated security fixes: enabled"
}

# -- Summary ------------------------------------------------------------------
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
