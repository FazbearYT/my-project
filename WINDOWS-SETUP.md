# Security Pipeline — Windows Setup Guide
### From a fresh computer to a fully protected GitHub repo

---

## What this guide covers

```
PHASE 1  Machine setup        (do once per Windows machine)
PHASE 2  GitHub account       (do once per GitHub account)
PHASE 3  New project          (do every time you start a repo)
```

Everything in Phase 1 and 2 survives forever. Phase 3 takes about 10 minutes
and is the only thing you repeat.

---

# PHASE 1 — Machine Setup
## Do once. Never repeat unless you get a new computer.

---

## 1.1 — Open PowerShell as Administrator

Press `Win + S`, type **PowerShell**, right-click → **Run as administrator**.

> All installation commands in this section require admin. After installation
> is done you will do everything in a regular (non-admin) PowerShell.

---

## 1.2 — Verify winget is available

winget is Microsoft's built-in package manager, available on Windows 10 (1709+)
and Windows 11.

```powershell
winget --version
```

Expected output: `v1.x.x`

If it says "not recognised":
- Windows 11: go to Microsoft Store → search **App Installer** → Update
- Windows 10: download App Installer from https://aka.ms/getwinget

---

## 1.3 — Install Windows Terminal (strongly recommended)

The default PowerShell window is limited. Windows Terminal has tabs, better
fonts, and proper UTF-8 support (needed for emoji in hook output).

```powershell
winget install Microsoft.WindowsTerminal
```

After installation, close the old window and open Windows Terminal.
**Use Windows Terminal for everything from this point on.**

Set PowerShell 7 as default inside Windows Terminal:
- Open Windows Terminal → Settings (Ctrl+,) → Startup → Default profile
- Select **PowerShell** (the one with the blue icon, not "Windows PowerShell")

---

## 1.4 — Install Git for Windows

```powershell
winget install Git.Git
```

After installation, **close and reopen** Windows Terminal so the `git` command
is available in PATH.

Verify:
```powershell
git --version
# Expected: git version 2.x.x.windows.x
```

---

## 1.5 — Install Python

```powershell
winget install Python.Python.3.12
```

Close and reopen Windows Terminal after installation.

Verify:
```powershell
python --version   # Expected: Python 3.12.x
pip --version      # Expected: pip 24.x ... (python 3.12)
```

> If `python` is not found after reopening, the installer may not have added it
> to PATH. Fix it:
> 1. Search Windows → **Edit the system environment variables**
> 2. Click **Environment Variables**
> 3. Under User variables, find **Path** → Edit
> 4. Add: `C:\Users\YOUR_USERNAME\AppData\Local\Programs\Python\Python312\`
> 5. Add: `C:\Users\YOUR_USERNAME\AppData\Local\Programs\Python\Python312\Scripts\`
> 6. Click OK everywhere, reopen terminal

---

## 1.6 — Install GitHub CLI

```powershell
winget install GitHub.cli
```

Reopen terminal, then verify:
```powershell
gh --version   # Expected: gh version 2.x.x
```

**Authenticate with your GitHub account (do this once):**
```powershell
gh auth login
```

At the prompts, choose:
1. **GitHub.com**
2. **HTTPS**
3. **Login with a web browser** → press Enter
4. Copy the 8-character code shown in terminal
5. Your browser opens → paste the code → Authorize

Verify authentication worked:
```powershell
gh auth status
# Expected: Logged in to github.com as YOUR_USERNAME
```

---

## 1.7 — Install Go (for Go projects)

```powershell
winget install GoLang.Go
```

Reopen terminal, verify:
```powershell
go version   # Expected: go version go1.22.x windows/amd64
```

---

## 1.8 — Install LLVM (provides clang-format for C++ hook)

```powershell
winget install LLVM.LLVM
```

During the LLVM installer, when asked about PATH, select:
**"Add LLVM to the system PATH for all users"**

Reopen terminal, verify:
```powershell
clang-format --version   # Expected: clang-format version 18.x.x
```

---

## 1.9 — Install jq (JSON processor, used by setup script)

```powershell
winget install jqlang.jq
```

Verify:
```powershell
jq --version   # Expected: jq-1.7.x
```

---

## 1.10 — Install pre-commit and detect-secrets

These are Python packages. Do NOT use winget for them.

```powershell
pip install pre-commit detect-secrets
```

Verify:
```powershell
pre-commit --version   # Expected: pre-commit 3.x.x
detect-secrets --version   # Expected: 1.x.x
```

> If `pre-commit` is "not recognised" after installation:
> The Python Scripts folder may not be in PATH. Add it (see Step 1.5 PATH fix)
> or run: `python -m pre_commit --version` as a test.

---

## 1.11 — Configure git globals

These settings apply to every repository on this machine.

```powershell
git config --global user.name  "Your Name"
git config --global user.email "your@email.com"
git config --global init.defaultBranch master

