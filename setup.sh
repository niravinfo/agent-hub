#!/usr/bin/env bash
#
# Installs this repo's skills and agents into agent discovery locations.
#
# OpenCode and VS Code Copilot both auto-discover ~/.agents/skills and
# .agents/skills, so either scope works with zero configuration.
#
#   Default scope: global (~/.agents/skills) - available in every project.
#   --scope local: .agents/skills plus an AGENTS.md copy inside one project
#   folder (you are asked for the path; this repo is the default). Local
#   scope never touches user-level files; an existing AGENTS.md that differs
#   from the setup/AGENTS.md template is left alone.
#
#   Default mode: copy. Re-run to refresh after editing ./skills.
#   --mode link:  symlink per skill so edits apply immediately.
#
#   --clean removes only entries it can prove are its own (symlinks, or
#   directories containing a matching SKILL.md). It never follows links.
#
#   Interactive by default: with no selection flags, a bare ./setup.sh asks
#   what to do (install or clean), which harness to configure (both /
#   OpenCode / Copilot / neither), how to install skills (copy or link
#   shortcut), and where (global or local scope). Pass any flag explicitly
#   to skip its question; --yes answers everything with defaults
#   (automation/CI). Prompts appear only on a real terminal; pipes and CI
#   fall back to defaults silently.
#
#   Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
#   find ~/.agents/skills on their own, but neither forces the discipline of
#   loading a matching skill before work starts. Both always-on files below
#   are always installed (they are required for skills to load properly):
#       OpenCode  ~/.config/opencode/AGENTS.md          every session
#       Copilot   ~/.copilot/copilot-instructions.md    every repository (Agent Host;
#                                                       Local agent uses profile storage)
#   Both are copies of setup/AGENTS.md (the same template local scope installs
#   at a project root). A file that differs is left alone unless it carries
#   the managed marker; --clean removes only copies that still match.
#
# Idempotent. No dependencies beyond bash/coreutils. No sudo required.
#
# Usage:
#   ./setup.sh
#   ./setup.sh --mode link
#   ./setup.sh --scope local --mode link
#   ./setup.sh --clean
#   ./setup.sh --yes            # answer everything with defaults (CI-safe)

set -euo pipefail

scope="global"
mode="copy"
clean=0
opencode_rules=0
copilot_rules=0
yes_all=0
interactive=0
scope_explicit=0
mode_explicit=0
rules_explicit=0
skip_opencode_rules=0
skip_copilot_rules=0

usage() {
    sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)
            [[ $# -ge 2 ]] || { echo "error: --scope needs a value" >&2; exit 2; }
            scope="$2"; scope_explicit=1; shift 2 ;;
        --mode)
            [[ $# -ge 2 ]] || { echo "error: --mode needs a value" >&2; exit 2; }
            mode="$2"; mode_explicit=1; shift 2 ;;
        --clean) clean=1; shift ;;
        --opencode-rules) opencode_rules=1; rules_explicit=1; shift ;;
        --copilot-rules) copilot_rules=1; rules_explicit=1; shift ;;
        --yes|--no-prompt|--non-interactive) yes_all=1; shift ;;
        --interactive) interactive=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

case "$scope" in global|local) ;; *) echo "error: --scope must be global or local" >&2; exit 2 ;; esac
case "$mode" in copy|link) ;; *) echo "error: --mode must be copy or link" >&2; exit 2 ;; esac

can_prompt() { [[ -t 0 && -t 1 ]]; }

# menu TITLE DEFAULT_INDEX OPTION... -> prints chosen index (0-based) to stdout.
# Empty answer (or EOF) selects the default. Accepts number or option name.
menu() {
    local title="$1" default="$2"; shift 2
    local opts=("$@")
    echo "" >&2
    echo "$title" >&2
    local i
    for i in "${!opts[@]}"; do
        local mark=""
        [[ $i == "$default" ]] && mark=" (default)"
        echo "  [$((i+1))] ${opts[$i]}$mark" >&2
    done
    local answer
    while true; do
        printf "Select [1-%s, Enter=%s]: " "${#opts[@]}" "$((default+1))" >&2
        if ! IFS= read -r answer; then echo "" >&2; echo "$default"; return 0; fi
        answer="$(printf '%s' "$answer" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$answer" ]]; then echo "$default"; return 0; fi
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#opts[@]} )); then
            echo "$((answer-1))"; return 0
        fi
        local low
        low="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
        for i in "${!opts[@]}"; do
            local opt_low short
            opt_low="$(printf '%s' "${opts[$i]}" | tr '[:upper:]' '[:lower:]')"
            short="${opt_low%% *}"
            if [[ "$low" == "$opt_low" || "$low" == "$short" ]]; then
                echo "$i"; return 0
            fi
        done
        echo "  Enter 1-${#opts[@]}, a listed name, or empty for default." >&2
    done
}

