#!/usr/bin/env bash
#
# Installs keyless remote MCP servers (Context7 + DeepWiki):
#
#   OpenCode : user level     ~/.config/opencode/opencode.json (every project)
#              project level ./opencode.json                  (this project)
#   Copilot  : user level     ~/.copilot/mcp-config.json       (every workspace;
#              portable format, read by Copilot tools and the Agent Host)
#   VS Code  : project level ./.vscode/mcp.json                (also read by
#              Copilot; commit it to share with your team)
#
# Interactive by default: a bare run asks, in order:
#     1) where - user level (global) or project level (local)
#     2) which application - OpenCode, Copilot, or both
#     3) which servers - comma separated numbers (e.g. 1,2)
#   then shows what it will write and asks for confirmation. Press Enter to
#   accept the bracketed default at any step. Prompts appear only on a real
#   terminal; pipes and CI fall back to the defaults silently. Any flag skips
#   the questions entirely (non-interactive, for scripting):
#
#   ./setup-mcp.sh --defaults      install everything at user level
#   ./setup-mcp.sh --skip-opencode
#   ./setup-mcp.sh --skip-copilot
#   ./setup-mcp.sh --clean         remove managed entries (user level)
#
# Safe by design: server definitions come from this repo's mcp/ templates,
# existing servers are never overwritten, nothing secret is written (both
# servers work keyless), every touched file is backed up as <file>.bak, and a
# target that is not plain JSON (e.g. JSONC with comments) is left untouched
# with manual instructions. Idempotent: re-running only adds what is missing.
#
# No dependencies beyond bash and python3. No sudo required.

set -euo pipefail

defaults_mode=0
skip_opencode=0
skip_copilot=0
clean=0

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --defaults) defaults_mode=1; shift ;;
        --skip-opencode) skip_opencode=1; shift ;;
        --skip-copilot) skip_copilot=1; shift ;;
        --clean) clean=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 is required for JSON merging (not found on PATH)" >&2
    exit 1
}

export REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SKIP_OPENCODE="$skip_opencode" SKIP_COPILOT="$skip_copilot" MCP_CLEAN="$clean"
export MCP_TARGETS="" MCP_SERVERS=""

eof_abort() {
    printf '\nno input left (EOF) - aborting. Use --defaults for a non-interactive install.\n' >&2
    exit 1
}

normalize_servers() { # $1 = raw input -> comma list of server names (1 = invalid)
    local raw want_c=0 want_d=0 tok out=""
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    raw="$(printf '%s' "$raw" | sed -E 's/[[:space:]]+/,/g')"
    raw="${raw#,}"; raw="${raw%,}"
    case "$raw" in
        all|both|'*') printf 'context7,deepwiki\n'; return 0 ;;
    esac
    local IFS=','
    for tok in $raw; do
        [[ -n "$tok" ]] || continue
        case "$tok" in
            1|context7) want_c=1 ;;
            2|deepwiki) want_d=1 ;;
            1-2|2-1) want_c=1; want_d=1 ;;
            *) return 1 ;;
        esac
    done
    [[ "$want_c" -eq 1 ]] && out="context7"
    [[ "$want_d" -eq 1 ]] && out="${out:+$out,}deepwiki"
    [[ -n "$out" ]] || return 1
    printf '%s' "$out"
}