# Line endings: convert CRLF to LF on commit (important for cross-platform repos)
git config --global core.autocrlf input

# Better diff output
git config --global core.pager "less -FRX"

# Always push to the matching remote branch
git config --global push.default current
```

Verify your config:
```powershell
git config --global --list
```

---

## 1.12 — Allow PowerShell scripts to run

By default Windows blocks running `.ps1` scripts. Enable it for your user:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
# Type Y when prompted
```

Verify:
```powershell
Get-ExecutionPolicy -Scope CurrentUser
# Expected: RemoteSigned
```

---

## 1.13 — Verify everything is installed

Run this full check to confirm nothing is missing:

```powershell
@{
    "git"           = "git --version"
    "gh"            = "gh --version"
    "python"        = "python --version"
    "pip"           = "pip --version"
    "go"            = "go version"
    "clang-format"  = "clang-format --version"
    "jq"            = "jq --version"
    "pre-commit"    = "pre-commit --version"
    "detect-secrets"= "detect-secrets --version"
}.GetEnumerator() | ForEach-Object {
    $result = Invoke-Expression $_.Value 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [OK] {0,-16} {1}" -f $_.Key, $result) -ForegroundColor Green
    } else {
        Write-Host ("  [!!] {0,-16} NOT FOUND" -f $_.Key) -ForegroundColor Red
    }
}
```

All items should show `[OK]`. Fix any that show `[NOT FOUND]` before continuing.

---

## 1.14 — Save your pipeline template

Keep a permanent local copy of the pipeline files so you can copy them into
every future project instantly.

```powershell
# Create a templates directory in your home folder
New-Item -ItemType Directory -Path "$HOME\templates\security-pipeline" -Force

# Copy the contents of security-pipeline-template.zip there
# Structure should be:
# $HOME\templates\security-pipeline\
#   .github\
#     workflows\
#       01-secret-scan.yml
#       02-sast-sca.yml
#       03-codeql.yml
#       04-history-scan.yml
#     dependabot.yml
#   scripts\
#     setup-repo.ps1
#     setup-repo.sh
#   .pre-commit-config.yaml
#   .gitleaks.toml
#   SECURITY.md
```

---

# PHASE 2 — GitHub Account Setup
## Do once. Settings live on GitHub forever.

Open your browser for these steps.

---

## 2.1 — Enable Dependabot globally

Dependabot needs to be turned on at the account level before per-repo configs
take effect.

1. Go to: **github.com → (your profile picture top-right) → Settings**
2. In the left sidebar, click **Code security and analysis**
3. Find each of these and click **Enable all** / **Enable**:
   - **Dependency graph** → Enable
   - **Dependabot alerts** → Enable
   - **Dependabot security updates** → Enable

> These settings mean: every public repo you create will automatically
> have Dependabot watching its dependencies. The `dependabot.yml` file in
> your repo controls the schedule and grouping.

---

## 2.2 — Enable Secret Scanning globally

GitHub has its own secret scanner running in parallel to Gitleaks. Free for
all public repos. Another detection layer.

On the same **Code security and analysis** page:
- **Secret scanning** → Enable for all repositories

---

## 2.3 — Enable Code scanning (CodeQL) default setup

Still on the same page:
- **Code scanning** → if there is a "Default setup" option → Enable

This complements the CodeQL workflow you have in the pipeline.

---

## 2.4 — Optional: Create a Semgrep Cloud account

The pipeline works 100% without this. With it, you get a persistent dashboard
showing findings across all your repos and historical trends.

1. Go to **semgrep.dev** → Sign up with GitHub (free)
2. Go to **Settings → Tokens** → Create new token
3. In each GitHub repo where you want the dashboard:
   - **Repo → Settings → Secrets and variables → Actions → New repository secret**
   - Name: `SEMGREP_APP_TOKEN`
   - Value: your token from Semgrep

---

# PHASE 3 — Starting a New Project
## Do this every time. ~10 minutes.

---

> **Assumed starting point:** You have a new empty folder on your computer.
> Nothing else yet.

