#Requires -Version 5.1
<#
.SYNOPSIS
    Installs keyless remote MCP servers (Context7 + DeepWiki) into user-level configs.

.DESCRIPTION
    OpenCode: merges "mcp" entries into ~/.config/opencode/opencode.json
    Copilot:  merges "mcpServers" entries into ~/.copilot/mcp-config.json
              (portable format, read by Copilot tools and the Agent Host)

    Safe by design: server definitions come from this repo's mcp/ templates,
    existing servers are never overwritten, nothing secret is written (both
    servers work keyless), every touched file is backed up as <file>.bak, and
    a target that is not plain JSON (e.g. JSONC with comments) is left
    untouched with manual instructions. Idempotent: re-running only adds what
    is missing.

.PARAMETER SkipOpencode
    Skip the OpenCode global config.

.PARAMETER SkipCopilot
    Skip the Copilot user config.

.PARAMETER Clean
    Remove only the entries this script manages (same name AND same URL).

.EXAMPLE
    ./setup-mcp.ps1
.EXAMPLE
    ./setup-mcp.ps1 -Clean
#>
[CmdletBinding()]
param(
    [switch]$SkipOpencode,
    [switch]$SkipCopilot,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot

function Read-TemplateJson {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch '^\s*//' }
    return ($lines -join "`n") | ConvertFrom-Json
}

$targets = @(
    @{
        Name     = 'OpenCode'
        Skip     = $SkipOpencode
        File     = Join-Path $HOME '.config/opencode/opencode.json'
        Template = Join-Path $RepoRoot 'mcp/opencode.jsonc'
        Section  = 'mcp'
        Fresh    = '{ "$schema": "https://opencode.ai/config.json", "mcp": {} }'
    },
    @{
        Name     = 'Copilot'
        Skip     = $SkipCopilot
        File     = Join-Path $HOME '.copilot/mcp-config.json'
        Template = Join-Path $RepoRoot 'mcp/copilot-user-mcp-config.json'
        Section  = 'mcpServers'
        Fresh    = '{ "mcpServers": {} }'
    }
)

foreach ($t in $targets) {
    if ($t.Skip) { continue }

    try {
        $desired = (Read-TemplateJson $t.Template).$($t.Section)
    }
    catch {
        Write-Host "[$($t.Name)] error: cannot read template: $($_.Exception.Message)"
        continue
    }

    $existed = Test-Path -LiteralPath $t.File
    if ($existed) {
        try {
            $current = Get-Content -LiteralPath $t.File -Raw | ConvertFrom-Json
        }
        catch {
            Write-Host "[$($t.Name)] skipped $($t.File): not plain JSON (JSONC with comments?). Add the `"$($t.Section)`" block from $($t.Template) manually. File left untouched."
            continue
        }
    }
    else {
        $current = $t.Fresh | ConvertFrom-Json
    }

    if (-not ($current -is [pscustomobject])) {
        Write-Host "[$($t.Name)] skipped $($t.File): top level is not an object. Left untouched."
        continue
    }
    if (-not $current.PSObject.Properties[$t.Section]) {
        $current | Add-Member -NotePropertyName $t.Section -NotePropertyValue (New-Object psobject)
    }
    $section = $current.$($t.Section)

    if ($Clean) {
        $removed = @()
        foreach ($p in @($desired.PSObject.Properties)) {
            $have = $section.PSObject.Properties[$p.Name]
            if ($have -and $have.Value.url -eq $p.Value.url) {
                $section.PSObject.Properties.Remove($p.Name)
                $removed += $p.Name
            }
        }
        if ($removed.Count -eq 0) {
            Write-Host "[$($t.Name)] nothing managed to remove in $($t.File)"
            continue
        }
        Copy-Item -LiteralPath $t.File -Destination ($t.File + '.bak') -Force
        $current | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $t.File -Encoding UTF8
        Write-Host "[$($t.Name)] removed $($removed -join ', ') from $($t.File) (backup: $($t.File).bak)"
        continue
    }

    $added = @()
    $present = @()
    $skipped = @()
    foreach ($p in @($desired.PSObject.Properties)) {
        $have = $section.PSObject.Properties[$p.Name]
        if (-not $have) {
            $section | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
            $added += $p.Name
        }
        elseif ($have.Value.url -eq $p.Value.url -and $have.Value.type -eq $p.Value.type) {
            $present += $p.Name
        }
        else {
            $skipped += $p.Name
        }
    }
    if ($skipped.Count -gt 0) {
        Write-Host "[$($t.Name)] skipped $($skipped -join ', '): name(s) already used by your own server(s) pointing elsewhere. Left untouched."
    }
    if ($added.Count -eq 0) {
        if ($present.Count -gt 0) {
            Write-Host "[$($t.Name)] $($present -join ', ') already present in $($t.File)"
        }
        elseif ($skipped.Count -eq 0) {
            Write-Host "[$($t.Name)] nothing to do"
        }
        continue
    }
    if ($existed) {
        Copy-Item -LiteralPath $t.File -Destination ($t.File + '.bak') -Force
        Write-Host "[$($t.Name)] backup: $($t.File).bak"
    }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $t.File) -Force | Out-Null
    }
    $current | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $t.File -Encoding UTF8
    Write-Host "[$($t.Name)] added $($added -join ', ') to $($t.File)"
}
