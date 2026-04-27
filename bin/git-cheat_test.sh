#!/usr/bin/env bash
#
# git-cheat_test.sh — integration tests for git-cheat
#
# Usage:
#   ./bin/git-cheat_test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHEAT_SCRIPT="$SCRIPT_DIR/git-cheat.sh"

pass() { echo "✅ $1"; }
fail() { echo "❌ Test failed: $1"; exit 1; }

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if echo "$haystack" | grep -Fq "$needle"; then
    pass "$message"
  else
    echo "❌ $message"
    echo "   Expected to find: '$needle'"
    echo "   In output:        '$haystack'"
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if echo "$haystack" | grep -Fq "$needle"; then
    echo "❌ $message"
    echo "   Expected NOT to find: '$needle'"
    echo "   In output:            '$haystack'"
    exit 1
  else
    pass "$message"
  fi
}

assert_file_exists() {
  local file="$1"
  local message="$2"
  if [ -f "$file" ]; then
    pass "$message"
  else
    echo "❌ $message"
    echo "   File not found: '$file'"
    exit 1
  fi
}

run_cheat() {
  HOME="$TEST_HOME" bash "$CHEAT_SCRIPT" "$@"
}

TEST_DIR=$(mktemp -d)
TEST_HOME="$TEST_DIR/home"
PROJECT_DIR="$TEST_DIR/project-repo"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME"

echo
echo "=== git-cheat tests ==="
echo

echo "── Test: global aliases are read from ~/.gitconfig ─────────────────────────"
cat > "$TEST_HOME/.gitconfig" << 'EOF'
[alias]
    # cheat: Compact status output
    st = status -sb
    co = checkout
EOF

default_output=$(run_cheat)
assert_contains "$default_output" "git-cheat — generate a cheat sheet" "Bare 'git cheat' shows help"
assert_contains "$default_output" "git cheat show" "Help points users at 'git cheat show'"
assert_not_contains "$default_output" "Git Cheat Sheet" "Bare 'git cheat' does not render the sheet"

output=$(run_cheat show)
assert_contains "$output" "Git Cheat Sheet" "Shows cheat sheet header"
assert_contains "$output" "st" "Includes cheat-marked global alias"
assert_contains "$output" "Compact status output" "Shows alias description from cheat comment"
assert_not_contains "$output" "status -sb" "Hides raw alias command from output"
assert_not_contains "$output" "checkout" "Excludes unmarked global alias"

echo "── Test: add project repo and include local aliases ────────────────────────"
mkdir -p "$PROJECT_DIR"
git -C "$PROJECT_DIR" init >/dev/null
git -C "$PROJECT_DIR" config user.email "test@example.com"
git -C "$PROJECT_DIR" config user.name "Test User"

cat >> "$PROJECT_DIR/.git/config" << 'EOF'
[alias]
    # cheat: Pull latest and rebase
    plr = pull --rebase
    lg = log --oneline
EOF

run_cheat config add "$PROJECT_DIR" >/dev/null
output=$(run_cheat show)
assert_contains "$output" "Project aliases: project-repo" "Shows project section"
assert_contains "$output" "plr" "Includes cheat-marked project alias"
assert_not_contains "$output" "log --oneline" "Excludes unmarked project alias"

echo "── Test: config list includes added project ────────────────────────────────"
config_list=$(run_cheat config list)
assert_contains "$config_list" "$PROJECT_DIR" "Config list shows added project path"

echo "── Test: markdown/html export ───────────────────────────────────────────────"
MD_OUT="$TEST_DIR/out.md"
HTML_OUT="$TEST_DIR/out.html"

run_cheat export md "$MD_OUT" >/dev/null
html_export_log=$(run_cheat export html "$HTML_OUT" 2>&1 >/dev/null)

assert_file_exists "$MD_OUT" "Markdown export file created"
assert_file_exists "$HTML_OUT" "HTML export file created"
assert_contains "$html_export_log" "Open with:" "HTML export suggests an open command"
assert_contains "$html_export_log" "$HTML_OUT" "HTML export hint references the output file"

