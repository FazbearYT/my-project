# Security Pipeline — Linux Setup Guide
### From a fresh computer to a fully protected GitHub repo

> This guide is written for Ubuntu / Debian (apt). For Arch use `pacman`,
> for Fedora/RHEL use `dnf` — package names are the same, syntax differs.

---

## What this guide covers

```
PHASE 1  Machine setup        (do once per Linux machine)
PHASE 2  GitHub account       (do once per GitHub account)
PHASE 3  New project          (do every time you start a repo)
```

---

# PHASE 1 — Machine Setup
## Do once. Never repeat unless you get a new machine.

---

## 1.1 — Update the system

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 1.2 — Install essential base packages

```bash
sudo apt install -y \
    curl \
    wget \
    git \
    build-essential \
    pkg-config \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    jq
```

Verify git:
```bash
git --version   # Expected: git version 2.x.x
jq --version    # Expected: jq-1.x.x
```

---

## 1.3 — Install Python 3.12+

```bash
# Check what version you already have
python3 --version

# If it's below 3.10, add the deadsnakes PPA for a newer version:
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip

# Verify
python3 --version    # Expected: Python 3.12.x (or your installed version)
pip3 --version       # Expected: pip 24.x
```

> On newer Ubuntu (22.04+), `python3` may already be 3.10 or 3.11, which is
> fine. You do not strictly need 3.12.

---

## 1.4 — Install GitHub CLI

GitHub CLI is not in the default apt repositories. Add the official one:

```bash
# Add GitHub CLI's official apt repository
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg

sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list

sudo apt update
sudo apt install gh -y
```

Verify:
```bash
gh --version   # Expected: gh version 2.x.x
```

**Authenticate with your GitHub account (do this once):**
```bash
gh auth login
```

At the prompts:
1. **GitHub.com**
2. **HTTPS**
3. **Login with a web browser** → press Enter
4. Copy the 8-character code from the terminal
5. Browser opens → paste the code → Authorize

Verify:
```bash
gh auth status
# Expected: Logged in to github.com as YOUR_USERNAME
```

---

## 1.5 — Install Go

```bash
# Download the latest stable Go release
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1)
curl -OL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz"

# Remove any previous Go installation and extract
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "${GO_VERSION}.linux-amd64.tar.gz"
rm "${GO_VERSION}.linux-amd64.tar.gz"

# Add to PATH (add to ~/.bashrc or ~/.zshrc for persistence)
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

Verify:
```bash
go version   # Expected: go version go1.22.x linux/amd64
```

---

## 1.6 — Install LLVM / clang-format (for C++ hook)

```bash
# Add LLVM's official repository for the latest version
wget -qO- https://apt.llvm.org/llvm.sh | sudo bash -s 18

sudo apt install -y clang-format-18
sudo ln -sf /usr/bin/clang-format-18 /usr/local/bin/clang-format
```

Verify:
```bash
clang-format --version   # Expected: clang-format version 18.x.x
```

---

## 1.7 — Install pre-commit and detect-secrets

```bash
pip3 install --user pre-commit detect-secrets
```

If `pre-commit` is not found after installation, add pip's user bin to PATH:
```bash
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc
```

Verify:
```bash
pre-commit --version      # Expected: pre-commit 3.x.x
detect-secrets --version  # Expected: 1.x.x
```

---

## 1.8 — Configure git globals

```bash
git config --global user.name  "Your Name"
git config --global user.email "your@email.com"
git config --global init.defaultBranch master
git config --global core.autocrlf input
git config --global push.default current
git config --global core.pager "less -FRX"
```

Verify:
```bash
git config --global --list
```

---

## 1.9 — Verify everything is installed

```bash
declare -A tools=(
    ["git"]="git --version"
    ["gh"]="gh --version"
    ["python3"]="python3 --version"
    ["pip3"]="pip3 --version"
    ["go"]="go version"
    ["clang-format"]="clang-format --version"
    ["jq"]="jq --version"
    ["pre-commit"]="pre-commit --version"
    ["detect-secrets"]="detect-secrets --version"
)

