#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${1:-"$repo_root/.env"}"
auth_root="$repo_root/data/cli-auth"
container_uid="${OPENCLAW_CONTAINER_UID:-1000}"
container_gid="${OPENCLAW_CONTAINER_GID:-1000}"

if [ ! -f "$env_file" ]; then
  if [ -f "$repo_root/.env.server.example" ]; then
    cp "$repo_root/.env.server.example" "$env_file"
  else
    touch "$env_file"
  fi
fi

upsert_env() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  if grep -qE "^${key}=" "$env_file"; then
    awk -v key="$key" -v value="$value" 'BEGIN { FS=OFS="=" } $1 == key { print key, value; next } { print }' "$env_file" > "$tmp"
  else
    cp "$env_file" "$tmp"
    printf '\n%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$env_file"
}

detect_dir() {
  local unix_path="$1"
  local windows_path="$2"
  if [ -d "$unix_path" ]; then
    printf '%s\n' "$unix_path"
    return 0
  fi
  if [ -n "$windows_path" ] && [ -d "$windows_path" ]; then
    printf '%s\n' "$windows_path"
    return 0
  fi
  return 1
}

copy_if_exists() {
  local src_dir="$1"
  local dst_dir="$2"
  shift 2
  mkdir -p "$dst_dir"
  for rel in "$@"; do
    if [ -e "$src_dir/$rel" ]; then
      mkdir -p "$dst_dir/$(dirname "$rel")"
      cp -a "$src_dir/$rel" "$dst_dir/$rel"
    fi
  done
}

fix_container_permissions() {
  local target="$1"
  [ -d "$target" ] || return 0
  chown -R "$container_uid:$container_gid" "$target" 2>/dev/null || true
  find "$target" -type d -exec chmod 700 {} +
  find "$target" -type f -exec chmod 600 {} +
}

enable_openai_http_endpoint() {
  local config_file="$repo_root/data/openclaw-config/openclaw.json"
  mkdir -p "$(dirname "$config_file")"
  if ! command -v node >/dev/null 2>&1; then
    echo "WARN: node not found; skipping OpenAI-compatible HTTP endpoint config" >&2
    return 0
  fi
  node - "$config_file" <<'NODE'
const fs = require("fs");
const path = process.argv[2];
let config = {};
if (fs.existsSync(path)) {
  const raw = fs.readFileSync(path, "utf8").trim();
  config = raw ? JSON.parse(raw) : {};
}
config.gateway ??= {};
config.gateway.http ??= {};
config.gateway.http.endpoints ??= {};
config.gateway.http.endpoints.chatCompletions ??= {};
config.gateway.http.endpoints.chatCompletions.enabled = true;
config.agents ??= {};
config.agents.defaults ??= {};
config.agents.defaults.model ??= "openai-codex/gpt-5.4";
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`);
NODE
}

seed_codex_auth_profile() {
  local codex_auth="$codex_dst/auth.json"
  local agent_dir="$repo_root/data/openclaw-config/agents/main/agent"
  local profile_file="$agent_dir/auth-profiles.json"
  [ -f "$codex_auth" ] || return 0
  mkdir -p "$agent_dir"
  if ! command -v node >/dev/null 2>&1; then
    echo "WARN: node not found; skipping Codex auth profile seed" >&2
    return 0
  fi
  node - "$codex_auth" "$profile_file" <<'NODE'
const fs = require("fs");
const [codexAuthPath, profilePath] = process.argv.slice(2);
const source = JSON.parse(fs.readFileSync(codexAuthPath, "utf8"));
const tokens = source.tokens && typeof source.tokens === "object" ? source.tokens : {};
const access = typeof tokens.access_token === "string" ? tokens.access_token.trim() : "";
const refresh = typeof tokens.refresh_token === "string" ? tokens.refresh_token.trim() : "";
if (!access || !refresh) {
  process.exit(0);
}
let store = { version: 1, profiles: {} };
if (fs.existsSync(profilePath)) {
  const raw = fs.readFileSync(profilePath, "utf8").trim();
  if (raw) {
    store = JSON.parse(raw);
  }
}
store.version = store.version || 1;
store.profiles = store.profiles && typeof store.profiles === "object" ? store.profiles : {};
store.profiles["openai-codex:default"] = {
  type: "oauth",
  provider: "openai-codex",
  access,
  refresh,
  expires: Date.now() + 55 * 60 * 1000,
  ...(typeof tokens.id_token === "string" && tokens.id_token.trim() ? { idToken: tokens.id_token.trim() } : {}),
  ...(typeof tokens.account_id === "string" && tokens.account_id.trim() ? { accountId: tokens.account_id.trim() } : {}),
};
fs.writeFileSync(profilePath, `${JSON.stringify(store, null, 2)}\n`, { mode: 0o600 });
NODE
}

windows_user="${USERNAME:-${USER:-}}"
codex_src="$(detect_dir "$HOME/.codex" "/mnt/c/Users/$windows_user/.codex" || true)"
claude_src="$(detect_dir "$HOME/.claude" "/mnt/c/Users/$windows_user/.claude" || true)"
codex_dst="$auth_root/codex"
claude_dst="$auth_root/claude"

if [ -n "$codex_src" ]; then
  mkdir -p "$codex_dst"
  copy_if_exists "$codex_src" "$codex_dst" \
    auth.json \
    config.toml \
    installation_id \
    version.json \
    skills \
    plugins \
    rules \
    memories || true
  fix_container_permissions "$codex_dst"
  upsert_env "CODEX_CONFIG_DIR" "./data/cli-auth/codex"
  echo "CODEX_CONFIG_DIR=./data/cli-auth/codex (synced from $codex_src)"
else
  echo "WARN: Codex auth dir not found at $HOME/.codex or /mnt/c/Users/$windows_user/.codex" >&2
fi

if [ -n "$claude_src" ]; then
  mkdir -p "$claude_dst"
  copy_if_exists "$claude_src" "$claude_dst" \
    .credentials.json \
    settings.json \
    settings.local.json \
    ide || true
  fix_container_permissions "$claude_dst"
  upsert_env "CLAUDE_CONFIG_DIR" "./data/cli-auth/claude"
  echo "CLAUDE_CONFIG_DIR=./data/cli-auth/claude (synced from $claude_src)"
else
  echo "WARN: Claude auth dir not found at $HOME/.claude or /mnt/c/Users/$windows_user/.claude" >&2
fi

mkdir -p "$repo_root/data/openclaw-config" "$repo_root/data/openclaw-workspace"
enable_openai_http_endpoint
seed_codex_auth_profile
fix_container_permissions "$repo_root/data/openclaw-config"
fix_container_permissions "$repo_root/data/openclaw-workspace"

echo "Updated $env_file"
