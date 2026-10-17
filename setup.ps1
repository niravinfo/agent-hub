#Requires -Version 5.1
<#
.SYNOPSIS
    Installs this repo's skills and agents into agent discovery locations.

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
    local            - .agents/skills plus an AGENTS.md copy inside one
                       project folder (you are asked for the path; this repo
                       is the default). User-level rules files are skipped.

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

$RepoRoot  = $PSScriptRoot
$SkillsDir = Join-Path $RepoRoot 'skills'
# Default local target (mirrors setup.sh): a quiet/non-interactive local run
# installs into the repo itself; the interactive prompt below may override it.
$LocalTarget = $RepoRoot

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
        $scopeChoice = Read-MenuChoice -Title "Where should skills be installed?" -Options @('Global (~/.agents/skills, every project)', 'Local (a single project folder)') -Default 0
        if ($scopeChoice -eq 1) { $Scope = 'local' }
    }
    $LocalTarget = $RepoRoot
    if ((-not $quiet) -and ($Scope -eq 'local')) {
        while ($true) {
            $answer = Read-Host ("Target project path [Enter=$RepoRoot]")
            if ([string]::IsNullOrWhiteSpace($answer)) { break }
            $candidate = $answer.Trim()
            if (-not [System.IO.Path]::IsPathRooted($candidate)) {
                $candidate = Join-Path $RepoRoot $candidate
            }
            try { $candidate = [System.IO.Path]::GetFullPath($candidate) } catch { $candidate = $null }
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) { $LocalTarget = $candidate; break }
            Write-Host "  Directory not found. Enter an existing folder or empty for default."
        }
    }
}

$TargetDir = if ($Scope -eq 'global') { Join-Path $HOME '.agents\skills' } else { Join-Path $LocalTarget '.agents\skills' }
$TemplateAgents = Join-Path $RepoRoot 'setup\AGENTS.md'

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
        Write-Host "They are now available at the target project only. Restart any running agent session to pick them up."
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

function Install-ProjectAgents {
    param([string]$Target, [string]$Template)
    $dst = Join-Path $Target 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $Template)) {
        Write-Warning "template not found: $Template - skipping project AGENTS.md"
        return
    }
    if (Test-Path -LiteralPath $dst) {
        $have = Get-Content -LiteralPath $dst -Raw
        $want = Get-Content -LiteralPath $Template -Raw
        if ($have -ceq $want) {
            Copy-Item -LiteralPath $Template -Destination $dst -Force
            Write-Host "  refreshed $dst"
        }
        else {
            Write-Warning "skipped $dst - exists and differs from the template (merge by hand if you want the template version)"
        }
        return
    }
    Copy-Item -LiteralPath $Template -Destination $dst -Force
    Write-Host "  installed $dst"
}

function Remove-ProjectAgents {
    param([string]$Target, [string]$Template)
    $dst = Join-Path $Target 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $dst)) { return }
    if (-not (Test-Path -LiteralPath $Template)) { return }
    $have = Get-Content -LiteralPath $dst -Raw
    $want = Get-Content -LiteralPath $Template -Raw
    if ($have -ceq $want) {
        Remove-Item -LiteralPath $dst -Force
        Write-Host "  removed  $dst"
    }
    else {
        Write-Warning "kept $dst - differs from the template"
    }
}

# Runs here (not next to the skills loop above): PowerShell executes top-down,
# so the Install/Remove-ProjectAgents calls must come after their definitions.
# Same placement as setup.sh (define-before-use).
if ($Scope -eq 'local') {
    if ($Clean) { Remove-ProjectAgents -Target $LocalTarget -Template $TemplateAgents }
    else { Install-ProjectAgents -Target $LocalTarget -Template $TemplateAgents }
}

$installOpenCodeRules = (-not $skipOpenCodeRules) -and ($Scope -eq 'global')
$installCopilotRules = (-not $skipCopilotRules) -and ($Scope -eq 'global')
$localScopeNote = "Local scope: user-level rules files not touched (project AGENTS.md installed at the target instead)."

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