md_content=$(cat "$MD_OUT")
html_content=$(cat "$HTML_OUT")
assert_contains "$md_content" "Git Cheat Sheet" "Markdown export contains heading"
assert_contains "$md_content" "plr" "Markdown export contains project alias"
assert_contains "$html_content" "<!doctype html>" "HTML export contains document preamble"
assert_contains "$html_content" "Project aliases: project-repo" "HTML export contains project section"
assert_contains "$html_content" 'class="card"' "HTML export wraps content in a card"
assert_contains "$html_content" 'class="alias"' "HTML export uses alias chip class"
assert_contains "$html_content" "print-color-adjust" "HTML export preserves backgrounds when printing"
assert_contains "$html_content" 'class="sections"' "HTML export uses multi-column section grid"
assert_contains "$html_content" "dagjomar/git-cheat" "HTML export includes attribution footer"

echo "── Test: edit command surfaces global config + project list ────────────────"
edit_output=$(GIT_CHEAT_NO_PROMPT=1 run_cheat edit)
assert_contains "$edit_output" "Git Cheat setup helper" "Edit command shows helper banner"
assert_contains "$edit_output" "$TEST_HOME/.gitconfig" "Edit command shows global git config path"
assert_contains "$edit_output" "status: found" "Edit command reports global config exists"
assert_contains "$edit_output" "Mark aliases like this" "Edit command shows marker example"
assert_contains "$edit_output" "$PROJECT_DIR" "Edit command lists configured project"

echo "── Test: edit command honours \$EDITOR for quick edit hint ──────────────────"
edit_with_editor=$(EDITOR="code -w" GIT_CHEAT_NO_PROMPT=1 run_cheat edit)
assert_contains "$edit_with_editor" "code -w" "Edit command suggests \$EDITOR command"

echo "── Test: edit reports missing global config gracefully ─────────────────────"
NO_CONFIG_HOME="$TEST_DIR/empty-home"
mkdir -p "$NO_CONFIG_HOME"
edit_missing=$(HOME="$NO_CONFIG_HOME" GIT_CHEAT_NO_PROMPT=1 bash "$CHEAT_SCRIPT" edit)
assert_contains "$edit_missing" "status: not found" "Edit command reports missing global config"
assert_contains "$edit_missing" "none configured" "Edit command says no projects configured when empty"

echo "── Test: remove project ─────────────────────────────────────────────────────"
run_cheat config remove "$PROJECT_DIR" >/dev/null
output=$(run_cheat show)
assert_not_contains "$output" "Project aliases: project-repo" "Project section removed after config remove"

echo "── Test: --help mentions edit command ───────────────────────────────────────"
help_output=$(run_cheat --help)
assert_contains "$help_output" "git cheat edit" "Help text advertises edit command"

echo "── Test: install_alias.sh adds cheat marker comment ────────────────────────"
INSTALL_HOME="$TEST_DIR/install-home"
mkdir -p "$INSTALL_HOME"
HOME="$INSTALL_HOME" bash "$SCRIPT_DIR/install_alias.sh" >/dev/null
install_config="$INSTALL_HOME/.gitconfig"
assert_file_exists "$install_config" "Installer creates global git config"
gitconfig_after=$(cat "$install_config")
assert_contains "$gitconfig_after" "cheat = !bash" "Installer adds cheat alias"
assert_contains "$gitconfig_after" "# cheat: cheat sheet generator" "Installer adds cheat marker comment"

# After install, 'git cheat show' against the installed config should list 'cheat' itself
post_install_output=$(HOME="$INSTALL_HOME" bash "$CHEAT_SCRIPT" show)
assert_contains "$post_install_output" "cheat sheet generator" "Installed alias shows up in 'git cheat show'"

echo "── Test: install_alias.sh re-run does not duplicate marker ─────────────────"
HOME="$INSTALL_HOME" bash "$SCRIPT_DIR/install_alias.sh" >/dev/null
marker_count=$(grep -c "cheat: cheat sheet generator" "$install_config" || true)
if [ "$marker_count" = "1" ]; then
  pass "Re-running installer does not duplicate marker comment"
else
  fail "Expected exactly 1 marker comment, got $marker_count"
fi

echo
echo "🎉 All tests passed!"
echo
