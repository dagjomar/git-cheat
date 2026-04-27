#!/usr/bin/env bash
# git-cheat — build a cheat sheet from git aliases and comments
#
# Usage:
#   git cheat
#   git cheat config add <folder>
#   git cheat config remove <folder>
#   git cheat export <md|html> [output-file]
#
# Inclusion rule:
#   Aliases are included only when a comment directly above them starts with:
#     cheat
#     cheat: <description>
#
# Config file:
#   ~/.config/git-cheat/config   (or $XDG_CONFIG_HOME/git-cheat/config)

set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Globals ────────────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git-cheat"
CONFIG_FILE="$CONFIG_DIR/config"

INCLUDE_GLOBAL=true
PROJECT_PATHS=()

# ── Helpers ────────────────────────────────────────────────────────────────────
die()  { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
ok()   { echo -e "${GREEN}✓${RESET} $*" >&2; }
warn() { echo -e "${YELLOW}warning:${RESET} $*" >&2; }

global_gitconfig_path() {
  if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
    printf '%s\n' "$GIT_CONFIG_GLOBAL"
    return 0
  fi
  printf '%s/.gitconfig\n' "$HOME"
}

suggest_open_command() {
  local target="$1"
  if command -v open >/dev/null 2>&1; then
    echo -e "  ${CYAN}Open with:${RESET} open \"$target\"" >&2
  elif command -v xdg-open >/dev/null 2>&1; then
    echo -e "  ${CYAN}Open with:${RESET} xdg-open \"$target\"" >&2
  fi
}

open_file_in_default_editor() {
  local target_file="$1"
  mkdir -p "$(dirname "$target_file")"
  [ -f "$target_file" ] || touch "$target_file"

  local editor_cmd="${VISUAL:-${EDITOR:-}}"
  if [ -n "$editor_cmd" ]; then
    sh -c "$editor_cmd \"\$1\"" _ "$target_file"
    return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open -t "$target_file"
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$target_file"
    return 0
  fi

  if command -v nano >/dev/null 2>&1; then
    nano "$target_file"
    return 0
  fi

  vi "$target_file"
}

usage() {
  cat << 'EOF'
git-cheat — generate a cheat sheet from git aliases

Usage:
  git cheat                       Show this help
  git cheat show                  Render your cheat sheet in the terminal
  git cheat edit                  Guided setup helper (open global config, etc.)
  git cheat configure             Print config location and setup guidance
  git cheat config init           Create the config file if missing
  git cheat config add <folder>   Include a project repo's local aliases
  git cheat config remove <folder>
  git cheat config list           Show current config
  git cheat config path           Print the config file path
  git cheat export <md|html> [output-file]
  git cheat help                  Show this help

Notes:
  - Aliases are included only when marked with a cheat comment:
      # cheat
      # cheat: description
  - Global aliases are included by default.
  - Add project folders to include their local .git/config aliases.
  - First time? Run `git cheat edit` for a guided setup flow.
EOF
}

config_usage() {
  cat << 'EOF'
Usage:
  git cheat config init
  git cheat config add <folder>
  git cheat config remove <folder>
  git cheat config list
  git cheat config path
EOF
}

to_abs_path() {
  local input="$1"
  if [ -d "$input" ]; then
    (cd "$input" && pwd)
    return 0
  fi

  if [ -e "$input" ]; then
    local parent
    parent=$(cd "$(dirname "$input")" && pwd)
    printf '%s/%s\n' "$parent" "$(basename "$input")"
    return 0
  fi

  case "$input" in
    /*) printf '%s\n' "$input" ;;
    *) printf '%s/%s\n' "$(pwd)" "$input" ;;
  esac
}

ensure_config() {
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
# git-cheat config (v1)
# include_global: include aliases from ~/.gitconfig
include_global=true

# Add one project repo path per line:
# project=/absolute/path/to/repo
EOF
  fi
}

load_config() {
  INCLUDE_GLOBAL=true
  PROJECT_PATHS=()

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    local line="$raw_line"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    case "$line" in
      ""|\#*|\;*)
        continue
        ;;
      include_global=*)
        local value="${line#include_global=}"
        case "$value" in
          true|1|yes|on) INCLUDE_GLOBAL=true ;;
          false|0|no|off) INCLUDE_GLOBAL=false ;;
          *) warn "invalid include_global value '$value' in $CONFIG_FILE (using true)" ;;
        esac
        ;;
      project=*)
        local path="${line#project=}"
        [ -n "$path" ] && PROJECT_PATHS+=("$path")
        ;;
      *)
        warn "ignoring unknown config line: $line"
        ;;
    esac
  done < "$CONFIG_FILE"
}

config_has_project() {
  local needle="$1"
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    local line="$raw_line"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ "$line" = "project=$needle" ] && return 0
  done < "$CONFIG_FILE"
  return 1
}

resolve_repo_config_path() {
  local repo_path="$1"
  local git_dir

  git_dir=$(git -C "$repo_path" rev-parse --git-dir 2>/dev/null || true)
  [ -n "$git_dir" ] || return 1

  case "$git_dir" in
    /*) printf '%s/config\n' "$git_dir" ;;
    *) printf '%s/%s/config\n' "$repo_path" "$git_dir" ;;
  esac
}

parse_cheat_aliases() {
  local config_path="$1"

  awk '
    function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
    function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
    function trim(s)  { return rtrim(ltrim(s)) }

    BEGIN {
      in_alias = 0
      pending_comment = ""
    }

    {
      line = $0

      if (line ~ /^[ \t]*\[/) {
        if (line ~ /^[ \t]*\[alias\][ \t]*$/) {
          in_alias = 1
        } else {
          in_alias = 0
        }
        pending_comment = ""
        next
      }

      if (!in_alias) {
        next
      }

      if (line ~ /^[ \t]*$/) {
        pending_comment = ""
        next
      }

      if (line ~ /^[ \t]*[#;]/) {
        pending_comment = line
        sub(/^[ \t]*[#;][ \t]*/, "", pending_comment)
        pending_comment = trim(pending_comment)
        next
      }

      if (line ~ /^[ \t]*[A-Za-z0-9._-]+[ \t]*=[ \t]*.*$/) {
        alias_name = line
        sub(/^[ \t]*/, "", alias_name)
        sub(/[ \t]*=.*/, "", alias_name)

        alias_cmd = line
        sub(/^[^=]*=[ \t]*/, "", alias_cmd)
        alias_cmd = trim(alias_cmd)
        include = 0
        desc = ""

        if (pending_comment ~ /^cheat([[:space:]]*:[[:space:]]*.*)?$/) {
          include = 1
          desc = pending_comment
          sub(/^cheat[[:space:]]*:[[:space:]]*/, "", desc)
          if (desc == "cheat") {
            desc = ""
          }
        } else if (pending_comment ~ /^cheat[[:space:]]+.+$/) {
          include = 1
          desc = pending_comment
          sub(/^cheat[[:space:]]+/, "", desc)
        }

        if (include) {
          gsub(/\t/, "    ", alias_name)
          gsub(/\t/, "    ", alias_cmd)
          gsub(/\t/, "    ", desc)
          print alias_name "\t" alias_cmd "\t" desc
        }

        pending_comment = ""
        next
      }

      pending_comment = ""
    }
  ' "$config_path"
}

