# Shared arrow-key / checkbox prompt library for the setup scripts.
#
# Sourced, never executed.  bash 3.2+ (macOS stock), no external dependencies.
#
# Each widget draws its block on stderr and writes only the chosen value to
# stdout, so callers keep the old `choice="$(menu ...)"` shape; tui_confirm
# reports through its exit status instead of a captured string.  The caller
# owns the terminal gate -- nothing here prompts on its own.
#
# tui_init decides colour and glyph capability once, and restores the terminal
# on EXIT/INT/TERM.

# Glyph and capability state, set before tui_init runs so a `set -u` caller can
# read the variables unconditionally.
TUI_ANSI=0
TUI_UNICODE=0
TUI_BOLD=""; TUI_DIM=""; TUI_CYAN=""; TUI_GREEN=""; TUI_GREY=""; TUI_YELLOW=""; TUI_RESET=""
TUI_POINTER=">"; TUI_RADIO_ON="*"; TUI_RADIO_OFF="o"; TUI_RULE="-"; TUI_DOT="."

_TUI_LINES=0     # lines the dynamic block currently occupies
_TUI_DRAWN=0     # a non-ANSI block is printed once and then left alone
_TUI_KEY=""
_TUI_STTY=""
_TUI_SAVED=0
_TUI_ACTIVE=0
_TUI_TRAPPED=0

# A UTF-8 codeset is what decides whether the glyphs are safe to print; the
# language part of the locale is irrelevant.
_tui_utf8_locale() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *[Uu][Tt][Ff]*) return 0 ;;
    esac
    return 1
}

# Put the tty in the mode the key reader wants: no echo, and one byte per read
# rather than a whole line.
_tui_raw() {
    if [[ $_TUI_SAVED == 1 ]]; then
        stty -echo -icanon min 1 time 0 2>/dev/null || true
    fi
    return 0
}

tui_init() {
    if [[ $_TUI_ACTIVE == 1 ]]; then tui_cleanup; fi

    TUI_ANSI=1
    if [[ "${TERM:-dumb}" == "dumb" || ! -t 2 ]]; then TUI_ANSI=0; fi
    TUI_UNICODE=0
    if [[ $TUI_ANSI == 1 ]] && _tui_utf8_locale; then TUI_UNICODE=1; fi

    # Reset first: a second tui_init must not keep capability the terminal has
    # lost (or never had).
    TUI_RESET=""; TUI_BOLD=""; TUI_DIM=""; TUI_CYAN=""; TUI_GREEN=""; TUI_YELLOW=""; TUI_GREY=""
    TUI_POINTER=">"; TUI_RADIO_ON="*"; TUI_RADIO_OFF="o"; TUI_RULE="-"; TUI_DOT="."
    if [[ $TUI_ANSI == 1 ]]; then
        TUI_RESET=$'\033[0m'; TUI_BOLD=$'\033[1m'; TUI_DIM=$'\033[2m'
        TUI_CYAN=$'\033[36m'; TUI_GREEN=$'\033[32m'; TUI_YELLOW=$'\033[33m'
        TUI_GREY=$'\033[90m'
    fi
    if [[ $TUI_UNICODE == 1 ]]; then
        TUI_POINTER='❯'; TUI_RADIO_ON='◉'; TUI_RADIO_OFF='○'
        TUI_RULE='─'; TUI_DOT='·'
    fi

    if _TUI_STTY="$(stty -g 2>/dev/null)"; then
        _TUI_SAVED=1
    else
        _TUI_STTY=""; _TUI_SAVED=0
    fi
    _TUI_ACTIVE=1
    _tui_raw

    if [[ $TUI_ANSI == 1 ]]; then printf '\033[?25l' >&2; fi

    if [[ $_TUI_TRAPPED == 0 ]]; then
        trap 'tui_cleanup' EXIT
        trap 'tui_cleanup; exit 130' INT
        trap 'tui_cleanup; exit 143' TERM
        _TUI_TRAPPED=1
    fi
    return 0
}

tui_cleanup() {
    if [[ $_TUI_ACTIVE == 0 ]]; then return 0; fi
    _TUI_ACTIVE=0
    if [[ $_TUI_SAVED == 1 ]]; then
        stty "$_TUI_STTY" 2>/dev/null || true
        _TUI_SAVED=0
    fi
    if [[ $TUI_ANSI == 1 ]]; then printf '\033[?25h' >&2; fi
    return 0
}

