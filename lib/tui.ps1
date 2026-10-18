# Shared arrow-key / checkbox prompt library for the setup scripts.
#
# Dot-sourced, never executed.  PowerShell 5.1 and 7, no dependencies.
#
# Each widget draws its block with Write-Host and returns the chosen value, so
# callers keep the old `$choice = Read-MenuChoice ...` shape; Read-TuiConfirm
# returns a [bool].  The caller owns the terminal gate -- nothing here prompts
# on its own.
#
# Initialize-Tui decides colour and glyph capability once, and Restore-Tui
# undoes it from a caller's `finally`.

# Glyph and capability state, set before Initialize-Tui runs so a caller can
# read the variables unconditionally.
$script:TuiAnsi = 0
$script:TuiUnicode = 0
$script:TuiBold = ''; $script:TuiDim = ''; $script:TuiCyan = ''
$script:TuiGreen = ''; $script:TuiGrey = ''; $script:TuiYellow = ''; $script:TuiReset = ''
$script:TuiPointer = '>'; $script:TuiRadioOn = '*'; $script:TuiRadioOff = 'o'
$script:TuiRule = '-'; $script:TuiDot = '.'

$script:TuiEsc = [string][char]27
$script:TuiLines = 0      # lines the dynamic block currently occupies
$script:TuiDrawn = 0      # a non-ANSI block is printed once and then left alone
$script:TuiKey = ''
$script:TuiActive = 0
$script:TuiCtrlC = $false

# VT is opt-in on 5.1: escapes written to a legacy console silently vanish.
$script:TuiVtSource = @'
using System;
using System.Runtime.InteropServices;

public static class AgentHubTuiConsole
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
}
'@

# ENABLE_VIRTUAL_TERMINAL_PROCESSING on the standard output handle.  Never
# throws: an unsupported console just keeps the ASCII, escape-free output.
function Enable-TuiVirtualTerminal {
    try {
        if (-not ('AgentHubTuiConsole' -as [type])) {
            Add-Type -TypeDefinition $script:TuiVtSource
        }
        $handle = [AgentHubTuiConsole]::GetStdHandle(-11)
        if ($handle -eq [IntPtr]::Zero) { return $false }
        $mode = [uint32]0
        if (-not [AgentHubTuiConsole]::GetConsoleMode($handle, [ref]$mode)) { return $false }
        return [AgentHubTuiConsole]::SetConsoleMode($handle, $mode -bor 0x0004)
    }
    catch { return $false }
}

# A console whose output encoding cannot round-trip a glyph prints mojibake, so
# the ASCII set is the answer there.
function Get-TuiGlyphRenderable {
    $probe = [string][char]0x276F
    try {
        $encoding = [Console]::OutputEncoding
        $bytes = $encoding.GetBytes($probe)
        if ($bytes.Length -eq 0) { return $false }
        return ($encoding.GetString($bytes) -eq $probe)
    }
    catch { return $false }
}

function Initialize-Tui {
    if ($script:TuiActive -eq 1) { Restore-Tui }

    $ansi = $true
    if ($env:TERM -eq 'dumb') { $ansi = $false }
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { $ansi = $false }
    if ($ansi -and $PSVersionTable.PSVersion.Major -lt 6) {
        $ansi = Enable-TuiVirtualTerminal
    }

    $unicode = $false
    if ($ansi -and (Get-TuiGlyphRenderable)) { $unicode = $true }

    # Reset first: a second Initialize-Tui must not keep capability the console
    # has lost (or never had).
    $script:TuiAnsi = 0
    $script:TuiUnicode = 0
    $script:TuiBold = ''; $script:TuiDim = ''; $script:TuiCyan = ''
    $script:TuiGreen = ''; $script:TuiGrey = ''; $script:TuiYellow = ''; $script:TuiReset = ''
    $script:TuiPointer = '>'; $script:TuiRadioOn = '*'; $script:TuiRadioOff = 'o'
    $script:TuiRule = '-'; $script:TuiDot = '.'
    if ($ansi) {
        $e = $script:TuiEsc
        $script:TuiAnsi = 1
        $script:TuiReset = $e + '[0m'; $script:TuiBold = $e + '[1m'; $script:TuiDim = $e + '[2m'
        $script:TuiCyan = $e + '[36m'; $script:TuiGreen = $e + '[32m'
        $script:TuiYellow = $e + '[33m'; $script:TuiGrey = $e + '[90m'
    }
    if ($unicode) {
        $script:TuiUnicode = 1
        $script:TuiPointer = [string][char]0x276F    # heavy right angle quote
        $script:TuiRadioOn = [string][char]0x25C9    # fisheye
        $script:TuiRadioOff = [string][char]0x25CB   # white circle
        $script:TuiRule = [string][char]0x2500       # light horizontal
        $script:TuiDot = [string][char]0x00B7        # middle dot
    }

    $script:TuiActive = 1
    if ($script:TuiAnsi -eq 1) { Write-Host -NoNewline ($script:TuiEsc + '[?25l') }

    # Ctrl-C has to arrive as a keypress, or the console is left with a hidden
    # cursor and no way to run the restore.
    $script:TuiCtrlC = $false
    if ($ansi) {
        try { [Console]::TreatControlCAsInput = $true; $script:TuiCtrlC = $true }
        catch { $script:TuiCtrlC = $false }
    }
    return
}

