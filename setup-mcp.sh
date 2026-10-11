#!/usr/bin/env bash
#
# Installs keyless remote MCP servers (Context7 + DeepWiki) into user-level configs:
#   OpenCode: merges "mcp" entries into ~/.config/opencode/opencode.json
#   Copilot:  merges "mcpServers" entries into ~/.copilot/mcp-config.json
#             (portable format, read by Copilot tools and the Agent Host)
#
# Safe by design: server definitions come from this repo's mcp/ templates,
# existing servers are never overwritten, nothing secret is written (both
# servers work keyless), every touched file is backed up as <file>.bak, and a
# target that is not plain JSON (e.g. JSONC with comments) is left untouched
# with manual instructions. Idempotent: re-running only adds what is missing.
#
# Usage:
#   ./setup-mcp.sh
#   ./setup-mcp.sh --skip-opencode
#   ./setup-mcp.sh --skip-copilot
#   ./setup-mcp.sh --clean   (removes only entries pointing at our URLs)
#
# No dependencies beyond bash and python3. No sudo required.

set -euo pipefail

skip_opencode=0
skip_copilot=0
clean=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

python3 <<'EOF'
import json, os, shutil, sys

repo = os.environ["REPO_ROOT"]
clean = os.environ.get("MCP_CLEAN") == "1"
home = os.path.expanduser("~")

targets = [
    {
        "name": "OpenCode",
        "skip": os.environ.get("SKIP_OPENCODE") == "1",
        "file": os.path.join(home, ".config", "opencode", "opencode.json"),
        "template": os.path.join(repo, "mcp", "opencode.jsonc"),
        "section": "mcp",
        "fresh": {"$schema": "https://opencode.ai/config.json", "mcp": {}},
    },
    {
        "name": "Copilot",
        "skip": os.environ.get("SKIP_COPILOT") == "1",
        "file": os.path.join(home, ".copilot", "mcp-config.json"),
        "template": os.path.join(repo, "mcp", "copilot-user-mcp-config.json"),
        "section": "mcpServers",
        "fresh": {"mcpServers": {}},
    },
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
    if t["skip"]:
        continue
    try:
        desired = load_template(t["template"])[t["section"]]
    except (OSError, ValueError) as e:
        print(f"[{t['name']}] error: cannot read template: {e}")
        fail = True
        continue

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
        removed = [n for n, want in desired.items()
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
    for name, want in desired.items():
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