# One keypress, as a token: up/down/left/right/enter/space/backspace/clear/esc
# or the literal character.  A closed input arrives as EOT from the pty.
_tui_read_key() {
    local k tail c probe
    _TUI_KEY=""
    if ! IFS= read -rsn1 k; then _TUI_KEY="eof"; return 0; fi

    if [[ $k == $'\x1b' ]]; then
        # An arrow is Esc plus two bytes the terminal sends in one burst.  Poll
        # for them rather than wait, so a lone Esc returns at once -- and poll
        # with `-t 0`, the only bash 3.2-safe probe (a fractional `read -t` is
        # banned, and VMIN=0/VTIME=1 is ignored by bash's read).
        tail=""
        while [[ ${#tail} -lt 2 ]]; do
            probe=""
            if ! IFS= read -rsn1 -t 0 probe 2>/dev/null; then break; fi
            c="$probe"
            if [[ -z $c ]]; then
                IFS= read -rsn1 c 2>/dev/null || break
                if [[ -z $c ]]; then break; fi
            fi
            tail="$tail$c"
        done
        case "$tail" in
            '[A') _TUI_KEY="up" ;;
            '[B') _TUI_KEY="down" ;;
            '[C') _TUI_KEY="right" ;;
            '[D') _TUI_KEY="left" ;;
            *$'\x04'*) _TUI_KEY="eof" ;;
            *) _TUI_KEY="esc" ;;
        esac
        return 0
    fi

    case "$k" in
        '') _TUI_KEY="enter" ;;              # read -n1 stops at the newline itself
        ' ') _TUI_KEY="space" ;;
        $'\x7f'|$'\x08') _TUI_KEY="backspace" ;;
        $'\x15') _TUI_KEY="clear" ;;         # Ctrl-U
        $'\x04') _TUI_KEY="eof" ;;
        *) _TUI_KEY="$k" ;;
    esac
    return 0
}

# EOF on the input means the caller has lost its terminal; there is no sane
# selection to hand back, so abort the way an interrupt would.
_tui_abort() {
    tui_cleanup
    printf '\n' >&2
    exit 130
}

# Every widget starts a fresh block: there is nothing of its own to wipe yet,
# and on a non-ANSI terminal its block prints exactly once.
_tui_begin() {
    _TUI_LINES=0
    _TUI_DRAWN=0
    return 0
}

# Erase the block drawn last time, so the next frame lands on the same lines.
_tui_wipe() {
    local i=$_TUI_LINES
    while [[ $i -gt 0 ]]; do
        printf '\033[1A\033[2K' >&2
        i=$((i - 1))
    done
    _TUI_LINES=0
}

