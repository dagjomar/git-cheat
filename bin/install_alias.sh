#!/usr/bin/env bash
# Installs 'git cheat' as a global git alias pointing to this script.
# Also drops a `# cheat: ...` marker comment above the alias so that
# `git cheat show` includes the cheat command itself.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CHEAT_SCRIPT="$SCRIPT_DIR/git-cheat.sh"
MARKER_TEXT="cheat: cheat sheet generator"

global_gitconfig_path() {
  if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
    printf '%s\n' "$GIT_CONFIG_GLOBAL"
    return 0
  fi
  printf '%s/.gitconfig\n' "$HOME"
}

ensure_cheat_marker_comment() {
  local config_file="$1"
  local marker="$2"
  [ -f "$config_file" ] || return 0

  local tmp
  tmp=$(mktemp)

  awk -v marker="$marker" '
    BEGIN { in_alias = 0; prev_was_marker = 0 }
    {
      if ($0 ~ /^[[:space:]]*\[/) {
        in_alias = ($0 ~ /^[[:space:]]*\[alias\][[:space:]]*$/)
        prev_was_marker = 0
        print
        next
      }
      if (in_alias && $0 ~ /^[[:space:]]*cheat[[:space:]]*=/ && !prev_was_marker) {
        print "\t# " marker
      }
      print
      if ($0 ~ /^[[:space:]]*[#;][[:space:]]*cheat([[:space:]:].*)?$/) {
        prev_was_marker = 1
      } else {
        prev_was_marker = 0
      }
    }
  ' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
}

chmod +x "$CHEAT_SCRIPT"

git config --global alias.cheat "!bash $CHEAT_SCRIPT"
ensure_cheat_marker_comment "$(global_gitconfig_path)" "$MARKER_TEXT"

echo "✅ Git alias 'cheat' installed successfully!"
echo "You can now use 'git cheat' from any git repository"
echo
echo "Examples:"
echo "  git cheat"
echo "  git cheat config add /path/to/project"
echo "  git cheat export html ./git-cheat-sheet.html"