# --- Agents (OpenCode + Copilot) ------------------------------------------------
#
# Canonical agents live in agents/<id>.md (OpenCode format: description +
# mode: subagent + optional permissions). Each is installed per the harness
# answer already given above (no new question): Both installs both copies,
# OpenCode-only / Copilot-only install just theirs.
#
#   Global scope: OpenCode ~/.config/opencode/agents/<id>.md (verbatim) and
#                 Copilot  ~/.copilot/agents/<id>.agent.md (converted).
#   Local scope:  OpenCode <target>/.opencode/agents/<id>.md (verbatim) and
#                 Copilot  <target>/.github/agents/<id>.agent.md (converted).
#
# The Copilot copy keeps `description`, gains a `tools:` array (architect gets
# read/search/edit since it drafts proposals; the read-only reviewers get
# read/search - `search` covers both text and file search; `grep` is not a
# Copilot tool alias), and drops the OpenCode-only `mode`/`permissions` keys;
# the body is unchanged.
#
# Installed file copies carry the managed marker (<!-- agent-hub:managed -->)
# as an HTML comment line right after the frontmatter, so refresh and -Clean
# can prove ownership: an existing file without the marker is never
# overwritten or deleted. Link mode installs OpenCode copies as file symlinks
# instead (the link itself is proof of ownership); Copilot copies are always
# written files because conversion changes the bytes, so a link to the source
# could not carry the converted frontmatter. On Windows, file symlinks may
# need Developer Mode/admin rights; when linking fails the script falls back
# to a copy with a warning.

function Get-AgentDescription {
    param([string]$Path)
    $m = Select-String -LiteralPath $Path -Pattern '^description:\s*(.+)' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    return ''
}

function Get-AgentBodyLines {
    param([string[]]$Lines)
    # Only the leading frontmatter counts: a body line of exactly --- (e.g. a
    # Markdown rule) must be kept. Files without leading frontmatter pass
    # through unchanged.
    $marks = @()
    for ($i = 0; $i -lt $Lines.Count -and $marks.Count -lt 2; $i++) {
        if ($Lines[$i] -eq '---') { $marks += $i }
    }
    if ($marks.Count -eq 2 -and $marks[0] -eq 0) {
        if ($marks[1] + 1 -ge $Lines.Count) { return @() }
        return $Lines[($marks[1] + 1)..($Lines.Count - 1)]
    }
    return $Lines
}

function Get-AgentTools {
    param([string]$Id)
    if ($Id -eq 'architect') { return "['read', 'search', 'edit']" }
    return "['read', 'search']"
}

function Test-AgentDstReady {
    param([string]$Dst)
    # Get-Item -Force (not Test-Path) so a dangling symlink is seen and
    # replaced instead of written through to a resurrected target path.
    $item = Get-Item -LiteralPath $Dst -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $true }
    if (Test-IsLink $Dst) {
        Remove-Item -LiteralPath $Dst -Force
        Write-Host "  unlinked $Dst"
        return $true
    }
    $existing = Get-Content -LiteralPath $Dst -Raw
    if ($existing -notlike "*$Marker*") {
        Write-Warning "skipped $Dst - exists and was not created by this script (back it up and remove it first to replace it)"
        return $false
    }
    return $true
}

function Remove-ManagedAgentFile {
    param([string]$Path)
    # Marker-aware removal for installed agent copies. Unlike
    # Remove-ManagedEntry (built for skill directories), a plain file without
    # the marker or link proof is never deleted.
    if (-not (Test-Path -LiteralPath $Path)) {
        $link = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if (-not $link) { return }
    }
    if (Test-IsLink $Path) {
        # A file symlink: Remove-Item deletes the link itself, never the target.
        Remove-Item -LiteralPath $Path -Force
        Write-Host "  unlinked $Path"
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        Write-Warning "skipped $Path - exists but is not a managed agent file"
        return
    }
    $existing = Get-Content -LiteralPath $Path -Raw
    if ($existing -notlike "*$Marker*") {
        Write-Warning "kept $Path - not created by this script"
        return
    }
    Remove-Item -LiteralPath $Path -Force
    Write-Host "  removed  $Path"
}

function Test-ManagedAgent {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    if (Test-IsLink $Path) { return $true }
    if ($item.PSIsContainer) { return $false }
    return ((Get-Content -LiteralPath $Path -Raw) -like "*$Marker*")
}

function Install-OpenCodeAgentCopy {
    param([string]$Src, [string]$Dst)
    $parent = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Dst -PathType Container) {
        Write-Warning "skipped $Dst - exists but is not a managed agent file"
        return $false
    }
    if (-not (Test-AgentDstReady $Dst)) { return $false }
    $lines = @(Get-Content -LiteralPath $Src)
    $hasFm = ($lines.Count -gt 0 -and $lines[0] -eq '---')
    $out = New-Object System.Collections.Generic.List[string]
    if (-not $hasFm) {
        [void]$out.Add($Marker)
        [void]$out.Add('')
    }
    $dashes = 0
    foreach ($l in $lines) {
        [void]$out.Add($l)
        if ($hasFm -and $dashes -lt 2 -and $l -eq '---') {
            $dashes++
            if ($dashes -eq 2) { [void]$out.Add($Marker) }
        }
    }
    [System.IO.File]::WriteAllText($Dst, (($out -join "`n") + "`n"))
    Write-Host "  installed $Dst"
    return $true
}