if [[ $interactive == "1" && $yes_all == "1" ]]; then
    echo "error: cannot combine --interactive with --yes/--no-prompt" >&2; exit 2
fi
if [[ $interactive == "1" ]] && ! can_prompt; then
    echo "error: --interactive requested but no terminal is attached. Run in a terminal or pass flags explicitly." >&2; exit 2
fi

quiet=0
if [[ $yes_all == "1" ]]; then quiet=1; fi
if [[ $interactive == "0" ]] && ! can_prompt; then quiet=1; fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_dir="$repo_root/skills"
template_agents="$repo_root/setup/AGENTS.md"
local_target="$repo_root"

if [[ $quiet == "0" ]]; then
    if [[ $clean == "0" ]]; then
        # No --clean flag: ask install vs clean. (A passed --clean skips this.)
        choice="$(menu "What do you want to do?" 0 "Install skills" "Clean up installed files")"
        if [[ "$choice" == "1" ]]; then clean=1; fi
    fi
    if [[ $rules_explicit == "0" ]]; then
        if [[ $clean == "1" ]]; then
            choice="$(menu "Which rules files apply?" 0 "Both" "OpenCode only" "Copilot only")"
        else
            choice="$(menu "Which harness do you want to configure?" 0 "Both (OpenCode + Copilot)" "OpenCode only" "Copilot only")"
        fi
        case "$choice" in
            1) skip_copilot_rules=1 ;;
            2) skip_opencode_rules=1 ;;
        esac
    fi
    if [[ $clean == "0" && $mode_explicit == "0" ]]; then
        choice="$(menu "How should skill files be installed?" 0 "Copy (safe snapshot; re-run to refresh)" "Link shortcut (symlink; edits apply immediately)")"
        if [[ "$choice" == "1" ]]; then mode="link"; fi
    fi
    if [[ $scope_explicit == "0" ]]; then
        choice="$(menu "Where should skills be installed?" 0 "Global (~/.agents/skills, every project)" "Local (a single project folder)")"
        if [[ "$choice" == "1" ]]; then scope="local"; fi
    fi
    if [[ "$scope" == "local" ]]; then
        while true; do
            printf "Target project path? [Enter=%s]: " "$repo_root" >&2
            if ! IFS= read -r answer; then echo "" >&2; break; fi
            answer="$(printf '%s' "$answer" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [[ -z "$answer" ]]; then break; fi
            case "$answer" in ~*) answer="${answer/#\~/$HOME}" ;; esac
            case "$answer" in /*) candidate="$answer" ;; *) candidate="$repo_root/$answer" ;; esac
            if [[ -d "$candidate" ]]; then local_target="$(cd "$candidate" && pwd)"; break; fi
            echo "  Directory not found. Enter an existing folder or empty for default." >&2
        done
    fi
fi

if [[ "$scope" == "global" ]]; then
    target_dir="$HOME/.agents/skills"
else
    target_dir="$local_target/.agents/skills"
fi

[[ -d "$skills_dir" ]] || { echo "error: skills directory not found: $skills_dir" >&2; exit 1; }

marker='<!-- agent-hub:managed -->'

remove_managed() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || return 0
    if [[ -L "$path" ]]; then
        rm "$path"
        echo "  unlinked $path"
    elif [[ -f "$path" ]]; then
        if grep -qF "$marker" "$path" 2>/dev/null; then
            rm "$path"
            echo "  removed  $path"
        else
            echo "  skipped  $path - not created by this script" >&2
        fi
    elif [[ -d "$path" ]]; then
        if [[ -f "$path/SKILL.md" ]]; then
            rm -rf "$path"
            echo "  removed  $path"
        else
            echo "  skipped  $path - exists but is not a managed skill directory" >&2
        fi
    fi
}

install_project_agents() { # $1 = target project dir
    local dst="$1/AGENTS.md"
    if [[ ! -f "$template_agents" ]]; then
        echo "  skipped  project AGENTS.md - template not found: $template_agents" >&2
        return 0
    fi
    if [[ -f "$dst" ]]; then
        if cmp -s "$dst" "$template_agents"; then
            cp "$template_agents" "$dst"
            echo "  refreshed $dst"
        else
            echo "  skipped  $dst - exists and differs from the template (merge by hand if you want the template version)" >&2
        fi
        return 0
    fi
    cp "$template_agents" "$dst"
    echo "  installed $dst"
}

remove_project_agents() { # $1 = target project dir
    local dst="$1/AGENTS.md"
    [[ -f "$dst" && -f "$template_agents" ]] || return 0
    if cmp -s "$dst" "$template_agents"; then
        rm "$dst"
        echo "  removed  $dst"
    else
        echo "  kept     $dst - differs from the template" >&2
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
        rmdir "$local_target/.agents" 2>/dev/null || true
    fi
    echo "Done: cleaned managed entries from $target_dir"
else
    echo "Done: $count skills installed to $target_dir ($mode)."
    echo "Restart any running agent session to pick them up."
fi

if [[ "$scope" == "local" ]]; then
    if [[ "$clean" == "1" ]]; then remove_project_agents "$local_target"
    else install_project_agents "$local_target"; fi
fi

# --- Always-on rules (always installed) --------------------------------------
#
# Skills discovery is not intent mapping: OpenCode and VS Code Copilot both
# discover ~/.agents/skills on their own, but neither forces the discipline of
# loading a matching skill before work starts. Each harness has exactly one
# always-on user-level file that can supply that nudge:
#
#   OpenCode  ~/.config/opencode/AGENTS.md          (combined into every session)
#   Copilot   ~/.copilot/copilot-instructions.md    (Agent Host personal, every repository;
#                                                    VS Code Local agent uses profile storage instead)
#
# Both files are installed by default. Each is a copy of setup/AGENTS.md (the
# same template local scope installs at a project root), so the full skill
# discipline - catalog, tool mapping, agents table, precedence - is always on.
# Ownership for refresh/--clean: a file is ours when it still matches the
# template, or when it carries the managed marker (the marker covers files
# written by earlier versions of this script). An existing file that differs
# and has no marker is never overwritten. Plain Markdown, no frontmatter
# required for these always-on files (frontmatter is only for *.instructions.md).

install_rules_file() { # $1 = destination path (a copy of the setup/AGENTS.md template)
    local dst="$1"
    if [[ ! -f "$template_agents" ]]; then
        echo "  skipped  $dst - template not found: $template_agents" >&2
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && ! cmp -s "$dst" "$template_agents" && ! grep -qF "$marker" "$dst" 2>/dev/null; then
        echo "  skipped  $dst - exists and was not created by this script (back it up and remove it first to replace it)" >&2
        return 0
    fi
    cp "$template_agents" "$dst"
    echo "  installed $dst"
}

remove_rules_file() { # $1 = destination path
    local dst="$1"
    [[ -f "$dst" ]] || return 0
    if cmp -s "$dst" "$template_agents" 2>/dev/null || grep -qF "$marker" "$dst" 2>/dev/null; then
        rm "$dst"
        echo "  removed  $dst"
    else
        echo "  kept     $dst - differs from the template" >&2
    fi
}

install_opencode_rules=1
install_copilot_rules=1
if [[ $skip_opencode_rules == "1" ]]; then install_opencode_rules=0; fi
if [[ $skip_copilot_rules == "1" ]]; then install_copilot_rules=0; fi
if [[ "$scope" != "global" ]]; then install_opencode_rules=0; install_copilot_rules=0; fi

local_scope_note="Local scope: user-level rules files not touched (project AGENTS.md installed at the target instead)."

if [[ $install_opencode_rules == "1" || $install_copilot_rules == "1" ]]; then
    if [[ $clean == "1" ]]; then
        echo "Cleaning always-on rules files"
    else
        echo "Installing always-on rules files"
    fi
    if [[ $install_opencode_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_rules_file "$HOME/.config/opencode/AGENTS.md"
        else install_rules_file "$HOME/.config/opencode/AGENTS.md"; fi
    fi
    if [[ $install_copilot_rules == "1" ]]; then
        if [[ $clean == "1" ]]; then remove_rules_file "$HOME/.copilot/copilot-instructions.md"
        else install_rules_file "$HOME/.copilot/copilot-instructions.md"; fi
    fi
elif [[ "$scope" != "global" ]]; then
    echo "  $local_scope_note"
fi

# --- Agents (OpenCode + Copilot) ----------------------------------------------
#
# Canonical agents live in agents/<id>.md (OpenCode format: description +
# mode: subagent + optional permissions). Each is installed per the harness
# answer already given above (no new question): Both installs both copies,
# OpenCode-only / Copilot-only install just theirs.
#
#   Global scope: OpenCode ~/.config/opencode/agents/<id>.md (verbatim) and
#                 Copilot  ~/.copilot/agents/<id>.agent.md (converted).
#   Local scope:  OpenCode <target>/.opencode/agents/<id>.md (verbatim) and
#                 Copilot  <target>/.github/agents/<id>.agent.md (converted).
#
# The Copilot copy keeps `description`, gains a `tools:` array (architect gets
# read/search/edit since it drafts proposals; the read-only reviewers get
# read/search - `search` covers both text and file search; `grep` is not a
# Copilot tool alias), and drops the OpenCode-only `mode`/`permissions` keys;
# the body is unchanged.
#
# Installed file copies carry the managed marker (<!-- agent-hub:managed -->)
# as an HTML comment line right after the frontmatter, so refresh and --clean
# can prove ownership: an existing file without the marker is never
# overwritten or deleted. Link mode installs OpenCode copies as symlinks
# instead (the link itself is proof of ownership); Copilot copies are always
# written files because conversion changes the bytes, so a link to the source
# could not carry the converted frontmatter.

agents_dir="$repo_root/agents"

install_opencode_agents=1
install_copilot_agents=1
if [[ $skip_opencode_rules == "1" ]]; then install_opencode_agents=0; fi
if [[ $skip_copilot_rules == "1" ]]; then install_copilot_agents=0; fi

if [[ "$scope" == "global" ]]; then
    opencode_agents_dir="$HOME/.config/opencode/agents"
    copilot_agents_dir="$HOME/.copilot/agents"
else
    opencode_agents_dir="$local_target/.opencode/agents"
    copilot_agents_dir="$local_target/.github/agents"
fi

agent_tools_for() { # $1 = agent id -> Copilot tools array for the converted copy
    if [[ "$1" == "architect" ]]; then
        echo "['read', 'search', 'edit']"
    else
        echo "['read', 'search']"
    fi
}

agent_description() { # $1 = src file -> value of the description: frontmatter line
    awk '/^description: */ { sub(/^description: */, ""); print; exit }' "$1"
}

