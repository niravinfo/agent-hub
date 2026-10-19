#!/usr/bin/env pwsh
#
# Zero-dependency tests for lib/tui.ps1.
#
#   pwsh -NoProfile -File tests/run.ps1
#
# A failed assertion is recorded and the run continues, so one test reports
# every problem it found before the suite moves on.  Key handling needs a real
# terminal, so those cases drive a script under script(1); they skip cleanly
# where script(1) is absent or lacks util-linux's -qec flags.  Nothing here
# writes inside the repo: drivers and captures live in a temp directory.

$ErrorActionPreference = 'Stop'

# Native stderr carries the pty tools' own diagnostics; it is data here, not an
# error.
if (Get-Variable -Name 'PSNativeCommandUseErrorActionPreference' -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LibPath = Join-Path $RepoRoot 'lib/tui.ps1'
$TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-hub-tui-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TmpRoot -Force | Out-Null

# A blocked reader must fail the suite rather than stall it; script(1) has no
# timeout of its own, so cap the pty run from the outside.
$PtyTimeout = if ($env:PTY_TIMEOUT) { [int]$env:PTY_TIMEOUT } else { 20 }
# The keystrokes are held back: a fresh pty starts in canonical mode, and its
# line discipline eats DEL and Ctrl-U before the driver's first read switches
# it to raw.  A driver reaches that read in about 0.6s here; 1s was seen to
# lose keys on a loaded machine, so the default keeps a margin.
$PtySettle = if ($env:PTY_SETTLE) { [int]$env:PTY_SETTLE } else { 2 }
# Child-process tests re-enter this host's own interpreter, which is not always
# named pwsh: 5.1 ships as powershell.exe.
$HostExe = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell' } else { 'pwsh' }

$script:Skipped = 0
$script:TestFailed = $false
$script:TestSkipped = $false
$script:DriverCount = 0
$script:PtyOutput = ''
$script:PtyExit = 0

# Guarded so a missing library reports one failure per test instead of taking
# the whole suite down before it can say what is wrong.
if (Test-Path -LiteralPath $LibPath) { . $LibPath }

function Write-Fail {
    param([string]$Message)
    $script:TestFailed = $true
    Write-Host "    $Message"
}

# A test that cannot run here records a skip instead of a pass, so a missing
# pty tool never looks like a verified assertion.
function Write-Skip {
    param([string]$Note)
    $script:TestSkipped = $true
    if ($Note) { Write-Host "    $Note" }
}

function Assert-Equal {
    param([string]$Label, [object]$Want, [object]$Got)
    if ($Want -ceq $Got) { return }
    Write-Fail "${Label}: want [$Want] got [$Got]"
}

function Assert-Contains {
    param([string]$Label, [string]$Haystack, [string]$Needle)
    if ($null -ne $Haystack -and $Haystack.Contains($Needle)) { return }
    Write-Fail "${Label}: [$Needle] not in output: $(Get-Snippet $Haystack)"
}

# An escape sequence is never legitimate here.  This can only be asserted over
# redirected output: a console-attached pwsh wraps every line it writes in SGR
# resets of its own, whatever the library does.
function Assert-NoAnsi {
    param([string]$Label, [string]$Text)
    if ($null -eq $Text) { return }
    if ($Text.Contains([string][char]27 + '[')) { Write-Fail "${Label}: ANSI escape sequence in output" }
}

# One readable line for a failure message: controls and escapes removed.
function Get-Snippet {
    param([string]$Text)
    if (-not $Text) { return '' }
    $clean = ($Text -replace '[^\x20-\x7E\n]', '.') -replace '\n', '|'
    if ($clean.Length -gt 200) { $clean = $clean.Substring(0, 200) }
    return $clean
}

# Write a driver under the temp dir and return its path.  Every driver needs the
# library and a TERM that exercises the ANSI redraw path, so those are
# prepended; -Body is the test's own script.
function New-Driver {
    param([string]$Body)
    $script:DriverCount = $script:DriverCount + 1
    $path = Join-Path $TmpRoot ('driver-{0}.ps1' -f $script:DriverCount)
    $lib = $LibPath.Replace("'", "''")
    $lines = @(
        '$env:TERM = ''xterm-256color'''
        ". '$lib'"
        $Body
    )
    Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
    return $path
}

# Feed keystrokes to a driver through a pty and return the run as a hash.
# Skip is $true -- with a Note -- where the pty tools are unusable.  -Keys is a
# printf format: escapes are interpreted, so it may not contain a quote.
function Invoke-Pty {
    param(
        [Parameter(Mandatory = $true)][string]$Driver,
        [string]$Keys = '',
        [int]$Timeout = 0
    )
    $result = @{ Output = ''; ExitCode = 0; Skip = $false; Note = '' }

    if (-not (Get-Command -Name 'script' -ErrorAction SilentlyContinue)) {
        $result.Skip = $true
        $result.Note = 'SKIP: pty tests (script(1) not found)'
        return $result
    }
    if (-not (Get-Command -Name 'bash' -ErrorAction SilentlyContinue)) {
        $result.Skip = $true
        $result.Note = 'SKIP: pty tests (bash not found)'
        return $result
    }
    # Some implementations (macOS, BSD) reject util-linux's -qec.
    $probe = & bash -c "printf '' | script -qec 'printf PTYOK' /dev/null 2>&1" | Out-String
    if ($LASTEXITCODE -ne 0 -or $probe -notmatch 'PTYOK') {
        $result.Skip = $true
        $result.Note = 'SKIP: pty tests (script(1) has no -qec)'
        return $result
    }

    $cap = ''
    if ($Timeout -gt 0 -and (Get-Command -Name 'timeout' -ErrorAction SilentlyContinue)) {
        $cap = "timeout $Timeout "
    }
    # The feeder's stderr is dropped: a driver that has already exited closes
    # the pty, which makes printf complain about a broken pipe.  That is a
    # symptom of the run, never the failure the test is reporting.
    $feed = ''
    if ($Keys) { $feed = "{ sleep $PtySettle; printf '%b' '$Keys'; } 2>/dev/null | " }

    # TERM has to name a terminal the .NET console reader can resolve, whatever
    # the caller's environment says.
    $savedTerm = $env:TERM
    $env:TERM = 'xterm-256color'
    try {
        $result.Output = & bash -c "${feed}${cap}script -qec 'pwsh -NoProfile -File `"$Driver`"' /dev/null 2>&1" | Out-String
    }
    finally {
        $env:TERM = $savedTerm
    }
    $result.ExitCode = $LASTEXITCODE
    return $result
}

# Run a driver and stash its output in $PtyOutput / $PtyExit; $false means the
# test skipped.  A run killed by the pty cap fails here, so no test can mistake
# a stall for a passing assertion.
function Start-PtyTest {
    param([string]$Driver, [string]$Keys = '')
    $r = Invoke-Pty -Driver $Driver -Keys $Keys -Timeout $PtyTimeout
    if ($r.Skip) {
        Write-Skip $r.Note
        return $false
    }
    $script:PtyOutput = $r.Output
    $script:PtyExit = $r.ExitCode
    if ($r.ExitCode -eq 124) { Write-Fail "pty run exceeded ${PtyTimeout}s" }
    return $true
}

# pwsh's own host wraps every Write-Host / Write-Output line in SGR resets
# whenever a console is attached, and the .NET reader emits keypad-mode
# sequences; both are noise in a captured typescript.
function Remove-Ansi {
    param([string]$Text)
    if (-not $Text) { return '' }
    return ($Text -replace '\x1b(\[[0-9;?]*[A-Za-z]|[=>])', '')
}

# The last `RESULT=...` line a driver printed, with the pty's CR and the host's
# escapes stripped.  This is what lets a test assert an exact value rather than
# a substring.
function Get-PtyResult {
    param([string]$Output)
    if (-not $Output) { return '' }
    $lines = @((Remove-Ansi $Output) -replace "`r", '' -split "`n" |
        Where-Object { $_.Contains('RESULT=') })
    if ($lines.Count -eq 0) { return '' }
    return $lines[$lines.Count - 1].Trim()
}

function Test-GlyphAsciiFallback {
    # TERM=dumb is the documented ASCII trigger.
    $savedTerm = $env:TERM
    $env:TERM = 'dumb'
    try { Initialize-Tui; Restore-Tui }
    finally { $env:TERM = $savedTerm }

    Assert-Equal -Label 'TERM=dumb leaves ANSI off' -Want 0 -Got $TuiAnsi
    Assert-Equal -Label 'TERM=dumb leaves glyphs ASCII' -Want 0 -Got $TuiUnicode
    Assert-Equal -Label 'a pointer glyph is set' -Want $true -Got ($TuiPointer.Length -gt 0)

    $bad = 0
    foreach ($ch in $TuiPointer.ToCharArray()) {
        if ([int]$ch -gt 0x7F) { $bad = $bad + 1 }
    }
    Assert-Equal -Label 'pointer has no code point above 0x7F' -Want 0 -Got $bad
}

# The glyphs are built from code points precisely so a legacy 5.1 console never
# sees mojibake from a UTF-8 literal or a BOM.
function Test-GlyphsAreAsciiSource {
    if (-not (Test-Path -LiteralPath $LibPath)) {
        Write-Fail "lib/tui.ps1 is missing ($LibPath)"
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($LibPath)
    $bad = 0
    foreach ($b in $bytes) {
        if ($b -gt 0x7F) { $bad = $bad + 1 }
    }
    Assert-Equal -Label 'no byte above 0x7F in lib/tui.ps1' -Want 0 -Got $bad
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Fail 'lib/tui.ps1 starts with a UTF-8 BOM'
    }
}

function Test-MenuDownEnterSelectsSecond {
    $body = @'
$i = Show-TuiMenu -Title 'Pick' -Options @('Alpha', 'Beta') -Default 0
Write-Output "RESULT=$i"
'@
    if (-not (Start-PtyTest -Driver (New-Driver -Body $body) -Keys '\x1b[B\n')) { return }
    Assert-Equal -Label 'the menu aborts cleanly' -Want 0 -Got $PtyExit
    Assert-Contains -Label 'down then enter selects index 1' -Haystack $PtyOutput -Needle 'RESULT=1'
}

function Test-MultiRequiresOne {
    $body = @'
$v = Show-TuiMulti -Title 'Pick' -Options @('A', 'B') -Default @($false, $false)
$bits = ''
foreach ($on in $v) { if ($on) { $bits = $bits + '1' } else { $bits = $bits + '0' } }
Write-Output "RESULT=$bits"
'@
    if (-not (Start-PtyTest -Driver (New-Driver -Body $body) -Keys '\n')) { return }
    # Enter is refused while every box is off; the closed pty then aborts the
    # widget, so no result line may appear and the run may not stall.
    if ($PtyOutput -match 'RESULT=') { Write-Fail "empty selection advanced: $(Get-Snippet $PtyOutput)" }
    Assert-Equal -Label 'the closed pty aborted instead of hanging' -Want 130 -Got $PtyExit
}

function Test-InputBackspace {
    $body = @'
$s = Read-TuiInput -Title 'Path' -Default '/base'
Write-Output "RESULT=$s"
'@
    if (-not (Start-PtyTest -Driver (New-Driver -Body $body) -Keys 'x\x7f\x7f\n')) { return }
    # '/base' + x is '/basex'; two backspaces leave '/bas', pinned exactly so a
    # lost delete fails.
    Assert-Equal -Label 'typed char then two deletes' -Want 'RESULT=/bas' -Got (Get-PtyResult $PtyOutput)
}

# A run whose output is not a console must stay escape-free, whatever TERM says.
function Test-NoAnsiWhenRedirected {
    $body = @'
Initialize-Tui
Write-TuiBanner -Title 'Setup'
Write-Output "RESULT=ANSI=$TuiAnsi"
Restore-Tui
'@
    $out = & $HostExe -NoProfile -File (New-Driver -Body $body) 2>&1 | Out-String
    Assert-Equal -Label 'a redirected run leaves ANSI off' -Want 'RESULT=ANSI=0' -Got (Get-PtyResult $out)
    Assert-NoAnsi -Label 'a redirected banner' -Text $out
}

# The complement of the fallback test: on a console that can render the glyphs,
# the pointer must actually be one of them.
function Test-GlyphUnicodeUnderPty {
    $body = @'
Initialize-Tui
$point = ''
foreach ($ch in $TuiPointer.ToCharArray()) { $point = $point + ('{0:X4} ' -f [int]$ch) }
Write-Output "RESULT=ANSI=$TuiAnsi UNI=$TuiUnicode P=$point"
Restore-Tui
'@
    if (-not (Start-PtyTest -Driver (New-Driver -Body $body))) { return }
    # A driver that could not load the library reports no usable capability
    # values, which is a failure here rather than a reason to skip.
    if ($PtyOutput -notmatch 'RESULT=ANSI=[01] ') {
        Write-Fail "the driver produced no capability result: $(Get-Snippet $PtyOutput)"
        return
    }
    if ($PtyOutput -notmatch 'ANSI=1') {
        Write-Skip 'SKIP: glyph test (console has no VT support)'
        return
    }
    if ($PtyOutput -notmatch 'UNI=1') {
        Write-Skip 'SKIP: glyph test (console encoding cannot render the glyphs)'
        return
    }
    Assert-Contains -Label 'the unicode pointer is the arrow glyph' -Haystack $PtyOutput -Needle 'P=276F '
}

function Invoke-Main {
    $names = @(Get-ChildItem -Path function: |
        Where-Object { $_.Name -like 'Test-*' } |
        ForEach-Object { $_.Name } |
        Sort-Object)
    if ($names.Count -eq 0) {
        Write-Host 'no tests discovered'
        return 1
    }

    $run = 0
    $failed = 0
    foreach ($name in $names) {
        $script:TestFailed = $false
        $script:TestSkipped = $false
        $run = $run + 1
        Write-Host -NoNewline ('{0} ... ' -f $name.Substring(5))
        try { $null = & $name }
        catch { Write-Fail "unhandled error: $(($_.Exception.Message -replace '\s+', ' ').Trim())" }
        if ($script:TestFailed) { Write-Host 'FAIL'; $failed = $failed + 1 }
        elseif ($script:TestSkipped) { Write-Host 'skip'; $script:Skipped = $script:Skipped + 1 }
        else { Write-Host 'ok' }
    }

    Write-Host ''
    Write-Host ('{0} run, {1} failed, {2} skipped' -f $run, $failed, $script:Skipped)
    if ($failed -gt 0) { return 1 }
    return 0
}

$exitCode = 1
try { $exitCode = Invoke-Main }
finally { Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
exit $exitCode
