#!/usr/bin/env bash
# =============================================================================
# setup-repo.sh — Run once per new project after first push to GitHub
# =============================================================================
# What this script does:
#   1. Creates the GitHub labels used by the security workflows
#   2. Creates the 'develop' branch if it doesn't exist
#   3. Configures branch protection on master and develop
#      (blocks pushes that fail security checks, NO pull request required)
#
# Requirements:
#   • GitHub CLI installed and authenticated (gh auth login)
#   • Run from inside the repository directory
#   • Repository must already exist on GitHub and have at least one push
#
# Usage:
#   bash scripts/setup-repo.sh
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
step()    { echo -e "\n${BOLD}──── $* ────${RESET}"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
step "Pre-flight checks"

command -v gh  >/dev/null 2>&1 || error "GitHub CLI not found. Install: https://cli.github.com"
command -v git >/dev/null 2>&1 || error "git not found."

# Verify we are inside a git repo
git rev-parse --git-dir >/dev/null 2>&1 || error "Not inside a git repository."

# Verify the repo is pushed to GitHub (remote 'origin' must exist)
REMOTE_URL=$(git remote get-url origin 2>/dev/null) || error "No remote 'origin' found. Push to GitHub first."
info "Remote: $REMOTE_URL"

# Extract owner/repo from remote URL
# Handles both HTTPS (https://github.com/owner/repo.git) and SSH (git@github.com:owner/repo.git)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) \
  || error "Could not detect repo from 'gh'. Make sure you are authenticated: gh auth login"

OWNER=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
info "Repository: $REPO"

# Verify gh is authenticated
gh auth status >/dev/null 2>&1 || error "Not authenticated. Run: gh auth login"
success "All pre-flight checks passed."

# ── Step 1: Create GitHub labels ──────────────────────────────────────────────
step "Step 1 — Create GitHub labels"

# Labels used by the four security workflows when auto-creating issues
declare -A LABELS=(
  ["security"]="0075ca:General security findings"
  ["critical"]="d93f0b:Critical severity — immediate action required"
  ["secret-detected"]="e11d48:A secret or credential was found in code"
  ["historical-secret"]="f97316:Secret found in git history"
  ["dependencies"]="0075ca:Dependency updates from Dependabot"
  ["python"]="3572A5:Python dependency update"
  ["go"]="00ADD8:Go dependency update"
  ["github-actions"]="2088FF:GitHub Actions workflow update"
)

for LABEL in "${!LABELS[@]}"; do
  COLOR=$(echo "${LABELS[$LABEL]}" | cut -d':' -f1)
  DESCRIPTION=$(echo "${LABELS[$LABEL]}" | cut -d':' -f2-)

  # Try to create; if already exists, update it
  if gh label create "$LABEL" \
       --color "$COLOR" \
       --description "$DESCRIPTION" \
       --repo "$REPO" 2>/dev/null; then
    success "Created label: $LABEL"
  else
    gh label edit "$LABEL" \
      --color "$COLOR" \
      --description "$DESCRIPTION" \
      --repo "$REPO" 2>/dev/null \
    && success "Updated label: $LABEL" \
    || warn "Label '$LABEL' already up to date."
  fi
done

# ── Step 2: Create 'develop' branch ──────────────────────────────────────────
step "Step 2 — Create 'develop' branch"

DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
info "Current branch: $DEFAULT_BRANCH"

# Check if develop exists remotely
if git ls-remote --exit-code --heads origin develop >/dev/null 2>&1; then
  success "'develop' branch already exists on remote."
else
  info "Creating 'develop' branch from $DEFAULT_BRANCH..."
  git checkout -b develop 2>/dev/null || git checkout develop
  git push -u origin develop
  git checkout "$DEFAULT_BRANCH"
  success "'develop' branch created and pushed."
fi

# ── Step 3: Configure branch protection ──────────────────────────────────────
step "Step 3 — Configure branch protection (master + develop)"

# These are the exact job names as defined in the workflow files.
# They must match for GitHub to recognise them as required status checks.
REQUIRED_CHECKS=(
  "Gitleaks — Secret Scan"
  "Security Gate"
)

info "Configuring branch protection for: master, develop"
info "Required checks: ${REQUIRED_CHECKS[*]}"
info "Pull requests required: NO (solo developer mode)"

configure_protection() {
  local BRANCH="$1"

  # Verify the branch exists on remote before trying to protect it
  if ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    warn "Branch '$BRANCH' not found on remote — skipping protection."
    return
  fi

  # Build the JSON payload for the GitHub API
  CONTEXTS_JSON=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -sc .)

  gh api \
    --method PUT \
    "repos/${REPO}/branches/${BRANCH}/protection" \
    --input - <<EOF
{
  "required_status_checks": {
    "strict": false,
    "contexts": ${CONTEXTS_JSON}
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

  success "Branch protection set on '$BRANCH'."
  info "  → Required checks : ${REQUIRED_CHECKS[*]}"
  info "  → PRs required     : NO"
  info "  → Force pushes     : BLOCKED"
  info "  → Branch deletion  : BLOCKED"
}

configure_protection "master"
configure_protection "develop"

# ── Step 4: Enable Dependabot and security alerts ─────────────────────────────
step "Step 4 — Enable GitHub security features"

# Enable vulnerability alerts (Dependabot alerts)
gh api \
  --method PUT \
  "repos/${REPO}/vulnerability-alerts" \
  2>/dev/null && success "Dependabot vulnerability alerts enabled." \
  || warn "Could not enable vulnerability alerts (may already be enabled)."

# Enable automated security fixes (Dependabot auto-PRs)
gh api \
  --method PUT \
  "repos/${REPO}/automated-security-fixes" \
  2>/dev/null && success "Dependabot automated security fixes enabled." \
  || warn "Could not enable automated security fixes (may already be enabled)."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  Repository security setup complete!               ${RESET}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Labels created:${RESET}       ${#LABELS[@]} security labels"
echo -e "  ${BOLD}Branch protection:${RESET}    master, develop"
echo -e "  ${BOLD}Required checks:${RESET}      ${REQUIRED_CHECKS[*]}"
echo -e "  ${BOLD}Dependabot:${RESET}           enabled"
echo ""
echo -e "  ${YELLOW}Next steps:${RESET}"
echo -e "  1. Push a commit to trigger the first workflow run"
echo -e "  2. Check Actions tab to verify all workflows start"
echo -e "  3. After the first run, CodeQL results appear in Security tab"
echo -e "  4. Run  ${BOLD}pre-commit run --all-files${RESET}  to verify local hooks"
echo ""