agent_body() { # $1 = src file -> everything after the closing --- frontmatter line
    # Only the leading frontmatter counts: a body line of exactly --- (e.g. a
    # Markdown rule) must be kept. Files without leading frontmatter pass
    # through unchanged.
    awk 'NR==1 { if ($0 != "---") { nofm=1 } } nofm { print; next } NR==1 { next } c<1 && $0=="---" { c++; next } 1' "$1"
}

is_managed_agent() { # $1 = path -> true when the path is a symlink or a marked file
    if [[ -L "$1" ]]; then return 0; fi
    if [[ -f "$1" ]] && grep -qF "$marker" "$1"; then return 0; fi
    return 1
}

write_opencode_agent() { # $1 = src, $2 = dst (copy mode: verbatim + marker after frontmatter)
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -d "$dst" && ! -L "$dst" ]]; then
        echo "  skipped  $dst - exists but is not a managed agent file" >&2
        return 0
    fi
    if [[ -f "$dst" && ! -L "$dst" ]] && ! grep -qF "$marker" "$dst"; then
        echo "  skipped  $dst - exists and was not created by this script (back it up and remove it first to replace it)" >&2
        return 0
    fi
    if [[ -L "$dst" ]]; then rm "$dst"; fi
    awk -v marker="$marker" 'NR==1 { if ($0 != "---") { nofm=1; print marker; print "" } print; next } nofm { print; next } c<1 && $0=="---" { print; print marker; c++; next } 1' "$src" > "$dst"
    echo "  installed $dst"
}