for name in "${!tools[@]}"; do
    output=$(${tools[$name]} 2>&1 | head -1)
    if [[ $? -eq 0 ]]; then
        printf "  \e[32m[OK]\e[0m  %-18s %s\n" "$name" "$output"
    else
        printf "  \e[31m[!!]\e[0m  %-18s NOT FOUND\n" "$name"
    fi
done
```

All items should show `[OK]`.

---

## 1.10 — Save your pipeline template

```bash
mkdir -p ~/templates/security-pipeline
# Copy the contents of security-pipeline-template.zip here
# Structure:
# ~/templates/security-pipeline/
#   .github/
#     workflows/
#       01-secret-scan.yml  ...
#     dependabot.yml
#   scripts/
#     setup-repo.sh
#     setup-repo.ps1
#   .pre-commit-config.yaml
#   .gitleaks.toml
#   SECURITY.md
```

---

# PHASE 2 — GitHub Account Setup
## Do once. Identical to the Windows guide — it's all in the browser.

---

## 2.1 — Enable Dependabot globally

1. Go to **github.com → (your profile picture) → Settings**
2. Left sidebar → **Code security and analysis**
3. Enable all three:
   - **Dependency graph** → Enable
   - **Dependabot alerts** → Enable
   - **Dependabot security updates** → Enable

---

## 2.2 — Enable Secret Scanning globally

Same page → **Secret scanning** → Enable for all repositories

---

## 2.3 — Enable Code Scanning default setup

Same page → **Code scanning** → Enable (if available)

---

## 2.4 — Optional: Semgrep Cloud account

1. Sign up at **semgrep.dev** with your GitHub account (free)
2. Settings → Tokens → Create token
3. In each repo: **Settings → Secrets → Actions → New secret**
   - Name: `SEMGREP_APP_TOKEN`, Value: your token

---

# PHASE 3 — Starting a New Project
## Do this every time. ~10 minutes.

---

> **Assumed starting point:** You have a new empty directory on your machine.

---

## Step 1 — Open terminal in your projects folder

```bash
# Create and enter the project directory
mkdir -p ~/projects/my-project
cd ~/projects/my-project
```

---

## Step 2 — Initialize git

```bash
git init
```

Expected: `Initialized empty Git repository in .../my-project/.git/`

---

## Step 3 — Copy the pipeline template

```bash
cp -r ~/templates/security-pipeline/. .
ls -la   # Should show .github/, scripts/, .pre-commit-config.yaml, etc.
```

---

## Step 4 — Create .gitignore

```bash
# Download .gitignore for your language(s). Combine as needed.

# C++
curl -sL https://raw.githubusercontent.com/github/gitignore/main/C%2B%2B.gitignore \
  > .gitignore

# Python (append)
curl -sL https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore \
  >> .gitignore

# Go (append)
curl -sL https://raw.githubusercontent.com/github/gitignore/main/Go.gitignore \
  >> .gitignore
```

Add universal rules:
```bash
cat >> .gitignore << 'EOF'

# Environment files — NEVER commit these
.env
.env.*
*.env
!.env.example

# IDE
.vscode/settings.json
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF
```

---

## Step 5 — Create the GitHub repo

```bash
gh repo create my-project --public --source=. --remote=origin \
  --description "Your project description"
