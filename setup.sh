#!/usr/bin/env bash
#
# Installs this repo's skills into an agent-skills discovery location.
#
# OpenCode and VS Code Copilot both auto-discover ~/.agents/skills and
# .agents/skills, so either scope works with zero configuration.
#
#   Default scope: global (~/.agents/skills) - available in every project.
#   --scope local: .agents/skills inside this repo (gitignored).
#
#   Default mode: copy. Re-run to refresh after editing ./skills.
#   --mode link:  symlink per skill so edits apply immediately.
#
#   --clean removes only entries it can prove are its own (symlinks, or
#   directories containing a matching SKILL.md). It never follows links.
#
# Idempotent. No dependencies beyond bash/coreutils. No sudo required.
#
# Usage:
#   ./setup.sh
#   ./setup.sh --mode link
#   ./setup.sh --scope local --mode link
#   ./setup.sh --clean

set -euo pipefail

scope="global"
mode="copy"
clean=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || { echo "error: --scope needs a value" >&2; exit 2; }
            scope="$2"; shift 2 ;;
        --mode)
            [[ $# -ge 2 ]] || { echo "error: --mode needs a value" >&2; exit 2; }
            mode="$2"; shift 2 ;;
        --clean) clean=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

case "$scope" in global|local) ;; *) echo "error: --scope must be global or local" >&2; exit 2 ;; esac
case "$mode" in copy|link) ;; *) echo "error: --mode must be copy or link" >&2; exit 2 ;; esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_dir="$repo_root/skills"
if [[ "$scope" == "global" ]]; then
    target_dir="$HOME/.agents/skills"
else
    target_dir="$repo_root/.agents/skills"
fi

[[ -d "$skills_dir" ]] || { echo "error: skills directory not found: $skills_dir" >&2; exit 1; }

remove_managed() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 0
    if [[ -L "$path" ]]; then
        rm "$path"
        echo "  unlinked $path"
    elif [[ -d "$path" ]]; then
        if [[ -f "$path/SKILL.md" ]]; then
            rm -rf "$path"
            echo "  removed  $path"
        else
            echo "  skipped  $path - exists but is not a managed skill directory" >&2
        fi
    fi
}

echo "Setup: scope=$scope mode=$mode target=$target_dir"
if [[ "$clean" == "1" ]]; then
    echo "Cleaning managed entries from $target_dir"
else
    mkdir -p "$target_dir"
fi

count=0
for src in "$skills_dir"/*/; do
    [[ -f "$src/SKILL.md" ]] || continue
    name="$(basename "$src")"
    dst="$target_dir/$name"

    if [[ "$clean" == "1" ]]; then
        remove_managed "$dst"
        continue
    fi

    if [[ "$mode" == "link" && -L "$dst" && -f "$dst/SKILL.md" ]]; then
        echo "  linked   $name (already current)"
        count=$((count + 1))
        continue
    fi

    remove_managed "$dst"
    if [[ "$mode" == "link" ]]; then
        src_abs="$(cd "$src" && pwd)"
        ln -s "$src_abs" "$dst"
        echo "  linked   $name -> $src_abs"
    else
        mkdir -p "$dst"
        cp -R "$src". "$dst"/
        echo "  copied   $name"
    fi
    count=$((count + 1))
done

if [[ "$count" == "0" && "$clean" == "0" ]]; then
    echo "error: no skills found in $skills_dir" >&2
    exit 1
fi

if [[ "$clean" == "1" ]]; then
    rmdir "$target_dir" 2>/dev/null || true
    if [[ "$scope" == "local" ]]; then
        rmdir "$repo_root/.agents" 2>/dev/null || true
    fi
    echo "Done: cleaned managed entries from $target_dir"
else
    echo "Done: $count skills installed to $target_dir ($mode)."
    echo "Restart any running agent session to pick them up."
fi