write_copilot_agent() { # $1 = src, $2 = dst (always a converted file copy)
    local src="$1" dst="$2" id desc tools
    id="$(basename "$src" .md)"
    mkdir -p "$(dirname "$dst")"
    if [[ -d "$dst" && ! -L "$dst" ]]; then
        echo "  skipped  $dst - exists but is not a managed agent file" >&2
        return 0
    fi
    if [[ -f "$dst" && ! -L "$dst" ]] && ! grep -qF "$marker" "$dst"; then
        echo "  skipped  $dst - exists and was not created by this script (back it up and remove it first to replace it)" >&2
        return 0
    fi
    if [[ -L "$dst" ]]; then rm "$dst"; fi
    desc="$(agent_description "$src")"
    if [[ -z "$desc" ]]; then
        echo "error: agent has no description frontmatter: $src" >&2
        exit 1
    fi
    tools="$(agent_tools_for "$id")"
    {
        printf -- '---\n'
        printf 'description: %s\n' "$desc"
        printf 'tools: %s\n' "$tools"
        printf -- '---\n'
        printf '%s\n' "$marker"
        agent_body "$src"
    } > "$dst"
    echo "  installed $dst"
}

agent_count=0
if [[ $install_opencode_agents == "1" || $install_copilot_agents == "1" ]]; then
    [[ -d "$agents_dir" ]] || { echo "error: agents directory not found: $agents_dir" >&2; exit 1; }
    if [[ "$clean" == "1" ]]; then
        echo "Cleaning managed agents"
    else
        echo "Installing agents"
    fi
    if [[ "$clean" == "0" ]]; then
        agent_srcs=( "$agents_dir"/*.md )
        if [[ ${#agent_srcs[@]} -eq 0 ]] || [[ ${#agent_srcs[@]} -eq 1 && ! -f "${agent_srcs[0]:-}" ]]; then
            echo "error: no agents found in $agents_dir" >&2
            exit 1
        fi
    fi
    for src in "$agents_dir"/*.md; do
        [[ -f "$src" ]] || continue
        id="$(basename "$src" .md)"
        if [[ $install_opencode_agents == "1" ]]; then
            dst="$opencode_agents_dir/$id.md"
            if [[ "$clean" == "1" ]]; then
                remove_managed "$dst"
            elif [[ "$mode" == "link" && -L "$dst" && -e "$dst" ]]; then
                echo "  linked   $dst (already current)"
                agent_count=$((agent_count + 1))
            elif [[ "$mode" == "link" ]]; then
                remove_managed "$dst"
                if [[ -e "$dst" || -L "$dst" ]]; then
                    echo "  skipped  $dst - exists and was not created by this script" >&2
                else
                    mkdir -p "$(dirname "$dst")"
                    ln -s "$src" "$dst"
                    echo "  linked   $dst -> $src"
                    agent_count=$((agent_count + 1))
                fi
            else
                write_opencode_agent "$src" "$dst"
                if is_managed_agent "$dst"; then agent_count=$((agent_count + 1)); fi
            fi
        fi
        if [[ $install_copilot_agents == "1" ]]; then
            dst="$copilot_agents_dir/$id.agent.md"
            if [[ "$clean" == "1" ]]; then
                remove_managed "$dst"
            else
                write_copilot_agent "$src" "$dst"
                if is_managed_agent "$dst"; then agent_count=$((agent_count + 1)); fi
            fi
        fi
    done
    if [[ "$clean" == "1" ]]; then
        if [[ $install_opencode_agents == "1" ]]; then rmdir "$opencode_agents_dir" 2>/dev/null || true; fi
        if [[ $install_copilot_agents == "1" ]]; then rmdir "$copilot_agents_dir" 2>/dev/null || true; fi
        echo "Done: cleaned managed agents"
    else
        echo "Done: $agent_count agent files installed ($mode)."
    fi
fi