interactive_setup() {
    echo "MCP server installer - Context7 + DeepWiki"
    echo ""
    echo "Step 1/3 - Where do you want to install?"
    echo "  1) User level (global)   - available in every project"
    echo "  2) Project level (local) - this project only"
    scope=""
    app=""
    servers=""
    while :; do
        printf 'Select 1 or 2 [1]: '
        read -r ans || eof_abort
        ans="${ans:-1}"
        case "$ans" in
            1|2) scope="$ans"; break ;;
            *) echo "  invalid selection: $ans - try again" >&2 ;;
        esac
    done

    echo ""
    echo "Step 2/3 - Which application?"
    echo "  1) OpenCode"
    echo "  2) Copilot"
    echo "  3) Both"
    while :; do
        printf 'Select 1, 2 or 3 [3]: '
        read -r ans || eof_abort
        ans="${ans:-3}"
        case "$ans" in
            1|2|3) app="$ans"; break ;;
            *) echo "  invalid selection: $ans - try again" >&2 ;;
        esac
    done

    echo ""
    echo "Step 3/3 - Which servers do you want to add?"
    echo "  1) context7 - up-to-date library docs (keyless)"
    echo "  2) deepwiki - public GitHub repo Q&A (keyless)"
    while :; do
        printf 'Select comma separated values, e.g. 1,2 [1,2]: '
        read -r ans || eof_abort
        ans="${ans:-1,2}"
        if norm="$(normalize_servers "$ans")"; then
            servers="$norm"
            break
        fi
        echo "  invalid selection: $ans - try again" >&2
    done

    case "$scope:$app" in
        1:1) targets="opencode" ;;
        1:2) targets="copilot" ;;
        1:3) targets="opencode,copilot" ;;
        2:1) targets="opencode-local" ;;
        2:2) targets="vscode-local" ;;
        2:3) targets="opencode-local,vscode-local" ;;
        *) echo "error: internal selection error" >&2; exit 2 ;;
    esac

    echo ""
    echo "Ready to install:"
    for pick in ${targets//,/ }; do
        case "$pick" in
            opencode)       echo "  - OpenCode (user level)             $HOME/.config/opencode/opencode.json" ;;
            copilot)        echo "  - Copilot (user level)              $HOME/.copilot/mcp-config.json" ;;
            opencode-local) echo "  - OpenCode (project level)          $PWD/opencode.json" ;;
            vscode-local)   echo "  - VS Code / Copilot (project level) $PWD/.vscode/mcp.json" ;;
        esac
    done
    printf 'Servers: %s\n' "$(printf '%s' "$servers" | sed 's/,/, /g')"

    while :; do
        printf 'Write these files? [Y/n]: '
        read -r ans || eof_abort
        case "${ans:-y}" in
            [Yy]|[Yy][Ee][Ss]) break ;;
            [Nn]|[Nn][Oo]) echo "Aborted - nothing was changed."; exit 0 ;;
            *) echo "  please answer y or n" >&2 ;;
        esac
    done

    echo ""
    export MCP_TARGETS="$targets" MCP_SERVERS="$servers"
}

interactive=0
if [[ $defaults_mode -eq 0 && $clean -eq 0 && $skip_opencode -eq 0 && $skip_copilot -eq 0 ]]; then
    # Real terminal (or the MCP_ASSUME_TTY test hook) -> guided setup.
    if [[ -t 0 || "${MCP_ASSUME_TTY:-0}" = "1" ]]; then
        interactive=1
    fi
fi

if [[ $interactive -eq 1 ]]; then
    interactive_setup
fi

python3 <<'EOF'
import json, os, shutil, sys

repo = os.environ["REPO_ROOT"]
clean = os.environ.get("MCP_CLEAN") == "1"
home = os.path.expanduser("~")
cwd = os.getcwd()

selected_keys = [k for k in os.environ.get("MCP_TARGETS", "").split(",") if k]
selected_servers = [s for s in os.environ.get("MCP_SERVERS", "").split(",") if s]

opencode_fresh = {"$schema": "https://opencode.ai/config.json", "mcp": {}}

all_targets = [
    {
        "key": "opencode",
        "name": "OpenCode (user level)",
        "skip_env": "SKIP_OPENCODE",
        "legacy": True,
        "file": os.path.join(home, ".config", "opencode", "opencode.json"),
        "template": os.path.join(repo, "mcp", "opencode.jsonc"),
        "section": "mcp",
        "fresh": opencode_fresh,
    },
    {
        "key": "opencode-local",
        "name": "OpenCode (project level)",
        "file": os.path.join(cwd, "opencode.json"),
        "template": os.path.join(repo, "mcp", "opencode.jsonc"),
        "section": "mcp",
        "fresh": opencode_fresh,
    },
    {
        "key": "copilot",
        "name": "Copilot (user level)",
        "skip_env": "SKIP_COPILOT",
        "legacy": True,
        "file": os.path.join(home, ".copilot", "mcp-config.json"),
        "template": os.path.join(repo, "mcp", "copilot-user-mcp-config.json"),
        "section": "mcpServers",
        "fresh": {"mcpServers": {}},
    },
    {
        "key": "vscode-local",
        "name": "VS Code / Copilot (project level)",
        "file": os.path.join(cwd, ".vscode", "mcp.json"),
        "template": os.path.join(repo, "mcp", "vscode-workspace-mcp.json"),
        "section": "servers",
        "fresh": {"servers": {}},
    },
]

