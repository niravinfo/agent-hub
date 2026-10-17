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

    Interactive by default: a bare run asks, in order:
      1) where - user level (global) or project level (local)
      2) which application - OpenCode, Copilot, or both
      3) which servers - comma separated numbers (e.g. 1,2)
      then shows what it will write and asks for confirmation.
    Press Enter to accept the bracketed default at any step. Prompts appear
    only on a real console; pipes and CI fall back to the defaults silently.
    Any flag skips the questions entirely (non-interactive, for scripting).

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

function Read-TemplateJson {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path | Where-Object { $_ -notmatch '^\s*//' }
    return ($lines -join "`n") | ConvertFrom-Json
}

function ConvertTo-ServerList {
    param([string]$Raw)
    # NB: PowerShell variables are case-insensitive - a local "$raw" would
    # clobber the "$Raw" parameter and make this always return $null.
    $text = ''
    if ($Raw) { $text = [string]$Raw }
    $text = $text.Trim().ToLowerInvariant()
    if (-not $text) { return $null }
    if ($text -in @('all', 'both', '*')) { return ,@('context7', 'deepwiki') }
    $map = @{ '1' = 'context7'; '2' = 'deepwiki'; 'context7' = 'context7'; 'deepwiki' = 'deepwiki' }
    $out = @()
    foreach ($p in ($text -replace '\s+', ',') -split ',') {
        $p = $p.Trim()
        if (-not $p) { continue }
        if ($p -in @('1-2', '2-1')) {
            foreach ($n in @('context7', 'deepwiki')) { if ($out -notcontains $n) { $out += $n } }
            continue
        }
        if ($map.ContainsKey($p)) {
            if ($out -notcontains $map[$p]) { $out += $map[$p] }
            continue
        }
        return $null
    }
    if ($out.Count -eq 0) { return $null }
    return ,@($out)
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
# is a test hook: it forces the prompts so piped answers can drive them.
$interactive = -not ($Defaults -or $SkipOpencode -or $SkipCopilot -or $Clean)
if ($interactive) {
    try { $redirected = [Console]::IsInputRedirected } catch { $redirected = $true }
    if ($redirected -and $env:MCP_ASSUME_TTY -ne '1') { $interactive = $false }
}

$selectedKeys = @()
$selectedServers = @()

if ($interactive) {
    function Read-Choice {
        param([string]$Prompt, [string]$Default, [scriptblock]$Validate)
        while ($true) {
            $answer = Read-Host "$Prompt [$Default]"
            if ($null -eq $answer) {
                Write-Host ''
                Write-Warning 'no input available (EOF) - aborting. Use -Defaults for a non-interactive install.'
                exit 1
            }
            $answer = $answer.Trim()
            if (-not $answer) { $answer = $Default }
            $result = & $Validate $answer
            if ($null -ne $result) { return $result }
            Write-Warning "invalid selection: '$answer' - try again"
        }
    }

    Write-Host 'MCP server installer - Context7 + DeepWiki'
    Write-Host ''
    Write-Host 'Step 1/3 - Where do you want to install?'
    Write-Host '  1) User level (global)   - available in every project'
    Write-Host '  2) Project level (local) - this project only'
    $scope = Read-Choice -Prompt 'Select 1 or 2' -Default '1' -Validate {
        param($a)
        if ($a -in @('1', '2')) { $a } else { $null }
    }

    Write-Host ''
    Write-Host 'Step 2/3 - Which application?'
    Write-Host '  1) OpenCode'
    Write-Host '  2) Copilot'
    Write-Host '  3) Both'
    $app = Read-Choice -Prompt 'Select 1, 2 or 3' -Default '3' -Validate {
        param($a)
        if ($a -in @('1', '2', '3')) { $a } else { $null }
    }

    Write-Host ''
    Write-Host 'Step 3/3 - Which servers do you want to add?'
    Write-Host '  1) context7 - up-to-date library docs (keyless)'
    Write-Host '  2) deepwiki - public GitHub repo Q&A (keyless)'
    $servers = Read-Choice -Prompt 'Select comma separated values, e.g. 1,2' -Default '1,2' -Validate {
        param($a)
        ConvertTo-ServerList $a
    }

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
    Write-Host ''
    Write-Host 'Ready to install:'
    foreach ($t in $targets) {
        Write-Host ('  - {0,-36} {1}' -f $t.Name, $t.File)
    }
    Write-Host ('Servers: ' + ($selectedServers -join ', '))
    while ($true) {
        $proceed = Read-Host 'Write these files? [Y/n]'
        if ($proceed -match '^[Yy]([Ee][Ss])?$') { break }
        if ($proceed -match '^[Nn]([Oo])?$') {
            Write-Host 'Aborted - nothing was changed.'
            exit 0
        }
        Write-Warning 'please answer y or n'
    }
    Write-Host ''
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