function Install-CopilotAgentCopy {
    param([string]$Src, [string]$Dst, [string]$Id)
    $parent = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Dst -PathType Container) {
        Write-Warning "skipped $Dst - exists but is not a managed agent file"
        return $false
    }
    if (-not (Test-AgentDstReady $Dst)) { return $false }
    $desc = Get-AgentDescription $Src
    if ([string]::IsNullOrWhiteSpace($desc)) {
        throw "agent has no description frontmatter: $Src"
    }
    $tools = Get-AgentTools $Id
    $body = @(Get-AgentBodyLines @(Get-Content -LiteralPath $Src))
    $out = New-Object System.Collections.Generic.List[string]
    [void]$out.Add('---')
    [void]$out.Add("description: $desc")
    [void]$out.Add("tools: $tools")
    [void]$out.Add('---')
    [void]$out.Add($Marker)
    foreach ($l in $body) { [void]$out.Add($l) }
    [System.IO.File]::WriteAllText($Dst, (($out -join "`n") + "`n"))
    Write-Host "  installed $Dst"
    return $true
}

$AgentsDir = Join-Path $RepoRoot 'agents'
$installOpenCodeAgents = -not $skipOpenCodeRules
$installCopilotAgents = -not $skipCopilotRules
if ($Scope -eq 'global') {
    $openCodeAgentsDir = Join-Path $HOME '.config/opencode/agents'
    $copilotAgentsDir = Join-Path $HOME '.copilot/agents'
}
else {
    $openCodeAgentsDir = Join-Path $LocalTarget '.opencode/agents'
    $copilotAgentsDir = Join-Path $LocalTarget '.github/agents'
}

$agentCount = 0
if ($installOpenCodeAgents -or $installCopilotAgents) {
    if (-not (Test-Path -LiteralPath $AgentsDir -PathType Container)) {
        throw "agents directory not found: $AgentsDir (run the script from inside the repo)"
    }
    if ($Clean) { Write-Host "Cleaning managed agents" }
    else { Write-Host "Installing agents" }
    $agentFiles = @(Get-ChildItem -LiteralPath $AgentsDir -Filter '*.md' -File)
    if ((-not $Clean) -and ($agentFiles.Count -eq 0)) {
        throw "no agents found in $AgentsDir"
    }
    foreach ($f in $agentFiles) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if ($installOpenCodeAgents) {
            $dst = Join-Path $openCodeAgentsDir "$id.md"
            if ($Clean) {
                Remove-ManagedAgentFile $dst
            }
            elseif ((Test-Path -LiteralPath $dst) -and (Test-IsLink $dst)) {
                if ($Mode -eq 'link') {
                    Write-Host "  linked   $dst (already current)"
                    $agentCount++
                }
                else {
                    Remove-ManagedAgentFile $dst
                    if (Install-OpenCodeAgentCopy $f.FullName $dst) { $agentCount++ }
                }
            }
            elseif ($Mode -eq 'link') {
                Remove-ManagedAgentFile $dst
                if ((Test-Path -LiteralPath $dst) -or (Get-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue)) {
                    Write-Warning "skipped $dst - exists and was not created by this script"
                }
                else {
                    $parent = Split-Path -Parent $dst
                    if (-not (Test-Path -LiteralPath $parent)) {
                        New-Item -ItemType Directory -Path $parent -Force | Out-Null
                    }
                    $linked = $false
                    try {
                        New-Item -ItemType SymbolicLink -Path $dst -Target $f.FullName -ErrorAction Stop | Out-Null
                        Write-Host "  linked   $dst -> $($f.FullName)"
                        $linked = $true
                    }
                    catch {
                        Write-Warning "symlink failed for $dst ($($_.Exception.Message)); falling back to copy"
                        $linked = Install-OpenCodeAgentCopy $f.FullName $dst
                    }
                    if ($linked) { $agentCount++ }
                }
            }
            else {
                if (Install-OpenCodeAgentCopy $f.FullName $dst) { $agentCount++ }
            }
        }
        if ($installCopilotAgents) {
            $dst = Join-Path $copilotAgentsDir "$id.agent.md"
            if ($Clean) {
                Remove-ManagedAgentFile $dst
            }
            else {
                if (Install-CopilotAgentCopy $f.FullName $dst $id) { $agentCount++ }
            }
        }
    }
    if ($Clean) {
        $cleanDirs = @()
        if ($installOpenCodeAgents) { $cleanDirs += $openCodeAgentsDir }
        if ($installCopilotAgents) { $cleanDirs += $copilotAgentsDir }
        foreach ($d in $cleanDirs) {
            if ((Test-Path -LiteralPath $d -PathType Container) -and @(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) {
                Remove-Item -LiteralPath $d -Force
                Write-Host "Removed empty $d"
            }
        }
        Write-Host "Done: cleaned managed agents"
    }
    else {
        Write-Host "Done: $agentCount agent files installed ($Mode)."
    }
}
