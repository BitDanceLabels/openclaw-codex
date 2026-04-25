#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${1:-"$repo_root/.env"}"

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

windows_user="${USERNAME:-${USER:-}}"
codex_dir="$(detect_dir "$HOME/.codex" "/mnt/c/Users/$windows_user/.codex" || true)"
claude_dir="$(detect_dir "$HOME/.claude" "/mnt/c/Users/$windows_user/.claude" || true)"

if [ -n "$codex_dir" ]; then
  upsert_env "CODEX_CONFIG_DIR" "$codex_dir"
  echo "CODEX_CONFIG_DIR=$codex_dir"
else
  echo "WARN: Codex auth dir not found at $HOME/.codex or /mnt/c/Users/$windows_user/.codex" >&2
fi

if [ -n "$claude_dir" ]; then
  upsert_env "CLAUDE_CONFIG_DIR" "$claude_dir"
  echo "CLAUDE_CONFIG_DIR=$claude_dir"
else
  echo "WARN: Claude auth dir not found at $HOME/.claude or /mnt/c/Users/$windows_user/.claude" >&2
fi

echo "Updated $env_file"