append_alias_rows_for_source() {
  local section_name="$1"
  local source_label="$2"
  local source_config_path="$3"
  local output_file="$4"

  while IFS=$'\t' read -r alias_name alias_cmd alias_desc; do
    [ -n "$alias_name" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$section_name" \
      "$source_label" \
      "$alias_name" \
      "$alias_cmd" \
      "$alias_desc" >> "$output_file"
  done < <(parse_cheat_aliases "$source_config_path")
}

collect_alias_rows() {
  local output_file="$1"
  : > "$output_file"

  ensure_config
  load_config

  if [ "$INCLUDE_GLOBAL" = true ]; then
    if [ -f "$HOME/.gitconfig" ]; then
      append_alias_rows_for_source "Global / User aliases" "$HOME/.gitconfig" "$HOME/.gitconfig" "$output_file"
    else
      warn "global git config not found at $HOME/.gitconfig"
    fi
  fi

  local project
  for project in "${PROJECT_PATHS[@]+"${PROJECT_PATHS[@]}"}"; do
    if [ ! -d "$project" ]; then
      warn "skipping missing project path: $project"
      continue
    fi

    local project_config
    if ! project_config=$(resolve_repo_config_path "$project"); then
      warn "skipping non-git directory: $project"
      continue
    fi

    if [ ! -f "$project_config" ]; then
      warn "skipping project without config file: $project"
      continue
    fi

    local project_name
    project_name=$(basename "$project")
    append_alias_rows_for_source "Project aliases: $project_name" "$project" "$project_config" "$output_file"
  done
}

show_no_alias_message() {
  cat << 'EOF'
No cheat-marked aliases found.

Mark aliases in your git config like this:

[alias]
    # cheat: Compact status output
    st = status -sb

Then run `git cheat` again.
EOF
}

render_terminal_sheet() {
  local rows_file="$1"

  if [ ! -s "$rows_file" ]; then
    show_no_alias_message
    return 0
  fi

  echo -e "${BOLD}Git Cheat Sheet${RESET}"
  echo

  local current_section=""
  while IFS=$'\t' read -r section source alias_name alias_cmd alias_desc; do
    if [ "$section" != "$current_section" ]; then
      [ -n "$current_section" ] && echo
      echo -e "${BOLD}${section}${RESET}"
      echo "  source: $source"
      current_section="$section"
    fi

    if [ -n "$alias_desc" ]; then
      printf '  %-14s - %s\n' "$alias_name" "$alias_desc"
    else
      printf '  %s\n' "$alias_name"
    fi
  done < "$rows_file"
}

escape_html() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g'
}

