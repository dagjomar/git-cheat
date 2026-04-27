# Git Cheat
## A lightweight CLI cheat sheet generator for your favorite git aliases

Git Cheat turns your git alias config into a cheat sheet you can read in the terminal or export to markdown or html.

It is designed for exactly the workflow you described:
- Use git config as source of truth
- Keep docs close to aliases via comments
- Include global aliases and selected project-local aliases
- Keep a small local config of which project folders to include

## v1 scope

This first version keeps things intentionally simple:
- One cheat-sheet set
- Global aliases included by default
- Add/remove project folders to include local aliases
- Aliases are included when tagged with a `cheat` comment

## How alias inclusion works

Only aliases with a `cheat` marker comment immediately above the alias line are shown.

Example:

```ini
[alias]
    # cheat: Compact status output
    st = status -sb

    # cheat: Pretty one-line graph
    lg = log --graph --oneline --decorate --all

    # Not included (no cheat marker)
    co = checkout
```

Supported marker forms:
- `# cheat`
- `# cheat: description`
- `; cheat`
- `; cheat: description`

The optional description is shown in output.

## Installation

Clone and install alias:

```bash
git clone https://github.com/yourusername/git-cheat.git
cd git-cheat
./bin/install_alias.sh
```

The installer also writes a `# cheat: cheat sheet generator` marker comment
above the alias in your global git config so that `git cheat show` includes
the `cheat` command itself — try it right after install. Re-running the
installer is safe: the comment is only added if it isn't already there.

Manual alias setup:

```bash
git config --global alias.cheat '!bash /path/to/git-cheat/bin/git-cheat.sh'
```

## Usage

- Show help (this is also what bare `git cheat` does):

```bash
git cheat
git cheat help
```

- Render your cheat sheet in the terminal:

```bash
git cheat show
```

- Show config path and setup guidance:

```bash
git cheat configure
```

- Guided setup helper (recommended after first install):

```bash
git cheat edit
```

`git cheat edit` shows where your global git config lives, prints the right
edit command for your `$EDITOR`/`$VISUAL`, lists every project repo you have
already added, and offers to open the global config in your default editor so
you can start adding `# cheat: ...` markers right away.

Set `GIT_CHEAT_NO_PROMPT=1` to suppress the interactive prompt (useful in
scripts and CI).

- Add a project repo whose local aliases should be included:

```bash
git cheat config add /path/to/project
```

- Remove a project repo:

```bash
git cheat config remove /path/to/project
```

- List current config:

```bash
git cheat config list
```

- Export:

```bash
git cheat export md ./git-cheat-sheet.md
git cheat export html ./git-cheat-sheet.html
```

Notes:
- If output path is omitted, defaults (`git-cheat-sheet.md` / `git-cheat-sheet.html`) are used in the current directory.
- After an html export the script prints the right `open` command for your platform so you can preview it immediately.

## Config file format

Default config file path:

`~/.config/git-cheat/config`

Example:

```bash
# git-cheat config (v1)
include_global=true
project=/Users/you/code/project-a
project=/Users/you/code/project-b
```

## Running tests

```bash
./bin/git-cheat_test.sh
```