function Restore-Tui {
    if ($script:TuiActive -eq 0) { return }
    $script:TuiActive = 0
    try {
        if ($script:TuiAnsi -eq 1) { Write-Host -NoNewline ($script:TuiEsc + '[?25h') }
    }
    finally {
        if ($script:TuiCtrlC) {
            try { [Console]::TreatControlCAsInput = $false } catch { }
            $script:TuiCtrlC = $false
        }
        $script:TuiLines = 0
        $script:TuiDrawn = 0
    }
}

# Every widget starts a fresh block: there is nothing of its own to wipe yet,
# and on a non-ANSI console its block prints exactly once.
function Reset-TuiBlock {
    $script:TuiLines = 0
    $script:TuiDrawn = 0
}

# One keypress, as a token: up/down/left/right/enter/space/backspace/clear/
# interrupt/eof, or the literal character.  A closed input arrives as Ctrl-D,
# and a read that throws means the same thing.
function Read-TuiKey {
    $script:TuiKey = ''
    $info = $null
    try { $info = [Console]::ReadKey($true) }
    catch { $script:TuiKey = 'eof'; return }

    switch ([string]$info.Key) {
        'UpArrow'    { $script:TuiKey = 'up'; return }
        'DownArrow'  { $script:TuiKey = 'down'; return }
        'LeftArrow'  { $script:TuiKey = 'left'; return }
        'RightArrow' { $script:TuiKey = 'right'; return }
        'Enter'      { $script:TuiKey = 'enter'; return }
        'Spacebar'   { $script:TuiKey = 'space'; return }
        'Backspace'  { $script:TuiKey = 'backspace'; return }
        'Escape'     { $script:TuiKey = 'esc'; return }
    }
    switch ([int][char]$info.KeyChar) {
        3  { $script:TuiKey = 'interrupt'; return }   # Ctrl-C
        4  { $script:TuiKey = 'eof'; return }         # Ctrl-D
        21 { $script:TuiKey = 'clear'; return }       # Ctrl-U
    }
    # Unbound keys -- F1-F12 among them -- carry no character; ignoring them
    # keeps a NUL out of a text field.
    if ([int][char]$info.KeyChar -eq 0) { return }
    $script:TuiKey = [string]$info.KeyChar
}

# A single 1-9 selects that option directly; -1 means "not a digit".
function Get-TuiDigit {
    if ($script:TuiKey -match '^[1-9]$') { return ([int]$script:TuiKey) - 1 }
    return -1
}

# Erase the block drawn last time, so the next frame lands on the same lines.
function Write-TuiDraw {
    param([string]$Title, [string[]]$Lines)

    if ($script:TuiAnsi -eq 1) {
        $i = $script:TuiLines
        while ($i -gt 0) {
            Write-Host -NoNewline ($script:TuiEsc + '[1A' + $script:TuiEsc + '[2K')
            $i = $i - 1
        }
    }
    elseif ($script:TuiDrawn -eq 1) { return }

    $n = 0
    if ($Title) {
        Write-Host ($script:TuiBold + $Title + $script:TuiReset)
        $n = 1
    }
    foreach ($line in $Lines) {
        Write-Host $line
        $n = $n + 1
    }
    $script:TuiLines = $n
    $script:TuiDrawn = 1
}

function Write-TuiBanner {
    param([string]$Title)
    Write-Host ''
    Write-Host ($script:TuiBold + $Title + $script:TuiReset)
    Write-Host ($script:TuiDim + (-join ($script:TuiRule * $Title.Length)) + $script:TuiReset)
}

# EOF on the input means the caller has lost its terminal; there is no sane
# selection to hand back, so abort the way an interrupt would.
function Stop-TuiAbort {
    Restore-Tui
    Write-Host ''
    exit 130
}