```

Or if you already created it on GitHub manually:
```bash
git remote add origin https://github.com/YOUR_USERNAME/my-project.git
git remote -v   # Verify
```

---

## Step 6 — Install pre-commit hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

Expected:
```
pre-commit installed at .git/hooks/pre-commit
pre-commit installed at .git/hooks/commit-msg
```

---

## Step 7 — Create the detect-secrets baseline

```bash
detect-secrets scan > .secrets.baseline
detect-secrets audit .secrets.baseline
```

The audit is interactive. For each finding press:
- `y` = real secret (block it)
- `n` = false positive (allow it)

For a fresh repo with only pipeline files, all findings are almost certainly
false positives. Mark them `n`.

---

## Step 8 — First clean run of all hooks

```bash
pre-commit run --all-files
```

If hooks auto-fix files (line endings, formatting), run again:
```bash
pre-commit run --all-files
```

Repeat until all hooks show `Passed`.

---

## Step 9 — First commit

```bash
git add .
git commit -m "chore: initial project setup with security pipeline"
```

The commit itself runs through Gitleaks and detect-secrets via the hooks.

---

## Step 10 — Push to GitHub

```bash
git push -u origin master
```

Opens three workflow runs on GitHub Actions simultaneously. Watch them:
```bash
gh browse   # Opens repo in browser
```

Or directly:
```bash
xdg-open "https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions"
```

---

## Step 11 — Run the setup script

```bash
chmod +x scripts/setup-repo.sh
bash scripts/setup-repo.sh
```

This creates GitHub labels, the `develop` branch, branch protection on
`master` and `develop`, and enables Dependabot.

> **If branch protection fails:** The check names only appear after the first
> workflow run completes. Wait ~2 minutes, then run the script again.

---

## Step 12 — Verify branch protection

```bash
echo 'API_KEY = "AKIAIOSFODNN7EXAMPLE"' > test-secret.py
git add test-secret.py
git commit -m "test: verify pipeline catches secrets"
git push
```

The push lands on GitHub but the `01-secret-scan` workflow should fail within
30 seconds, blocking the commit from touching protected branches.

Clean up:
```bash
git rm test-secret.py
git commit -m "chore: remove secret test file"
git push
```

---

## Step 13 — Start working

```bash
# New feature
git checkout develop
git checkout -b feature/my-feature

# Work, commit (hooks run on every commit)
git add .
git commit -m "feat(scope): description"

# Push — triggers secret scan + SAST/SCA
git push -u origin feature/my-feature

# Merge into develop when done
git checkout develop
git merge feature/my-feature
git push
# → triggers SAST/SCA + CodeQL

# Stable release to master
git checkout master
git merge develop
git push
```

---

## Quick Reference — Linux Commands

```bash
# ── Per-machine (run once) ──────────────────────────────────────────────────
sudo apt install -y curl wget git build-essential jq
pip3 install --user pre-commit detect-secrets
gh auth login

# ── Per-project ──────────────────────────────────────────────────────────────
gh repo create PROJECT --public --source=. --remote=origin
pre-commit install
pre-commit install --hook-type commit-msg
detect-secrets scan > .secrets.baseline
detect-secrets audit .secrets.baseline
pre-commit run --all-files
git add . && git commit -m "chore: initial setup"
git push -u origin master
bash scripts/setup-repo.sh

# ── Daily use ────────────────────────────────────────────────────────────────
git checkout develop && git checkout -b feature/NAME
git push -u origin feature/NAME
pre-commit run --all-files
pre-commit autoupdate && git add .pre-commit-config.yaml
gh workflow run 04-history-scan.yml
```

---

## Troubleshooting — Linux

### `pre-commit: command not found`

```bash
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc
```

### `clang-format: command not found` in pre-commit

```bash
sudo apt install clang-format
# or for a specific version:
sudo apt install clang-format-18
sudo ln -sf /usr/bin/clang-format-18 /usr/local/bin/clang-format
```

### `go: command not found` after installation

```bash
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### Branch protection fails with "context not found"

The workflow must run at least once before GitHub recognises the check name.
```bash
git commit --allow-empty -m "ci: trigger initial workflow run"
git push
# Wait ~2 minutes for workflows to complete
bash scripts/setup-repo.sh
```

### `detect-secrets scan` hangs on large repos

```bash
# Exclude large directories
detect-secrets scan --exclude-files "node_modules|\.git|build|dist" > .secrets.baseline
```

### pre-commit hooks don't run after cloning to a new machine

The `.git/hooks/` folder is not part of the repository. On every new clone:
```bash
pre-commit install
pre-commit install --hook-type commit-msg
```
