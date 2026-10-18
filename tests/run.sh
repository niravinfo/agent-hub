#!/usr/bin/env bash
#
# Zero-dependency tests for lib/tui.sh.
#
#   bash tests/run.sh
#
# A failed assertion is recorded and the run continues, so one test reports
# every problem it found before the suite moves on.  Key handling needs a real
# terminal, so those cases run a driver script under script(1); they skip
# cleanly where script(1) is absent or lacks util-linux's -qec flags.
#
# bash 3.2 compatible, like the library it tests (macOS stock bash).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# A blocked reader must fail the suite rather than stall it; util-linux
# script(1) has no timeout of its own, so cap the pty run from the outside.
PTY_TIMEOUT="${PTY_TIMEOUT:-10}"
PTY_SETTLE="${PTY_SETTLE:-1}"
PTY_OUT=""

failures=0
skipped=0
_test_failed=0

assert_eq() {
    local label="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then return 0; fi
    _fail "$label: want [$want] got [$got]"
    return 1
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) return 0 ;;
    esac
    _fail "$label: [$needle] not in output: $(snippet "$haystack")"
    return 1
}

assert_no_ansi() {
    local label="$1" text="$2"
    case "$text" in
        *$'\033['*) _fail "$label: ANSI escape sequence in output"; return 1 ;;
    esac
    return 0
}

# The brief's three helpers cannot express "printable ASCII only"; grep under
# LC_ALL=C keeps the test byte-based whatever locale the suite runs in.
assert_ascii() {
    local label="$1" text="$2"
    if printf '%s' "$text" | LC_ALL=C grep -q '[^ -~]'; then
        _fail "$label: non-ASCII bytes in output"
        return 1
    fi
    return 0
}

_fail() {
    _test_failed=1
    printf '    %s\n' "$1" >&2
}

# One readable line for a failure message: controls and escapes removed.
snippet() {
    printf '%s' "$1" | LC_ALL=C tr -c '[:print:]\n' '.' | LC_ALL=C tr '\n' '|' | cut -c1-200
}

# Write an executable driver under the temp dir and print its path.  Every
# driver needs the library and a TERM that exercises the ANSI redraw path, so
# those are prepended; <body> is the test's own script.
mk_driver() {
    local body="$1" path
    path="$(mktemp "$TMP_ROOT/driver.XXXXXX")"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'TERM=xterm-256color\n'
        printf '%s\n' "source $(printf '%q' "$REPO_ROOT/lib/tui.sh") || exit 1"
        printf '%s\n' "$body"
    } > "$path"
    chmod +x "$path"
    printf '%s\n' "$path"
}

# Feed keystrokes to a driver through a pty.  Returns 2 when the pty tools are
# unusable so the caller can report a skip.  The probe runs on every call:
# drivers run inside a command substitution, where no cached state survives.
#
# The keystrokes are held back briefly: a fresh pty is in canonical mode, and
# its line discipline eats DEL and Ctrl-U before the reader can ever see them.
# The driver needs that moment to switch the tty to raw mode (tui_init).
pty_drive() {
    local driver="$1" keystrokes="$2" probe=""
    if ! command -v script >/dev/null 2>&1; then
        printf 'SKIP: pty tests (script(1) not found)\n' >&2
        return 2
    fi
    # Some implementations (macOS, BSD) reject util-linux's -qec.
    if ! probe="$(printf '' | script -qec 'printf PTYOK' /dev/null 2>/dev/null)" || [[ "$probe" != *PTYOK* ]]; then
        printf 'SKIP: pty tests (script(1) has no -qec)\n' >&2
        return 2
    fi
    if command -v timeout >/dev/null 2>&1; then
        { sleep "$PTY_SETTLE"; printf '%b' "$keystrokes"; } | timeout "$PTY_TIMEOUT" script -qec "bash \"$driver\"" /dev/null
    else
        { sleep "$PTY_SETTLE"; printf '%b' "$keystrokes"; } | script -qec "bash \"$driver\"" /dev/null
    fi
}

# Run a driver and stash its output in PTY_OUT; 2 means "skip this test".
# A driver that never got the library, or that was killed by the pty cap, is a
# failure -- otherwise a broken driver would look like a passing assertion.
pty_run() {
    PTY_OUT="$(pty_drive "$1" "$2")"
    local rc=$?
    case "$rc" in
        2) return 2 ;;
        0) return 0 ;;
        124) _fail "pty run exceeded ${PTY_TIMEOUT}s" ;;
        *) _fail "pty driver exited $rc" ;;
    esac
    return 1
}

