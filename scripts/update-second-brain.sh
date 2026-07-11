#!/usr/bin/env bash
set -Eeuo pipefail

# Safely update Cody's model-neutral Codex integration and install it in the
# existing Obsidian vault. Environment variables make paths overridable for
# testing without changing the defaults used by the launcher.

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" == /* ]] || SOURCE_PATH="$SOURCE_DIR/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_ROOT="${SECOND_BRAIN_VAULT:-/Users/codychandler/Documents/Obsidian Vault/Cody Vault}"
BACKUP_ROOT="${SECOND_BRAIN_BACKUP_ROOT:-$HOME/Desktop}"
EXPECTED_ORIGIN="${SECOND_BRAIN_ORIGIN:-https://github.com/Sagewater1283/obsidian-second-brain.git}"
EXPECTED_UPSTREAM="${SECOND_BRAIN_UPSTREAM:-https://github.com/eugeniughelbur/obsidian-second-brain}"
INTEGRATION_ITEMS=(AGENTS.md INSTALL.md .agents .codex)
BACKUP_DIR=""
INSTALL_STARTED=0
INSTALL_COMPLETE=0

info() { printf '[info] %s\n' "$*"; }
ok() { printf '[ok] %s\n' "$*"; }
fail() { printf '[error] %s\n' "$*" >&2; exit 1; }

normalize_remote() {
  printf '%s' "$1" | sed -E 's#^git@github.com:#https://github.com/#; s#/$##; s#\.git$##'
}

restore_backup() {
  local item
  [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || return 0
  printf '[warn] Installation failed; restoring integration from %s\n' "$BACKUP_DIR" >&2
  for item in "${INTEGRATION_ITEMS[@]}"; do
    rm -rf "$VAULT_ROOT/$item"
    [[ -e "$BACKUP_DIR/$item" ]] && cp -R "$BACKUP_DIR/$item" "$VAULT_ROOT/$item"
  done
}

on_exit() {
  local status=$?
  if (( status != 0 && INSTALL_STARTED == 1 && INSTALL_COMPLETE == 0 )); then
    restore_backup
  fi
  exit "$status"
}
trap on_exit EXIT

command -v git >/dev/null || fail 'git is required.'
command -v python3 >/dev/null || fail 'python3 is required.'
command -v rg >/dev/null || fail 'ripgrep (rg) is required.'

[[ -d "$REPO_ROOT/.git" ]] || fail "Not a Git repository: $REPO_ROOT"
[[ -x "$REPO_ROOT/scripts/build.sh" || -f "$REPO_ROOT/scripts/build.sh" ]] || fail 'scripts/build.sh is missing.'
[[ -d "$VAULT_ROOT" ]] || fail "Vault not found: $VAULT_ROOT"

cd "$REPO_ROOT"

[[ "$(git branch --show-current)" == main ]] || fail 'Run this command from the main branch.'
[[ -z "$(git status --porcelain)" ]] || fail 'Working tree is not clean. Commit or stash local changes, then retry.'

origin_url="$(git remote get-url origin 2>/dev/null)" || fail 'Missing origin remote.'
upstream_url="$(git remote get-url upstream 2>/dev/null)" || fail 'Missing upstream remote.'
[[ "$(normalize_remote "$origin_url")" == "$(normalize_remote "$EXPECTED_ORIGIN")" ]] || fail "Unexpected origin remote: $origin_url"
[[ "$(normalize_remote "$upstream_url")" == "$(normalize_remote "$EXPECTED_UPSTREAM")" ]] || fail "Unexpected upstream remote: $upstream_url"

start_commit="$(git rev-parse --short HEAD)"
info "Repository verified at $REPO_ROOT"
info 'Fetching upstream/main...'
git fetch upstream main

info 'Merging upstream/main (conflicts will not be auto-resolved)...'
if ! git merge --no-edit upstream/main; then
  git merge --abort >/dev/null 2>&1 || true
  fail 'Upstream merge conflicted and was aborted. Resolve it manually; nothing was installed.'
fi

# The customized source must remain model-neutral after integrating upstream.
if rg -n -F 'For future Claude' \
  adapters/codex-cli/adapter.sh commands references/ai-first-rules.md \
  references/claude-md-template.md scripts hooks/validate-ai-first.sh \
  hooks/validate-ai-first.hook.yaml \
  --glob '*.md' --glob '*.sh' --glob '*.yaml' --glob '*.py' \
  --glob '!update-second-brain.sh'; then
  fail 'The upstream update reintroduced the legacy phrase in active Codex sources. Review the merge before installing.'
fi

info 'Checking validator syntax...'
bash -n hooks/validate-ai-first.sh
info 'Running smoke tests...'
python3 -m pytest tests/test_smoke.py

info 'Building only codex-cli...'
bash scripts/build.sh --platform codex-cli

DIST_DIR="$REPO_ROOT/dist/codex-cli"
for item in "${INTEGRATION_ITEMS[@]}"; do
  [[ -e "$DIST_DIR/$item" ]] || fail "Build output is missing $item."
  [[ -e "$VAULT_ROOT/$item" ]] || fail "Installed integration is missing $item; refusing an incomplete backup."
done

if rg -n -F 'For future Claude' "$DIST_DIR/AGENTS.md" "$DIST_DIR/.agents" "$DIST_DIR/.codex"; then
  fail 'Legacy phrase found in generated Codex output; nothing was installed.'
fi
agent_count="$(rg -o -F 'For future agents' "$DIST_DIR/AGENTS.md" "$DIST_DIR/.agents" "$DIST_DIR/.codex" | wc -l | tr -d ' ')"
(( agent_count > 0 )) || fail 'Generated output does not contain the model-neutral phrase.'

timestamp="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/obsidian-second-brain-integration-backup-$timestamp"
mkdir -p "$BACKUP_DIR"
for item in "${INTEGRATION_ITEMS[@]}"; do
  cp -R "$VAULT_ROOT/$item" "$BACKUP_DIR/$item"
done
ok "Backup created: $BACKUP_DIR"

INSTALL_STARTED=1
for item in "${INTEGRATION_ITEMS[@]}"; do
  rm -rf "$VAULT_ROOT/$item"
  cp -R "$DIST_DIR/$item" "$VAULT_ROOT/$item"
done

if rg -n -F 'For future Claude' "$VAULT_ROOT/AGENTS.md" "$VAULT_ROOT/.agents" "$VAULT_ROOT/.codex"; then
  fail 'Legacy phrase found after installation.'
fi
installed_count="$(rg -o -F 'For future agents' "$VAULT_ROOT/AGENTS.md" "$VAULT_ROOT/.agents" "$VAULT_ROOT/.codex" | wc -l | tr -d ' ')"
(( installed_count > 0 )) || fail 'Installed integration is missing the model-neutral phrase.'
INSTALL_COMPLETE=1

end_commit="$(git rev-parse --short HEAD)"
printf '\nUpdate complete\n'
printf '  Repository: %s -> %s\n' "$start_commit" "$end_commit"
printf '  Tests:      smoke suite and validator syntax passed\n'
printf '  Build:      codex-cli only\n'
printf '  Installed:  %s\n' "$VAULT_ROOT"
printf '  Legacy:     0 matches\n'
printf '  Agent text: %s matches\n' "$installed_count"
printf '  Rollback:   %s\n' "$BACKUP_DIR"
printf '\nRestart Codex from the vault to load the updated integration.\n'
