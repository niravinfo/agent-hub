#Requires -Version 5.1
<#
.SYNOPSIS
    Installs keyless remote MCP servers (Context7 + DeepWiki).

.DESCRIPTION
    OpenCode : user level  ~/.config/opencode/opencode.json (every project)
               project level ./opencode.json (this project)
    Copilot  : user level  ~/.copilot/mcp-config.json (portable format, read
               by Copilot tools and the Agent Host)
    VS Code  : project level ./.vscode/mcp.json (also read by Copilot)

    Interactive by default: on a real console a bare run drives an arrow-key
    wizard - where (user or project level), which application (OpenCode and/or
    Copilot checkboxes; at least one), and which servers (context7 and/or
    deepwiki checkboxes; at least one) - then shows what it will write and asks
    for confirmation. Prompts appear only on a real console; pipes and CI fall
    back to the defaults silently. Any flag skips the questions entirely
    (non-interactive, for scripting).

    Safe by design: server definitions come from this repo's mcp/ templates,
    existing servers are never overwritten, nothing secret is written (both
    servers work keyless), every touched file is backed up as <file>.bak, and
    a target that is not plain JSON (e.g. JSONC with comments) is left
    untouched with manual instructions. Idempotent: re-running only adds
    what is missing.

.PARAMETER Defaults
    Non-interactive: install every server at user level (the old bare-run
    behavior).

.PARAMETER SkipOpencode
    Skip the OpenCode global config.

.PARAMETER SkipCopilot
    Skip the Copilot user config.

.PARAMETER Clean
    Remove only the entries this script manages (same name AND same URL) from
    the user-level configs.

.EXAMPLE
    ./setup-mcp.ps1
.EXAMPLE
    ./setup-mcp.ps1 -Defaults
.EXAMPLE
    ./setup-mcp.ps1 -Clean
#>
[CmdletBinding()]
param(
    [switch]$Defaults,
    [switch]$SkipOpencode,
    [switch]$SkipCopilot,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot

# The interactive wizard is the shared, dependency-free arrow-key layer; it
# draws with Write-Host and returns the chosen value.
. (Join-Path $PSScriptRoot 'lib/tui.ps1')

function Read-TemplateJson {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch '^\s*//' }
    return ($lines -join "`n") | ConvertFrom-Json
}

$opencodeFresh = '{ "$schema": "https://opencode.ai/config.json", "mcp": {} }'
$allTargets = @(
    @{
        Key      = 'opencode'
        Name     = 'OpenCode (user level)'
        File     = Join-Path $HOME '.config/opencode/opencode.json'
        Template = Join-Path $RepoRoot 'mcp/opencode.jsonc'
        Section  = 'mcp'
        Fresh    = $opencodeFresh
    },
    @{
        Key      = 'opencode-local'
        Name     = 'OpenCode (project level)'
        File     = Join-Path (Get-Location).Path 'opencode.json'
        Template = Join-Path $RepoRoot 'mcp/opencode.jsonc'
        Section  = 'mcp'
        Fresh    = $opencodeFresh
    },
    @{
        Key      = 'copilot'
        Name     = 'Copilot (user level)'
        File     = Join-Path $HOME '.copilot/mcp-config.json'
        Template = Join-Path $RepoRoot 'mcp/copilot-user-mcp-config.json'
        Section  = 'mcpServers'
        Fresh    = '{ "mcpServers": {} }'
    },
    @{
        Key      = 'vscode-local'
        Name     = 'VS Code / Copilot (project level)'
        File     = Join-Path (Get-Location).Path '.vscode/mcp.json'
        Template = Join-Path $RepoRoot 'mcp/vscode-workspace-mcp.json'
        Section  = 'servers'
        Fresh    = '{ "servers": {} }'
    }
)

# Interactive only when run bare on a real console. Any flag (or a redirected
# stdin, i.e. pipes/CI) keeps the non-interactive defaults. MCP_ASSUME_TTY=1
# is a test hook: it forces the prompts, but the widgets read raw keys, so a
# test has to drive them through a pseudo-terminal rather than piped lines.
$interactive = -not ($Defaults -or $SkipOpencode -or $SkipCopilot -or $Clean)
if ($interactive) {
    try { $redirected = [Console]::IsInputRedirected } catch { $redirected = $true }
    if ($redirected -and $env:MCP_ASSUME_TTY -ne '1') { $interactive = $false }
}

$selectedKeys = @()
$selectedServers = @()

if ($interactive) {
    Initialize-Tui
    try {
        Write-Host 'MCP server installer - Context7 + DeepWiki'
        Write-Host ''

        $scope = [string](1 + (Show-TuiMenu -Title 'Step 1/3 - Where do you want to install?' -Options @(
            'User level (global)   - available in every project'
            'Project level (local) - this project only'
        ) -Default 0))

        # Checkboxes, not a one-of-three menu: the widget refuses an all-off
        # answer, so the pair maps back onto the old 1/2/3 application codes.
        $apps = Show-TuiMulti -Title 'Step 2/3 - Which application?' -Options @('OpenCode', 'Copilot') -Default @($true, $true)
        $app = if ($apps[0] -and $apps[1]) { '3' } elseif ($apps[0]) { '1' } else { '2' }

        $picks = Show-TuiMulti -Title 'Step 3/3 - Which servers do you want to add?' -Options @(
            'context7 - up-to-date library docs (keyless)'
            'deepwiki - public GitHub repo Q&A (keyless)'
        ) -Default @($true, $true)
        $servers = @()
        if ($picks[0]) { $servers += 'context7' }
        if ($picks[1]) { $servers += 'deepwiki' }

        switch ("$scope`:$app") {
            '1:1' { $selectedKeys = @('opencode') }
            '1:2' { $selectedKeys = @('copilot') }
            '1:3' { $selectedKeys = @('opencode', 'copilot') }
            '2:1' { $selectedKeys = @('opencode-local') }
            '2:2' { $selectedKeys = @('vscode-local') }
            '2:3' { $selectedKeys = @('opencode-local', 'vscode-local') }
            default { throw "internal error: scope=$scope app=$app" }
        }
        $selectedServers = $servers

        $targets = @($allTargets | Where-Object { $selectedKeys -contains $_.Key })
        Write-TuiBanner -Title 'Ready to install:'
        foreach ($t in $targets) {
            Write-Host ('  - {0,-36} {1}' -f $t.Name, $t.File)
        }
        Write-Host ('Servers: ' + ($selectedServers -join ', '))
        if (-not (Read-TuiConfirm -Question 'Write these files?')) {
            Write-Host 'Aborted - nothing was changed.'
            exit 0
        }
        Write-Host ''
    }
    finally { Restore-Tui }
}
else {
    if (-not $SkipOpencode) { $selectedKeys += 'opencode' }
    if (-not $SkipCopilot) { $selectedKeys += 'copilot' }
}

foreach ($t in @($allTargets | Where-Object { $selectedKeys -contains $_.Key })) {
    try {
        $desiredAll = (Read-TemplateJson $t.Template).$($t.Section)
    }
    catch {
        Write-Host "[$($t.Name)] error: cannot read template: $($_.Exception.Message)"
        continue
    }

    $desired = $desiredAll
    if ($selectedServers.Count -gt 0) {
        $filtered = New-Object psobject
        foreach ($p in @($desiredAll.PSObject.Properties)) {
            if ($selectedServers -contains $p.Name) {
                $filtered | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
            }
        }
        $desired = $filtered
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
