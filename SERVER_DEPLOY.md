# OpenClaw Server Deploy

Repo này là gateway OpenAI-compatible dùng cùng `bumbee-wiki-ai`.

Luồng chuẩn:

```text
bumbee-wiki-ai -> http://<server>:18789/v1 -> openclaw-codex
```

## 1. Chuẩn bị

```bash
cd /path/to/openclaw-codex
cp .env.server.example .env
mkdir -p data/openclaw-config data/openclaw-workspace
bash scripts/sync-cli-auth-env.sh .env
```

Sửa `.env`:

- `OPENCLAW_GATEWAY_TOKEN`: bắt buộc
- `CLAUDE_*`: nếu bạn dùng Claude auth
- `CODEX_CONFIG_DIR` / `CLAUDE_CONFIG_DIR`: tự điền bằng `bash scripts/sync-cli-auth-env.sh .env`; compose mount read-only vào container để OpenClaw reuse Codex/Claude CLI auth của máy host
- port/bind nếu cần

## 2. Build và chạy

```bash
docker compose -f docker-compose.server.yml --env-file .env build
docker compose -f docker-compose.server.yml --env-file .env up -d
```

Kiểm tra:

```bash
docker compose -f docker-compose.server.yml --env-file .env ps
curl http://127.0.0.1:18789/healthz
```

## 3. Dùng với bumbee-wiki-ai

Trong `bumbee-wiki-ai`:

```env
OPENAI_BASE_URL=http://host.docker.internal:18789/v1
OPENAI_MODEL=openclaw/default
```

Nếu chạy khác máy:

```env
OPENAI_BASE_URL=http://<openclaw-server-ip>:18789/v1
OPENAI_MODEL=openclaw/default
```

## 4. Lưu ý deploy

- file này không dùng path tuyệt đối theo máy local
- config/workspace nằm trong `./data/`
- Codex/Claude CLI auth không bị copy vào repo; chỉ mount read-only từ host qua `CODEX_CONFIG_DIR` và `CLAUDE_CONFIG_DIR`
- gateway port `18789` public theo bind bạn chọn
- bridge port `18790` chỉ bind localhost mặc định

## 5. Lệnh hay dùng

```bash
docker compose -f docker-compose.server.yml --env-file .env logs -f openclaw-gateway
docker compose -f docker-compose.server.yml --env-file .env exec openclaw-cli health --token "$OPENCLAW_GATEWAY_TOKEN"
docker compose -f docker-compose.server.yml --env-file .env down
```