---

## Step 1 — Open the folder in Windows Terminal

```powershell
# Option A: navigate to it
cd C:\Users\YOUR_USERNAME\Projects\my-project

# Option B: create it now
New-Item -ItemType Directory -Path "$HOME\Projects\my-project"
cd "$HOME\Projects\my-project"
```

---

## Step 2 — Initialize git

```powershell
git init
```

Expected output: `Initialized empty Git repository in .../my-project/.git/`

---

## Step 3 — Copy the pipeline template

```powershell
# Copy everything from your saved template into the current folder
Copy-Item -Path "$HOME\templates\security-pipeline\*" `
          -Destination "." `
          -Recurse -Force
```

Verify the files are there:
```powershell
Get-ChildItem -Force   # -Force shows hidden files/folders like .github
```

You should see: `.github\`, `scripts\`, `.pre-commit-config.yaml`,
`.gitleaks.toml`, `SECURITY.md`

---

## Step 4 — Create .gitignore

```powershell
# Download the appropriate .gitignore for your language(s).
# Pick the ones that match your project:

# C++
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/github/gitignore/main/C%2B%2B.gitignore" `
                  -OutFile ".gitignore"

# Python (append to existing)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore" `
                  -OutFile "python.gitignore"
Get-Content "python.gitignore" | Add-Content ".gitignore"
Remove-Item "python.gitignore"

# Go (append to existing)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/github/gitignore/main/Go.gitignore" `
                  -OutFile "go.gitignore"
Get-Content "go.gitignore" | Add-Content ".gitignore"
Remove-Item "go.gitignore"
```

Then always add these at the bottom regardless of language:

```powershell
Add-Content ".gitignore" @"

# Environment files — NEVER commit these
.env
.env.*
*.env
!.env.example

# IDE
.vscode/settings.json
.idea/
*.swp
*.suo
*.user

# OS
Thumbs.db
Desktop.ini
"@
```

---

## Step 5 — Create the repo on GitHub

```powershell
gh repo create my-project --public --source=. --remote=origin --description "Your project description"
```

This creates the repo on GitHub AND sets the `origin` remote in one command.

If you already created the repo manually on GitHub:
```powershell
git remote add origin https://github.com/YOUR_USERNAME/my-project.git
git remote -v   # Verify it's set
```

---

## Step 6 — Install pre-commit hooks

```powershell
pre-commit install
pre-commit install --hook-type commit-msg
```

Expected:
```
pre-commit installed at .git\hooks\pre-commit
pre-commit installed at .git\hooks\commit-msg
```

> These are installed into `.git\hooks\` which is not committed to the repo.
> You need to run these two commands on every machine you clone the repo to.

---

## Step 7 — Create the detect-secrets baseline

detect-secrets needs to know which patterns in your current files are
intentionally safe, so it has a reference point.

```powershell
detect-secrets scan | Out-File -Encoding UTF8 .secrets.baseline
```

Review and approve findings interactively:
```powershell
detect-secrets audit .secrets.baseline
```

The auditor shows you each finding and asks:
- `y` → yes, this is a real secret (will block commits containing it)
- `n` → no, this is a false positive (will be allowed)

For a fresh project with only pipeline files, most findings will be false
positives (Gitleaks pattern examples in `.gitleaks.toml`, etc.). Mark them `n`.

---

## Step 8 — Run pre-commit against all files (dry run)

Before your first real commit, verify that all hooks pass on the existing files:

```powershell
pre-commit run --all-files
```

Some hooks auto-fix files (trailing whitespace, line endings). If any hook
fails with an auto-fix, the files are now corrected — just run again:

```powershell
pre-commit run --all-files
```

Keep running until everything shows `Passed`. This is your baseline clean state.

---

## Step 9 — First commit to master

```powershell
git add .
git commit -m "chore: initial project setup with security pipeline"
```

Because hooks are installed, this commit itself runs through Gitleaks and
detect-secrets before being created. You will see the hook output. If it passes,
the commit is created.

---

## Step 10 — Push to GitHub

```powershell
git push -u origin master
```

This push triggers **three GitHub Actions workflows simultaneously**:
- `01-secret-scan.yml` (Gitleaks)
- `02-sast-sca.yml` (Semgrep + Trivy)
- `03-codeql.yml` (CodeQL — detects languages and starts analysis)

Watch them run:
```powershell
# Opens the Actions tab in your browser
gh browse --no-browser  # Prints the URL
# or simply:
Start-Process "https://github.com/YOUR_USERNAME/my-project/actions"
```

---

## Step 11 — Run the setup script

```powershell
.\scripts\setup-repo.ps1
```

This script automatically:
- Creates 8 GitHub labels used by the security workflows
- Creates the `develop` branch and pushes it
- Configures branch protection on `master` and `develop`
- Enables Dependabot

Expected output:
```
──── Step 1 — Create GitHub labels ────
[OK]    Created  : security
[OK]    Created  : critical
...

