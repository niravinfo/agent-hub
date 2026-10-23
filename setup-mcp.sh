#!/usr/bin/env bash
#
# Installs keyless remote MCP servers (Context7 + DeepWiki):
#
#   OpenCode : user level    ~/.config/opencode/opencode.json(c) (every project)
#              project level ./opencode.json(c)                  (this project)
#   Copilot  : user level    ~/.copilot/mcp-config.json          (every project)
#              project level ./.mcp.json                         (this project)
#
# Interactive by default: on a real terminal a bare run drives an arrow-key
# wizard - where (user or project level), which application (OpenCode and/or
# Copilot checkboxes; at least one), and which servers (context7 and/or
# deepwiki checkboxes; at least one) - then shows what it will write and asks
# for confirmation. Prompts appear only on a real terminal; pipes and CI fall
# back to the defaults silently. Any flag skips the questions entirely
# (non-interactive, for scripting):
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
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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

# The interactive wizard is the shared, dependency-free arrow-key layer; it
# draws to stderr and hands values back on stdout.
# shellcheck source=lib/tui.sh
source "$REPO_ROOT/lib/tui.sh"

interactive_setup() {
    echo "MCP server installer - Context7 + DeepWiki"
    echo ""
    scope=""
    app=""
    servers=""

    if [[ "$(tui_menu "Step 1/3 - Where do you want to install?" 0 "User level (global)   - available in every project" "Project level (local) - this project only")" == "0" ]]; then
        scope=1
    else
        scope=2
    fi

    # Checkboxes, not a one-of-three menu: the widget refuses an all-off
    # answer, so the pair maps back onto the old 1/2/3 application codes.
    apps="$(tui_multi "Step 2/3 - Which application?" 11 "OpenCode" "Copilot")"
    if [[ "${apps:0:1}" == "1" && "${apps:1:1}" == "1" ]]; then app=3
    elif [[ "${apps:0:1}" == "1" ]]; then app=1
    else app=2; fi

    picks="$(tui_multi "Step 3/3 - Which servers do you want to add?" 11 "context7 - up-to-date library docs (keyless)" "deepwiki - public GitHub repo Q&A (keyless)")"
    [[ "${picks:0:1}" == "1" ]] && servers="context7"
    [[ "${picks:1:1}" == "1" ]] && servers="${servers:+$servers,}deepwiki"

    case "$scope:$app" in
        1:1) targets="opencode" ;;
        1:2) targets="copilot" ;;
        1:3) targets="opencode,copilot" ;;
        2:1) targets="opencode-local" ;;
        2:2) targets="copilot-local" ;;
        2:3) targets="opencode-local,copilot-local" ;;
        *) echo "error: internal selection error" >&2; exit 2 ;;
    esac

    tui_banner "Ready to install:"
    for pick in ${targets//,/ }; do
        case "$pick" in
            opencode)       echo "  - OpenCode (user level)    $HOME/.config/opencode/opencode.json(c)" ;;
            copilot)        echo "  - Copilot (user level)     $HOME/.copilot/mcp-config.json" ;;
            opencode-local) echo "  - OpenCode (project level) $PWD/opencode.json(c)" ;;
            copilot-local)  echo "  - Copilot (project level)  $PWD/.mcp.json" ;;
        esac
    done
    printf 'Servers: %s\n' "$(printf '%s' "$servers" | sed 's/,/, /g')"

    if ! tui_confirm "Write these files?"; then
        echo "Aborted - nothing was changed."
        exit 0
    fi

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
    tui_init
    interactive_setup
    tui_cleanup
fi

python3 <<'EOF'
import json, os, shutil, sys

repo = os.environ["REPO_ROOT"]
clean = os.environ.get("MCP_CLEAN") == "1"
home = os.path.expanduser("~")
cwd = os.getcwd()

selected_keys = [k for k in os.environ.get("MCP_TARGETS", "").split(",") if k]
selected_servers = [s for s in os.environ.get("MCP_SERVERS", "").split(",") if s]

def existing_path(*paths):
    for path in paths:
        if os.path.exists(path):
            return path
    return paths[-1]


opencode_fresh = {"$schema": "https://opencode.ai/config.json", "mcp": {}}
opencode_user_file = existing_path(
    os.path.join(home, ".config", "opencode", "opencode.jsonc"),
    os.path.join(home, ".config", "opencode", "opencode.json"),
)
opencode_local_file = existing_path(
    os.path.join(cwd, ".opencode", "opencode.jsonc"),
    os.path.join(cwd, ".opencode", "opencode.json"),
    os.path.join(cwd, "opencode.jsonc"),
    os.path.join(cwd, "opencode.json"),
)

all_targets = [
    {
        "key": "opencode",
        "name": "OpenCode (user level)",
        "skip_env": "SKIP_OPENCODE",
        "legacy": True,
        "file": opencode_user_file,
        "template": os.path.join(repo, "mcp", "opencode.jsonc"),
        "section": ["mcp", "servers"],
        "fresh": opencode_fresh,
    },
    {
        "key": "opencode-local",
        "name": "OpenCode (project level)",
        "file": opencode_local_file,
        "template": os.path.join(repo, "mcp", "opencode.jsonc"),
        "section": ["mcp", "servers"],
        "fresh": opencode_fresh,
    },
    {
        "key": "copilot",
        "name": "Copilot (user level)",
        "skip_env": "SKIP_COPILOT",
        "legacy": True,
        "file": os.path.join(home, ".copilot", "mcp-config.json"),
        "template": os.path.join(repo, "mcp", "copilot-user-mcp-config.json"),
        "section": ["mcpServers"],
        "fresh": {"mcpServers": {}},
    },
    {
        "key": "copilot-local",
        "name": "Copilot (project level)",
        "file": os.path.join(cwd, ".mcp.json"),
        "template": os.path.join(repo, "mcp", "copilot-user-mcp-config.json"),
        "section": ["mcpServers"],
        "fresh": {"mcpServers": {}},
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


def resolve_section(document, path, create=False):
    node = document
    for key in path:
        if not isinstance(node, dict):
            return None
        if key not in node:
            if not create:
                return None
            node[key] = {}
        node = node[key]
    return node if isinstance(node, dict) else None


fail = False
for t in targets:
    section_name = ".".join(t["section"])
    try:
        desired_section = resolve_section(
            load_template(t["template"]), t["section"]
        )
        if desired_section is None:
            raise ValueError(f'"{section_name}" is not an object')
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
                  f"(JSONC with comments?). Add the \"{section_name}\" block from "
                  f"{t['template']} manually. File left untouched.")
            continue
    else:
        current = {k: (dict(v) if isinstance(v, dict) else v)
                   for k, v in t["fresh"].items()}

    if not isinstance(current, dict):
        print(f"[{t['name']}] skipped {t['file']}: top level is not an object. Left untouched.")
        continue
    section = resolve_section(current, t["section"], create=not clean)
    if section is None:
        if clean:
            print(f"[{t['name']}] nothing managed to remove in {t['file']}")
        else:
            print(f"[{t['name']}] skipped {t['file']}: "
                  f"\"{section_name}\" is not an object. Left untouched.")
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
