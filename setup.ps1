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

    Interactive by default: with no selection flags, a bare ./setup.ps1 asks
    what to do (install or clean), which harness to configure (Both /
    OpenCode / Copilot), how to install skills (copy or link
    shortcut), and where (global or local scope). Pass any flag explicitly to
    skip its question; -Yes answers everything with defaults (automation/CI).

.PARAMETER Scope
    global (default) - ~/.agents/skills, all projects for this user
    local            - .agents/skills inside this repo. Local scope installs
                       skills only; the user-level rules files are skipped
                       (this repo's own AGENTS.md already applies here).

.PARAMETER Mode
    copy (default) - copy skill directories
    link           - directory junction per skill

.PARAMETER Clean
    Unlink / remove the entries this script manages from the target.
    Offered as a menu choice in interactive mode too.

.PARAMETER Interactive
    Force the guided menu even if flags were passed. Errors when no console
    is attached (pass flags explicitly instead).

.PARAMETER Yes
    Answer every menu question with its default (both harnesses, copy,
    global scope). For automation and CI. Alias: -NonInteractive.

    Rules files carry a managed marker: an existing file without the marker
    is never overwritten, and -Clean removes only marked ones.
    -OpenCodeRules / -CopilotRules are accepted but ignored (both rules
    files are always installed).

.EXAMPLE
    ./setup.ps1
.EXAMPLE
    ./setup.ps1 -Mode link
.EXAMPLE
    ./setup.ps1 -Scope local -Mode link
.EXAMPLE
    ./setup.ps1 -Clean
.EXAMPLE
    ./setup.ps1 -Yes
#>
[CmdletBinding()]
param(
    [ValidateSet('global', 'local')]
    [string]$Scope = 'global',

    [ValidateSet('copy', 'link')]
    [string]$Mode = 'copy',

    [switch]$Clean,

    [switch]$Interactive,

    [Alias('NonInteractive')]
    [switch]$Yes,

    [switch]$OpenCodeRules,

    [switch]$CopilotRules
)

$ErrorActionPreference = 'Stop'

function Test-CanPrompt {
    try {
        return [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    }
    catch { return $false }
}

function Read-MenuChoice {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$Default = 0
    )
    Write-Host ""
    Write-Host $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $mark = if ($i -eq $Default) { " (default)" } else { "" }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $Options[$i], $mark)
    }
    while ($true) {
        $answer = Read-Host ("Select [1-{0}, Enter={1}]" -f $Options.Count, ($Default + 1))
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $answer = $answer.Trim()
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return ($n - 1) }
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($Options[$i] -ieq $answer) { return $i }
        }
        Write-Host ("  Enter 1-{0}, a listed name, or empty for default." -f $Options.Count)
    }
}

$canPrompt = Test-CanPrompt
if ($Interactive -and $Yes) {
    throw "Cannot combine -Interactive with -Yes/-NonInteractive."
}
if ($Interactive -and -not $canPrompt) {
    throw "Interactive mode requested (-Interactive) but no console is attached. Run in a terminal or pass flags explicitly."
}
$quiet = $Yes -or (-not $canPrompt -and -not $Interactive)

$skipOpenCodeRules = $false
$skipCopilotRules = $false
if (-not $quiet) {
    if (-not $PSBoundParameters.ContainsKey('Clean')) {
        $action = Read-MenuChoice -Title "What do you want to do?" -Options @('Install skills', 'Clean up installed files') -Default 0
        if ($action -eq 1) { $Clean = $true }
    }
    if ($Clean) {
        $harness = Read-MenuChoice -Title "Which rules files apply?" -Options @('Both', 'OpenCode only', 'Copilot only') -Default 0
    }
    else {
        $harness = Read-MenuChoice -Title "Which harness do you want to configure?" -Options @('Both (OpenCode + Copilot)', 'OpenCode only', 'Copilot only') -Default 0
    }
    switch ($harness) {
        1 { $skipCopilotRules = $true }
        2 { $skipOpenCodeRules = $true }
    }
    if (-not $Clean -and -not $PSBoundParameters.ContainsKey('Mode')) {
        $modeChoice = Read-MenuChoice -Title "How should skill files be installed?" -Options @('Copy (safe snapshot; re-run to refresh)', 'Link shortcut (junction; edits apply immediately)') -Default 0
        if ($modeChoice -eq 1) { $Mode = 'link' }
    }
    if (-not $PSBoundParameters.ContainsKey('Scope')) {
        $scopeChoice = Read-MenuChoice -Title "Where should skills be installed?" -Options @('Global (~/.agents/skills, every project)', 'Local (.agents/skills in this repo only)') -Default 0
        if ($scopeChoice -eq 1) { $Scope = 'local' }
    }
}

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

# --- Always-on rules (always installed) -------------------------------------
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

$installOpenCodeRules = (-not $skipOpenCodeRules) -and ($Scope -eq 'global')
$installCopilotRules = (-not $skipCopilotRules) -and ($Scope -eq 'global')
$localScopeNote = "Local scope: skipping user-level rules files (this repo's own AGENTS.md already applies here)."

if ($Clean) {
    if ($installOpenCodeRules -or $installCopilotRules) {
        Write-Host "Cleaning always-on rules files"
    }
    elseif ($Scope -ne 'global') {
        Write-Host "  $localScopeNote"
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
    elseif ($Scope -ne 'global') {
        Write-Host "  $localScopeNote"
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
