#Requires -Version 5.1
<#
.SYNOPSIS
    Installs this repo's skills into an agent-skills discovery location.

.DESCRIPTION
    Populates a skills discovery location from ./skills. OpenCode and
    VS Code Copilot both auto-discover ~/.agents/skills and .agents/skills,
    so either scope works with zero configuration.

    Default scope is global (~/.agents/skills): the skills become available
    in every project for the current user. Use -Scope local to install into
    this repo only (.agents/skills, which is gitignored).

    Default mode is copy. Use -Mode link for a junction so edits to
    ./skills apply immediately (directory junctions on Windows need no
    admin rights or Developer Mode, unlike symlinks).

    The script is idempotent: re-running refreshes copies and recreates
    missing links. -Clean removes only entries it can prove are its own.

    Use -NoRules (or -NoOpenCodeRules / -NoCopilotRules) to skip the
    always-on rules files, which are installed by default.

.PARAMETER Scope
    global (default) - ~/.agents/skills, all projects for this user
    local            - .agents/skills inside this repo

.PARAMETER Mode
    copy (default) - copy skill directories
    link           - directory junction per skill

.PARAMETER Clean
    Unlink / remove the entries this script manages from the target.

.PARAMETER NoRules
    Skip both always-on rules files (installed by default):
    ~/.config/opencode/AGENTS.md and ~/.copilot/copilot-instructions.md.

.PARAMETER NoOpenCodeRules
    Skip ~/.config/opencode/AGENTS.md only.

.PARAMETER NoCopilotRules
    Skip ~/.copilot/copilot-instructions.md only.

    Rules files carry a managed marker: an existing file without the marker
    is never overwritten, and -Clean removes only marked ones.
    -OpenCodeRules / -CopilotRules are deprecated aliases kept for
    backwards compatibility; they no longer do anything because both files
    are installed by default.

.EXAMPLE
    ./setup.ps1
.EXAMPLE
    ./setup.ps1 -Mode link
.EXAMPLE
    ./setup.ps1 -Scope local -Mode link
.EXAMPLE
    ./setup.ps1 -Clean
.EXAMPLE
    ./setup.ps1 -NoRules
.EXAMPLE
    ./setup.ps1 -NoCopilotRules