_tui_draw() {
    local title="$1"; shift
    local n=0
    if [[ $TUI_ANSI == 1 ]]; then
        _tui_wipe
    elif [[ $_TUI_DRAWN == 1 ]]; then
        return 0
    fi
    if [[ -n $title ]]; then
        printf '%s%s%s\n' "$TUI_BOLD" "$title" "$TUI_RESET" >&2
        n=$((n + 1))
    fi
    while [[ $# -gt 0 ]]; do
        printf '%s\n' "$1" >&2
        n=$((n + 1))
        shift
    done
    _TUI_LINES=$n
    _TUI_DRAWN=1
    return 0
}

tui_banner() {
    local title="$1" rule="" i=0
    while [[ $i -lt ${#title} ]]; do
        rule="$rule$TUI_RULE"
        i=$((i + 1))
    done
    printf '\n%s%s%s\n%s%s%s\n' \
        "$TUI_BOLD" "$title" "$TUI_RESET" "$TUI_DIM" "$rule" "$TUI_RESET" >&2
    return 0
}

# tui_menu TITLE DEFAULT OPTION... -> 0-based index on stdout.
tui_menu() {
    local title="$1" default="$2"; shift 2
    local opts=("$@") n=${#opts[@]} cur=0 i frame
    _tui_begin

    if [[ "$default" =~ ^[0-9]+$ ]] && [[ "$default" -ge 0 && "$default" -lt "$n" ]]; then
        cur="$default"
    fi

    while :; do
        frame=()
        i=0
        while [[ $i -lt $n ]]; do
            if [[ $i -eq $cur ]]; then
                frame[${#frame[@]}]="$TUI_CYAN$TUI_POINTER$TUI_RESET ${TUI_RADIO_ON} ${opts[$i]}"
            else
                frame[${#frame[@]}]="  ${TUI_RADIO_OFF} ${opts[$i]}"
            fi
            i=$((i + 1))
        done
        _tui_draw "$title" ${frame[@]+"${frame[@]}"}
        _tui_read_key
        case "$_TUI_KEY" in
            up)   if [[ $cur -gt 0 ]]; then cur=$((cur - 1)); fi ;;
            down) if [[ $cur -lt $((n - 1)) ]]; then cur=$((cur + 1)); fi ;;
            enter|space|right) break ;;
            [1-9]) if [[ $_TUI_KEY -le $n ]]; then cur=$((_TUI_KEY - 1)); fi ;;
            eof) _tui_abort ;;
        esac
    done
    printf '%s\n' "$cur"
    return 0
}

# tui_multi TITLE DEFAULTS OPTION... -> one 0/1 per option, in order, on stdout.
# Enter is refused while every option is off.
tui_multi() {
    local title="$1" defaults="$2"; shift 2
    local opts=("$@") n=${#opts[@]} cur=0 i frame hint box any sel
    _tui_begin
    sel=()
    i=0
    while [[ $i -lt $n ]]; do
        case "${defaults:$i:1}" in
            1) sel[$i]=1 ;;
            *) sel[$i]=0 ;;
        esac
        i=$((i + 1))
    done

    hint=""
    while :; do
        frame=()
        i=0
        while [[ $i -lt $n ]]; do
            if [[ ${sel[$i]} == 1 ]]; then box="[${TUI_RADIO_ON}]"; else box="[${TUI_RADIO_OFF}]"; fi
            if [[ $i -eq $cur ]]; then
                frame[${#frame[@]}]="$TUI_CYAN$TUI_POINTER$TUI_RESET $box ${opts[$i]}"
            else
                frame[${#frame[@]}]="  $box ${opts[$i]}"
            fi
            i=$((i + 1))
        done
        if [[ -n $hint ]]; then frame[${#frame[@]}]="$TUI_YELLOW$hint$TUI_RESET"; fi
        _tui_draw "$title" ${frame[@]+"${frame[@]}"}
        _tui_read_key
        case "$_TUI_KEY" in
            up)   if [[ $cur -gt 0 ]]; then cur=$((cur - 1)); fi ;;
            down) if [[ $cur -lt $((n - 1)) ]]; then cur=$((cur + 1)); fi ;;
            space) if [[ ${sel[$cur]} == 1 ]]; then sel[$cur]=0; else sel[$cur]=1; fi; hint="" ;;
            enter)
                any=0
                i=0
                while [[ $i -lt $n ]]; do
                    if [[ ${sel[$i]} == 1 ]]; then any=1; break; fi
                    i=$((i + 1))
                done
                if [[ $any == 1 ]]; then break; fi
                hint="Select at least one."
                ;;
            [1-9]) if [[ $_TUI_KEY -le $n ]]; then cur=$((_TUI_KEY - 1)); fi ;;
            eof) _tui_abort ;;
        esac
    done

    local out=""
    i=0
    while [[ $i -lt $n ]]; do
        out="$out${sel[$i]}"
        i=$((i + 1))
    done
    printf '%s\n' "$out"
    return 0
}

# tui_input TITLE DEFAULT -> the edited string on stdout.  The default is the
# starting buffer, so Enter alone returns it unchanged.
tui_input() {
    local title="$1" default="$2"
    local buf="$default"
    _tui_begin

    while :; do
        _tui_draw "$title" "$TUI_CYAN$TUI_POINTER$TUI_RESET $buf"
        _tui_read_key
        case "$_TUI_KEY" in
            enter) break ;;
            backspace) if [[ -n $buf ]]; then buf="${buf%?}"; fi ;;
            clear) buf="" ;;
            space) buf="$buf " ;;
            eof) _tui_abort ;;
            up|down|left|right|esc) ;;
            *) buf="$buf$_TUI_KEY" ;;
        esac
    done
    printf '%s\n' "$buf"
    return 0
}

# tui_confirm QUESTION -> status 0 for yes, 1 for no.
tui_confirm() {
    local question="$1"
    _tui_begin

    while :; do
        _tui_draw "$question [Y/n]"
        _tui_read_key
        case "$_TUI_KEY" in
            enter|y|Y) return 0 ;;
            n|N) return 1 ;;
            eof) _tui_abort ;;
        esac
    done
}