# Show-TuiMenu -Title T -Options O... -Default N -> 0-based index.
function Show-TuiMenu {
    [OutputType([int])]
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$Default = 0
    )
    Reset-TuiBlock

    $n = $Options.Count
    $cur = 0
    if ($Default -ge 0 -and $Default -lt $n) { $cur = $Default }

    while ($true) {
        $frame = @()
        for ($i = 0; $i -lt $n; $i++) {
            if ($i -eq $cur) {
                $frame += $script:TuiCyan + $script:TuiPointer + $script:TuiReset + ' ' +
                    $script:TuiRadioOn + ' ' + $Options[$i]
            }
            else {
                $frame += '  ' + $script:TuiRadioOff + ' ' + $Options[$i]
            }
        }
        Write-TuiDraw -Title $Title -Lines $frame
        Read-TuiKey
        switch ($script:TuiKey) {
            'up'        { if ($cur -gt 0) { $cur = $cur - 1 } }
            'down'      { if ($cur -lt ($n - 1)) { $cur = $cur + 1 } }
            'enter'     { return [int]$cur }
            'space'     { return [int]$cur }
            'right'     { return [int]$cur }
            'eof'       { Stop-TuiAbort }
            'interrupt' { Stop-TuiAbort }
            default {
                $jump = Get-TuiDigit
                if ($jump -ge 0 -and $jump -lt $n) { $cur = $jump }
            }
        }
    }
}

# Show-TuiMulti -Title T -Options O... -Default B... -> one [bool] per option,
# in order.  Enter is refused while every option is off.
function Show-TuiMulti {
    [OutputType([bool[]])]
    param(
        [string]$Title,
        [string[]]$Options,
        [bool[]]$Default
    )
    Reset-TuiBlock

    $n = $Options.Count
    $sel = @()
    for ($i = 0; $i -lt $n; $i++) {
        $on = $false
        if ($null -ne $Default -and $i -lt $Default.Count) { $on = [bool]$Default[$i] }
        $sel += $on
    }
    $cur = 0
    $hint = ''

    while ($true) {
        $frame = @()
        for ($i = 0; $i -lt $n; $i++) {
            if ($sel[$i]) { $box = '[' + $script:TuiRadioOn + ']' }
            else { $box = '[' + $script:TuiRadioOff + ']' }
            if ($i -eq $cur) {
                $frame += $script:TuiCyan + $script:TuiPointer + $script:TuiReset + ' ' +
                    $box + ' ' + $Options[$i]
            }
            else {
                $frame += '  ' + $box + ' ' + $Options[$i]
            }
        }
        if ($hint) { $frame += $script:TuiYellow + $hint + $script:TuiReset }
        Write-TuiDraw -Title $Title -Lines $frame
        Read-TuiKey
        switch ($script:TuiKey) {
            'up'        { if ($cur -gt 0) { $cur = $cur - 1 } }
            'down'      { if ($cur -lt ($n - 1)) { $cur = $cur + 1 } }
            'space'     {
                if ($sel[$cur]) { $sel[$cur] = $false } else { $sel[$cur] = $true }
                $hint = ''
            }
            'enter'     {
                $any = $false
                foreach ($on in $sel) { if ($on) { $any = $true; break } }
                if ($any) { return ,([bool[]]$sel) }
                $hint = 'Select at least one.'
            }
            'eof'       { Stop-TuiAbort }
            'interrupt' { Stop-TuiAbort }
            default {
                $jump = Get-TuiDigit
                if ($jump -ge 0 -and $jump -lt $n) { $cur = $jump }
            }
        }
    }
}

# Read-TuiInput -Title T -Default D -> the edited string.  The default is the
# starting buffer, so Enter alone returns it unchanged.
function Read-TuiInput {
    [OutputType([string])]
    param(
        [string]$Title,
        [string]$Default = ''
    )
    Reset-TuiBlock

    $buf = $Default
    if ($null -eq $buf) { $buf = '' }

    while ($true) {
        Write-TuiDraw -Title $Title -Lines @(
            $script:TuiCyan + $script:TuiPointer + $script:TuiReset + ' ' + $buf
        )
        Read-TuiKey
        switch ($script:TuiKey) {
            'enter'     { return $buf }
            'backspace' { if ($buf.Length -gt 0) { $buf = $buf.Substring(0, $buf.Length - 1) } }
            'clear'     { $buf = '' }
            'space'     { $buf = $buf + ' ' }
            'eof'       { Stop-TuiAbort }
            'interrupt' { Stop-TuiAbort }
            'up'        { }
            'down'      { }
            'left'      { }
            'right'     { }
            'esc'       { }
            default     { $buf = $buf + $script:TuiKey }
        }
    }
}

# Read-TuiConfirm -Question Q -> $true for yes, $false for no.
function Read-TuiConfirm {
    [OutputType([bool])]
    param([string]$Question)
    Reset-TuiBlock

    while ($true) {
        Write-TuiDraw -Title ($Question + ' [Y/n]') -Lines @()
        Read-TuiKey
        switch ($script:TuiKey) {
            'enter'     { return $true }
            'y'         { return $true }
            'n'         { return $false }
            'eof'       { Stop-TuiAbort }
            'interrupt' { Stop-TuiAbort }
        }
    }
}