if selected_keys:
    unknown = set(selected_keys) - {t["key"] for t in all_targets}
    if unknown:
        print("error: unknown target(s): " + ", ".join(sorted(unknown)))
        sys.exit(2)
    targets = [t for t in all_targets if t["key"] in selected_keys]
else:
    targets = [
        t for t in all_targets
        if t.get("legacy") and os.environ.get(t.get("skip_env", ""), "") != "1"
    ]


def load_template(path):
    with open(path) as f:
        text = f.read()
    if path.endswith(".jsonc"):
        text = "\n".join(
            line for line in text.splitlines()
            if not line.lstrip().startswith("//")
        )
    return json.loads(text)


fail = False
for t in targets:
    try:
        desired_section = load_template(t["template"])[t["section"]]
    except (OSError, ValueError) as e:
        print(f"[{t['name']}] error: cannot read template: {e}")
        fail = True
        continue

    if selected_servers:
        desired_section = {
            n: d for n, d in desired_section.items() if n in selected_servers
        }

    existed = os.path.exists(t["file"])
    if existed:
        try:
            with open(t["file"]) as f:
                current = json.load(f)
        except ValueError:
            print(f"[{t['name']}] skipped {t['file']}: not plain JSON "
                  f"(JSONC with comments?). Add the \"{t['section']}\" block from "
                  f"{t['template']} manually. File left untouched.")
            continue
    else:
        current = {k: (dict(v) if isinstance(v, dict) else v)
                   for k, v in t["fresh"].items()}

    if not isinstance(current, dict):
        print(f"[{t['name']}] skipped {t['file']}: top level is not an object. Left untouched.")
        continue
    section = current.setdefault(t["section"], {})
    if not isinstance(section, dict):
        print(f"[{t['name']}] skipped {t['file']}: \"{t['section']}\" is not an object. Left untouched.")
        continue

    if clean:
        removed = [n for n, want in desired_section.items()
                   if isinstance(section.get(n), dict)
                   and section[n].get("url") == want.get("url")]
        if not removed:
            print(f"[{t['name']}] nothing managed to remove in {t['file']}")
            continue
        shutil.copy2(t["file"], t["file"] + ".bak")
        for n in removed:
            del section[n]
        with open(t["file"], "w") as f:
            json.dump(current, f, indent=2)
            f.write("\n")
        print(f"[{t['name']}] removed {', '.join(sorted(removed))} "
              f"from {t['file']} (backup: {t['file']}.bak)")
        continue

    added, present, skipped = [], [], []
    for name, want in desired_section.items():
        have = section.get(name)
        if have is None:
            section[name] = want
            added.append(name)
        elif (isinstance(have, dict)
              and have.get("url") == want.get("url")
              and have.get("type") == want.get("type")):
            present.append(name)
        else:
            skipped.append(name)
    if skipped:
        print(f"[{t['name']}] skipped {', '.join(sorted(skipped))}: "
              f"name(s) already used by your own server(s) pointing elsewhere. Left untouched.")
    if not added:
        if present:
            print(f"[{t['name']}] {', '.join(sorted(present))} already present in {t['file']}")
        elif not skipped:
            print(f"[{t['name']}] nothing to do")
        continue
    if existed:
        shutil.copy2(t["file"], t["file"] + ".bak")
        print(f"[{t['name']}] backup: {t['file']}.bak")
    else:
        os.makedirs(os.path.dirname(t["file"]), exist_ok=True)
    with open(t["file"], "w") as f:
        json.dump(current, f, indent=2)
        f.write("\n")
    print(f"[{t['name']}] added {', '.join(sorted(added))} to {t['file']}")

sys.exit(1 if fail else 0)
EOF
