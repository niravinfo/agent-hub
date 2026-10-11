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

.PARAMETER Scope
    global (default) - ~/.agents/skills, all projects for this user
    local            - .agents/skills inside this repo

.PARAMETER Mode
    copy (default) - copy skill directories
    link           - directory junction per skill

.PARAMETER Clean
    Unlink / remove the entries this script manages from the target.

.EXAMPLE
    ./setup.ps1
.EXAMPLE
    ./setup.ps1 -Mode link
.EXAMPLE
    ./setup.ps1 -Scope local -Mode link
.EXAMPLE
    ./setup.ps1 -Clean
#>
[CmdletBinding()]
param(
    [ValidateSet('global', 'local')]
    [string]$Scope = 'global',

    [ValidateSet('copy', 'link')]
    [string]$Mode = 'copy',

    [switch]$Clean
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