# The `RESULT=...` line a driver printed, with the pty's CR stripped.  This is
# what lets a test assert an exact value rather than a substring.
pty_result() {
    printf '%s\n' "$1" | tr -d '\r' | grep 'RESULT=' | tail -n 1
}

test_glyph_ascii_fallback() {
    local out
    if ! out="$( TERM=dumb LANG=C LC_ALL=C; . "$REPO_ROOT/lib/tui.sh" && tui_init && printf '%s' "$TUI_POINTER" )"; then
        _fail "tui_init could not run"
        return 1
    fi
    assert_eq "a pointer glyph is set" "set" "${out:+set}"
    assert_ascii "pointer is ASCII under TERM=dumb" "$out"
}

test_menu_down_enter_selects_second() {
    pty_run "$(mk_driver 'tui_init; idx=$(tui_menu "Pick" 0 Alpha Beta); echo "RESULT=$idx"')" '\x1b[B\n' || return $?
    assert_contains "down then enter selects index 1" "$PTY_OUT" "RESULT=1"
}

test_menu_digit_jumps() {
    pty_run "$(mk_driver 'tui_init; idx=$(tui_menu "Pick" 0 A B C); echo "RESULT=$idx"')" '3\n' || return $?
    assert_contains "digit 3 selects the third option" "$PTY_OUT" "RESULT=2"
}

test_multi_space_toggles() {
    # Space toggles the highlighted option; Enter is the accept key.  The second
    # Enter after the toggle accepts, leaving only option B selected.
    pty_run "$(mk_driver 'tui_init; v=$(tui_multi "Pick" 11 A B); echo "RESULT=$v"')" ' \n' || return $?
    assert_contains "space cleared the first option" "$PTY_OUT" "RESULT=01"
}

test_multi_requires_one() {
    pty_run "$(mk_driver 'tui_init; v=$(tui_multi "Pick" 00 A B); echo "RESULT=$v"')" '\n\n' || return $?
    case "$PTY_OUT" in
        *RESULT=11*) _fail "empty selection advanced: $(snippet "$PTY_OUT")" ;;
    esac
    return 0
}

test_input_types_and_backspaces() {
    pty_run "$(mk_driver 'tui_init; s=$(tui_input "Path" /base); echo "RESULT=$s"')" 'x\x7f\x7f\n' || return $?
    # `/base` + x is `/basex`; two backspaces leave `/bas`, which is the `/ba`
    # prefix the brief asserts, pinned exactly here so a lost delete fails.
    assert_eq "typed char then two deletes" "RESULT=/bas" "$(pty_result "$PTY_OUT")"
}

test_confirm_no_is_status_1() {
    pty_run "$(mk_driver 'tui_init; if tui_confirm "Go?"; then echo "RESULT=yes"; else echo "RESULT=no"; fi')" 'n' || return $?
    assert_contains "n answers no" "$PTY_OUT" "RESULT=no"
}

test_lone_esc_does_not_hang() {
    # A lone Esc must return at once: the escape reader may not wait for an
    # arrow-sequence tail that will never arrive.
    local rc=0
    pty_drive "$(mk_driver 'tui_init; tui_menu "Pick" 0 A B')" '\x1b' >/dev/null 2>&1 || rc=$?
    case "$rc" in
        2) return 2 ;;
        0|130) return 0 ;;   # 130 is the library's own abort on input EOF
        124) _fail "lone Esc blocked" ;;
        *) _fail "lone Esc run exited $rc" ;;
    esac
    return 1
}

main() {
    local names name run=0
    names="$(declare -F | sed -n 's/.*[[:space:]]\(test_[A-Za-z0-9_]*\)$/\1/p' | LC_ALL=C sort)"

    for name in $names; do
        _test_failed=0
        run=$((run + 1))
        printf '%s ... ' "${name#test_}"
        "$name"
        local rc=$?
        if [[ $rc -eq 2 ]]; then
            printf 'skip\n'
            skipped=$((skipped + 1))
        elif [[ $_test_failed -ne 0 || $rc -ne 0 ]]; then
            printf 'FAIL\n'
            failures=$((failures + 1))
        else
            printf 'ok\n'
        fi
    done

    printf '\n%s run, %s failed, %s skipped\n' "$run" "$failures" "$skipped"
    [[ $failures -eq 0 ]] || exit 1
    exit 0
}

main "$@"