write_markdown_output() {
  local rows_file="$1"
  local output_file="$2"

  {
    echo "# Git Cheat Sheet"
    echo

    local current_section=""
    while IFS=$'\t' read -r section source alias_name alias_cmd alias_desc; do
      if [ "$section" != "$current_section" ]; then
        [ -n "$current_section" ] && echo
        echo "## $section"
        echo
        echo "- Source: \`$source\`"
        echo
        current_section="$section"
      fi

      if [ -n "$alias_desc" ]; then
        echo "- \`$alias_name\` — $alias_desc"
      else
        echo "- \`$alias_name\`"
      fi
    done < "$rows_file"
  } > "$output_file"
}

write_html_output() {
  local rows_file="$1"
  local output_file="$2"

  {
    cat << 'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Git Cheat Sheet</title>
  <style>
    @page { margin: 1.2cm; }

    *, *::before, *::after { box-sizing: border-box; }

    html {
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
      color-adjust: exact;
    }

    body {
      margin: 0;
      padding: 2.5rem 1rem 1.5rem;
      background: #ffffff;
      color: #0f172a;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
                   "Helvetica Neue", Arial, sans-serif;
      line-height: 1.5;
      font-size: 16px;
    }

    .card {
      position: relative;
      max-width: 980px;
      margin: 0 auto;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 18px;
      padding: 2.5rem 2.5rem 2rem;
      overflow: hidden;
    }

    .card::before {
      content: "";
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 6px;
      background: linear-gradient(90deg, #3b82f6 0%, #8b5cf6 50%, #ec4899 100%);
    }

    .card__header {
      display: flex;
      align-items: center;
      gap: 0.85rem;
      margin-bottom: 1.5rem;
    }

    .card__icon {
      flex: 0 0 auto;
      width: 44px;
      height: 44px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: #dbeafe;
      color: #1e3a8a;
      border-radius: 12px;
    }

    .card__icon svg { width: 26px; height: 26px; }

    h1 {
      margin: 0;
      font-size: 1.875rem;
      font-weight: 700;
      letter-spacing: -0.015em;
      color: #0f172a;
      line-height: 1.15;
    }

    .sections {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 1.4rem 1.5rem;
    }

    section {
      background: #ffffff;
      border: 1px solid #e2e8f0;
      border-radius: 14px;
      padding: 1.1rem 1.2rem 0.6rem;
      break-inside: avoid;
      page-break-inside: avoid;
    }

    .section__title {
      margin: 0 0 0.1rem;
      font-size: 1.05rem;
      font-weight: 700;
      color: #1e293b;
      letter-spacing: -0.005em;
    }

    .section__source {
      margin: 0 0 0.85rem;
      font-size: 0.75rem;
      color: #94a3b8;
    }

    .section__source code {
      background: transparent;
      color: #64748b;
      padding: 0;
      font-size: 0.75rem;
    }

    ul.aliases {
      list-style: none;
      margin: 0;
      padding: 0;
    }

    ul.aliases li {
      display: flex;
      align-items: baseline;
      gap: 0.75rem;
      padding: 0.4rem 0;
      border-top: 1px solid #f1f5f9;
    }

    ul.aliases li:first-child { border-top: none; padding-top: 0.2rem; }

    .alias {
      display: inline-block;
      flex: 0 0 auto;
      min-width: 4rem;
      text-align: center;
      background: #dbeafe;
      color: #1e3a8a;
      padding: 0.18rem 0.55rem;
      border-radius: 6px;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco,
                   Consolas, monospace;
      font-size: 0.8125rem;
      font-weight: 600;
      white-space: nowrap;
    }

    .desc {
      color: #475569;
      font-size: 0.9rem;
    }

    code {
      background: #eef2f7;
      color: #334155;
      border-radius: 4px;
      padding: 0.1rem 0.35rem;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco,
                   Consolas, monospace;
      font-size: 0.8125rem;
    }

    .card__footer {
      margin-top: 1.75rem;
      padding-top: 1rem;
      border-top: 1px solid #e2e8f0;
      text-align: center;
      font-size: 0.78rem;
      color: #94a3b8;
      letter-spacing: 0.01em;
    }

    .card__footer a {
      color: #3b82f6;
      text-decoration: none;
      font-weight: 600;
    }

    .card__footer a:hover { text-decoration: underline; }

    @media print {
      body { background: #ffffff; padding: 0; font-size: 11pt; }

      .card {
        background: #f8fafc !important;
        border: 1px solid #e2e8f0 !important;
        border-radius: 14px;
        padding: 1.5rem 1.4rem 1.1rem;
        max-width: 100%;
      }

      .card::before {
        background: linear-gradient(90deg, #3b82f6 0%, #8b5cf6 50%, #ec4899 100%) !important;
      }

      .card__icon {
        background: #dbeafe !important;
        color: #1e3a8a !important;
      }

      .sections {
        grid-template-columns: repeat(2, 1fr);
        gap: 0.9rem;
      }

      section {
        background: #ffffff !important;
        border: 1px solid #e2e8f0 !important;
        padding: 0.9rem 1rem 0.5rem;
      }

      .alias {
        background: #dbeafe !important;
        color: #1e3a8a !important;
      }

      code {
        background: #eef2f7 !important;
        color: #334155 !important;
      }
    }
  </style>
</head>
<body>
  <main class="card">
    <header class="card__header">
      <span class="card__icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="6" cy="6" r="2.5"/>
          <circle cx="18" cy="18" r="2.5"/>
          <circle cx="6" cy="18" r="2.5"/>
          <path d="M6 8.5v7"/>
          <path d="M8.5 6h6a3 3 0 0 1 3 3v6.5"/>
        </svg>
      </span>
      <h1>Git Cheat Sheet</h1>
    </header>
    <div class="sections">
HTML_HEAD

    local current_section=""
    while IFS=$'\t' read -r section source alias_name alias_cmd alias_desc; do
      if [ "$section" != "$current_section" ]; then
        if [ -n "$current_section" ]; then
          echo '      </ul>'
          echo '    </section>'
        fi

        echo '    <section>'
        echo "      <h2 class=\"section__title\">$(escape_html "$section")</h2>"
        echo "      <p class=\"section__source\">Source: <code>$(escape_html "$source")</code></p>"
        echo '      <ul class="aliases">'
        current_section="$section"
      fi

      local alias_html
      alias_html="<span class=\"alias\">$(escape_html "$alias_name")</span>"
      if [ -n "$alias_desc" ]; then
        echo "        <li>${alias_html}<span class=\"desc\">$(escape_html "$alias_desc")</span></li>"
      else
        echo "        <li>${alias_html}</li>"
      fi
    done < "$rows_file"

    if [ -n "$current_section" ]; then
      echo '      </ul>'
      echo '    </section>'
    fi

    cat << 'HTML_FOOT'
    </div>
    <footer class="card__footer">
      Created with <a href="https://github.com/dagjomar/git-cheat">dagjomar/git-cheat</a>
    </footer>
  </main>
</body>
</html>
HTML_FOOT
  } > "$output_file"
}

cmd_show() {
  local rows_file
  rows_file=$(mktemp)
  collect_alias_rows "$rows_file"
  render_terminal_sheet "$rows_file"
  rm -f "$rows_file"
}

cmd_config_init() {
  ensure_config
  ok "Config initialized: $CONFIG_FILE"
}

cmd_config_add() {
  local folder="${1:-}"
  [ -n "$folder" ] || die "usage: git cheat config add <folder>"

  local abs_path
  abs_path=$(to_abs_path "$folder")
  [ -d "$abs_path" ] || die "directory does not exist: $folder"

  if ! git -C "$abs_path" rev-parse --git-dir >/dev/null 2>&1; then
    die "not a git repository: $abs_path"
  fi

  ensure_config
  if config_has_project "$abs_path"; then
    warn "project already in config: $abs_path"
    return 0
  fi

  printf 'project=%s\n' "$abs_path" >> "$CONFIG_FILE"
  ok "Added project: $abs_path"
}

cmd_config_remove() {
  local folder="${1:-}"
  [ -n "$folder" ] || die "usage: git cheat config remove <folder>"

  ensure_config

  local abs_path
  abs_path=$(to_abs_path "$folder")

  local tmp_file
  tmp_file=$(mktemp)
  local removed=0

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    local line="$raw_line"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    if [ "$line" = "project=$abs_path" ]; then
      removed=1
      continue
    fi

    printf '%s\n' "$raw_line" >> "$tmp_file"
  done < "$CONFIG_FILE"

  mv "$tmp_file" "$CONFIG_FILE"

  if [ "$removed" -eq 1 ]; then
    ok "Removed project: $abs_path"
  else
    warn "project not found in config: $abs_path"
  fi
}

cmd_config_list() {
  ensure_config
  load_config

  echo "Config file: $CONFIG_FILE"
  echo "include_global=$INCLUDE_GLOBAL"

  if [ "${#PROJECT_PATHS[@]}" -eq 0 ]; then
    echo "projects=(none)"
    return 0
  fi

  echo "projects:"
  local i=1
  local project
  for project in "${PROJECT_PATHS[@]}"; do
    echo "  $i. $project"
    i=$((i + 1))
  done
}

cmd_config_path() {
  ensure_config
  echo "$CONFIG_FILE"
}

cmd_configure() {
  ensure_config
  cat << EOF
Config ready at:
  $CONFIG_FILE
Open a guided setup helper with:
  git cheat edit

Add project repos with:
  git cheat config add /path/to/repo

Or edit manually and add lines like:
  project=/absolute/path/to/repo
EOF
}

cmd_edit() {
  ensure_config
  load_config

  local global_config
  global_config=$(global_gitconfig_path)

  echo "Git Cheat setup helper"
  echo
  echo "Global git config:"
  echo "  path: $global_config"
  if [ -f "$global_config" ]; then
    echo "  status: found"
  else
    echo "  status: not found (it will be created when you save)"
  fi

  echo
  echo "Quick edit commands:"
  if [ -n "${VISUAL:-}" ]; then
    echo "  ${VISUAL} \"$global_config\""
  elif [ -n "${EDITOR:-}" ]; then
    echo "  ${EDITOR} \"$global_config\""
  else
    echo "  nano \"$global_config\""
    if command -v open >/dev/null 2>&1; then
      echo "  open -t \"$global_config\""
    fi
  fi

  echo
  echo "Mark aliases like this:"
  cat << 'EOF'
[alias]
    # cheat: Compact status output
    st = status -sb
EOF

  echo
  echo "Configured project sources:"
  if [ "${#PROJECT_PATHS[@]}" -eq 0 ]; then
    echo "  - none configured"
    echo "  - add one with: git cheat config add /path/to/repo"
  else
    local idx=1
    local project
    for project in "${PROJECT_PATHS[@]}"; do
      echo "  $idx. $project"
      if [ -d "$project" ]; then
        local project_config
        if project_config=$(resolve_repo_config_path "$project" 2>/dev/null); then
          if [ -f "$project_config" ]; then
            echo "     local config: $project_config"
          else
            echo "     local config: missing"
          fi
        else
          echo "     local config: not a git repository"
        fi
      else
        echo "     local config: path does not exist"
      fi
      idx=$((idx + 1))
    done
  fi

  if [ "${GIT_CHEAT_NO_PROMPT:-0}" = "1" ]; then
    return 0
  fi

  if [ ! -e /dev/tty ] || [ ! -r /dev/tty ]; then
    return 0
  fi

  local answer=""
  read -r -p "Open global git config in your default editor now? [y/N] " answer < /dev/tty || true
  case "$answer" in
    y|Y|yes|YES)
      open_file_in_default_editor "$global_config"
      ;;
  esac
}

cmd_export() {
  local format="${1:-}"
  local output_file="${2:-}"
  [ -n "$format" ] || die "usage: git cheat export <md|html> [output-file]"

  local rows_file
  rows_file=$(mktemp)
  collect_alias_rows "$rows_file"

  if [ ! -s "$rows_file" ]; then
    rm -f "$rows_file"
    show_no_alias_message
    return 0
  fi

  case "$format" in
    md|markdown)
      output_file="${output_file:-git-cheat-sheet.md}"
      write_markdown_output "$rows_file" "$output_file"
      ok "Markdown cheat sheet written: $output_file"
      ;;
    html)
      output_file="${output_file:-git-cheat-sheet.html}"
      write_html_output "$rows_file" "$output_file"
      ok "HTML cheat sheet written: $output_file"
      suggest_open_command "$output_file"
      ;;
    *)
      rm -f "$rows_file"
      die "unknown export format '$format' (use md or html)"
      ;;
  esac

  rm -f "$rows_file"
}

main() {
  local command="${1:-}"

  case "$command" in
    "")
      usage
      ;;
    show)
      cmd_show
      ;;
    configure)
      cmd_configure
      ;;
    edit)
      cmd_edit
      ;;
    config)
      shift || true
      local subcommand="${1:-list}"
      case "$subcommand" in
        init)
          cmd_config_init
          ;;
        add)
          shift || true
          cmd_config_add "${1:-}"
          ;;
        remove|rm)
          shift || true
          cmd_config_remove "${1:-}"
          ;;
        list|ls)
          cmd_config_list
          ;;
        path)
          cmd_config_path
          ;;
        --help|-h|help)
          config_usage
          ;;
        *)
          die "unknown config command '$subcommand'"
          ;;
      esac
      ;;
    export)
      shift || true
      cmd_export "${1:-}" "${2:-}"
      ;;
    --help|-h|help)
      usage
      ;;
    *)
      die "unknown command '$command' (run: git cheat --help)"
      ;;
  esac
}

main "$@"