──── Step 2 — Create 'develop' branch ────
[OK]    'develop' branch created and pushed.

──── Step 3 — Configure branch protection ────
[OK]    Protected : master
[OK]    Protected : develop
...

================================================
  Repository security setup complete!
================================================
```

> **If branch protection fails:** The required status check names only appear
> in GitHub after the workflows run at least once. Wait for the Actions tab to
> show the first completed run, then run the script again.

---

## Step 12 — Verify branch protection works

Test that a push with a fake secret gets blocked:

```powershell
# Create a test file with a fake-looking API key
"API_KEY = `"AKIAIOSFODNN7EXAMPLE`"" | Out-File test-secret.py
git add test-secret.py
git commit -m "test: verify pipeline catches secrets"
git push
```

The push reaches GitHub, but within 30 seconds the `01-secret-scan` workflow
will fail and turn red. Branch protection prevents this commit from being
merged into `master` or `develop`.

Clean up:
```powershell
git rm test-secret.py
git commit -m "chore: remove secret test file"
git push
```

---

## Step 13 — Start working

Your branch structure is ready. Normal workflow from here:

```powershell
# Create a feature branch off develop
git checkout develop
git checkout -b feature/my-feature

# ... write code ...

# Commit (hooks run automatically)
git add .
git commit -m "feat(my-feature): add initial implementation"

# Push (triggers secret scan + SAST/SCA on feature/*)
git push -u origin feature/my-feature

# After pipeline passes, merge into develop
git checkout develop
git merge feature/my-feature
git push
# → triggers SAST/SCA + CodeQL on develop

# When stable, merge develop into master
git checkout master
git merge develop
git push
# → triggers full pipeline including CodeQL on master
```

---

## Quick Reference — Windows Commands

```powershell
# ── Per-machine (run once) ──────────────────────────────────────────────────
winget install Git.Git Microsoft.WindowsTerminal Python.Python.3.12
winget install GitHub.cli GoLang.Go LLVM.LLVM jqlang.jq
pip install pre-commit detect-secrets
gh auth login
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# ── Per-project ──────────────────────────────────────────────────────────────
gh repo create PROJECT --public --source=. --remote=origin
pre-commit install
pre-commit install --hook-type commit-msg
detect-secrets scan | Out-File -Encoding UTF8 .secrets.baseline
detect-secrets audit .secrets.baseline
pre-commit run --all-files
git add . && git commit -m "chore: initial setup"
git push -u origin master
.\scripts\setup-repo.ps1

# ── Daily use ────────────────────────────────────────────────────────────────
git checkout develop && git checkout -b feature/NAME    # new feature
git push -u origin feature/NAME                         # push + trigger CI
pre-commit run --all-files                              # manual full scan
pre-commit autoupdate                                   # update hook versions
gh workflow run 04-history-scan.yml                     # manual history scan
```

---

## Troubleshooting — Windows

### `pre-commit: The term 'pre-commit' is not recognized`

Python's Scripts folder is not in PATH.

```powershell
# Find where pip installed it
python -c "import site; print(site.getusersitepackages())"
# Add the Scripts folder next to that location to your PATH
# Or just run as:
python -m pre_commit install
```

### `clang-format: not recognized` in pre-commit

LLVM was installed but not added to PATH.

```powershell
# Find where LLVM was installed
Get-ChildItem "C:\Program Files\LLVM\bin" -Filter "clang-format*"

# Add to PATH:
$env:PATH += ";C:\Program Files\LLVM\bin"
# To make it permanent: Edit system environment variables → PATH → add the above
```

### `git commit` creates CRLF line ending warnings

```powershell
git config --global core.autocrlf input
```

### PowerShell says "running scripts is disabled"

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### `detect-secrets scan` outputs nothing / empty file

```powershell
# UTF-8 encoding issue on some Windows versions
detect-secrets scan --output .secrets.baseline
# If that still fails:
python -m detect_secrets scan > .secrets.baseline
```