#>
[CmdletBinding()]
param(
    [ValidateSet('global', 'local')]
    [string]$Scope = 'global',

    [ValidateSet('copy', 'link')]
    [string]$Mode = 'copy',

    [switch]$Clean,

    [switch]$NoRules,

    [switch]$NoOpenCodeRules,

    [switch]$NoCopilotRules,

    [switch]$OpenCodeRules,

    [switch]$CopilotRules
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = $PSScriptRoot
$SkillsDir = Join-Path $RepoRoot 'skills'
$TargetDir = if ($Scope -eq 'global') { Join-Path $HOME '.agents\skills' } else { Join-Path $RepoRoot '.agents\skills' }

function Test-IsLink {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

function Remove-ManagedEntry {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }

    if (Test-IsLink $Path) {
        # rmdir removes the junction itself; it never follows it to the target.
        & cmd.exe /c rmdir "`"$Path`"" | Out-Null
        Write-Host "  unlinked $Path"
        return
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        if (Test-Path -LiteralPath (Join-Path $Path 'SKILL.md')) {
            [System.IO.Directory]::Delete($Path, $true)
            Write-Host "  removed  $Path"
        }
        else {
            Write-Warning "skipped $Path - exists but is not a managed skill directory"
        }
    }
    else {
        $item.Delete()
        Write-Host "  removed  $Path"
    }
}

if (-not (Test-Path -LiteralPath $SkillsDir)) {
    throw "skills directory not found: $SkillsDir (run the script from inside the repo)"
}

$skillNames = Get-ChildItem -LiteralPath $SkillsDir -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Select-Object -ExpandProperty Name

if (-not $skillNames) {
    throw "no skills found in $SkillsDir"
}

Write-Host "Setup: scope=$Scope mode=$Mode target=$TargetDir"
if ($Clean) { Write-Host "Cleaning managed entries from $TargetDir" }
else { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }

$count = 0
foreach ($name in $skillNames) {
    $src = Join-Path $SkillsDir $name
    $dst = Join-Path $TargetDir $name

    if ($Clean) {
        Remove-ManagedEntry $dst
        continue
    }

    if ($Mode -eq 'link') {
        $existing = Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        if ($existing -and (Test-IsLink $dst) -and (Test-Path -LiteralPath (Join-Path $dst 'SKILL.md'))) {
            Write-Host "  linked   $name (already current)"
            $count++
            continue
        }
    }

    Remove-ManagedEntry $dst
    if ($Mode -eq 'link') {
        New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
        Write-Host "  linked   $name -> $src"
    }
    else {
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        Write-Host "  copied   $name"
    }
    $count++
}

if ($Clean) {
    $leftover = @(Get-ChildItem -LiteralPath $TargetDir -Force -ErrorAction SilentlyContinue)
    if ($leftover.Count -eq 0) {
        Remove-Item -LiteralPath $TargetDir -Force -ErrorAction SilentlyContinue
        Write-Host "Removed empty $TargetDir"
        $parentDir = Split-Path -Parent $TargetDir
        $parentLeftover = @(Get-ChildItem -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue)
        if ($Scope -eq 'local' -and $parentLeftover.Count -eq 0 -and (Split-Path -Leaf $parentDir) -eq '.agents') {
            Remove-Item -LiteralPath $parentDir -Force -ErrorAction SilentlyContinue
            Write-Host "Removed empty $parentDir"
        }
    }
    Write-Host "Done: cleaned $($skillNames.Count) managed entries from $TargetDir"
}
else {
    Write-Host "Done: $count skills installed to $TargetDir ($Mode)."
    if ($Scope -eq 'global') {
        Write-Host "They are now available in every project for this user. Restart any running agent session to pick them up."
    }
    else {
        Write-Host "They are now available in this repo only. Restart any running agent session to pick them up."
    }
}

# --- Always-on rules (default, opt out with -NoRules) ------------------------
#
# Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
# discover ~/.agents/skills on their own, but neither forces the discipline of
# loading a matching skill before work starts. Each harness has exactly one
# always-on user-level file that can supply that nudge:
#
#   OpenCode  ~/.config/opencode/AGENTS.md          (combined into every session)
#   Copilot   ~/.copilot/copilot-instructions.md    (Agent Host personal, every repository;
#                                                    VS Code Local agent uses profile storage instead)
#
# Both files are installed by default. Both carry the managed marker: an
# existing file without it is never overwritten, and -Clean removes only
# marked ones. Plain Markdown, no frontmatter required for these always-on
# files (frontmatter is only for *.instructions.md).

$Marker = '<!-- agent-hub:managed -->'

# Short and harness-neutral. Deliberately tiny: the skill descriptions are
# already in context through skills discovery, so this file must not repeat
# them - it only has to establish the priority.
$RulesBody = @'
<!-- agent-hub:managed -->

# Skills library

A skills library is installed on this machine at `~/.agents/skills`: a set of
step-by-step procedures for recurring engineering work (planning, debugging,
reviewing, finishing a branch).

Before you start a task, check it. If a skill covers the work you are about to
do, read `~/.agents/skills/<skill>/SKILL.md` and follow it - do not improvise a
procedure when one already exists. Skills are discovered automatically by your
harness, so this file only has to set that priority, nothing more.

Generated by the agent-hub setup script. Re-run it to refresh, or run the
setup script with `-Clean` to remove this file.
'@

function Install-RulesTarget {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        $existing = Get-Content -LiteralPath $Path -Raw
        if ($existing -notlike "*$Marker*") {
            Write-Warning "skipped $Path - exists and was not created by this script (back it up and remove it first to replace it)"
            return
        }
    }
    [System.IO.File]::WriteAllText($Path, "$($RulesBody.TrimEnd())`n")
    Write-Host "  installed $Path"
}

function Remove-RulesTarget {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $existing = Get-Content -LiteralPath $Path -Raw
    if ($existing -notlike "*$Marker*") {
        Write-Warning "kept $Path - not created by this script"
        return
    }
    Remove-Item -LiteralPath $Path -Force
    Write-Host "  removed  $Path"
}

$installOpenCodeRules = (-not $NoRules) -and (-not $NoOpenCodeRules)
$installCopilotRules = (-not $NoRules) -and (-not $NoCopilotRules)

if ($Clean) {
    if ($installOpenCodeRules -or $installCopilotRules) {
        Write-Host "Cleaning always-on rules files"
    }
    if ($installOpenCodeRules) {
        $target = Join-Path $HOME '.config/opencode/AGENTS.md'
        Remove-RulesTarget $target
    }
    if ($installCopilotRules) {
        $target = Join-Path $HOME '.copilot/copilot-instructions.md'
        Remove-RulesTarget $target
    }
}
else {
    if ($installOpenCodeRules -or $installCopilotRules) {
        Write-Host "Installing always-on rules files"
    }
    if ($installOpenCodeRules) {
        $target = Join-Path $HOME '.config/opencode/AGENTS.md'
        Install-RulesTarget $target
    }
    if ($installCopilotRules) {
        $target = Join-Path $HOME '.copilot/copilot-instructions.md'
        Install-RulesTarget $target
    }
}
