#!/bin/bash
set -e

echo "🔧 Setting up n8n Codespace..."

# make sure required tools exist
command -v openssl >/dev/null || { echo "Installing openssl..."; sudo apt-get update -y && sudo apt-get install -y openssl; }
command -v curl >/dev/null || { echo "Installing curl..."; sudo apt-get update -y && sudo apt-get install -y curl; }

# create devcontainer directory
mkdir -p .devcontainer

# --- devcontainer.json ---
cat <<'JSON' | tr -d '\r' > .devcontainer/devcontainer.json
{
  "name": "codespace with docker and n8n",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {
      "moby": true,
      "version": "latest",
      "dockerDashComposeVersion": "v2"
    }
  },
  "runArgs": ["--privileged"],
  "customizations": {
    "vscode": {
      "extensions": ["ms-azuretools.vscode-docker"]
    }
  },
  "forwardPorts": [
    { "port": 5678, "label": "n8n", "onAutoForward": "openBrowser" }
  ],
  "postCreateCommand": ".devcontainer/postCreate.sh"
}
JSON

# --- postCreate.sh ---
cat <<'BASH' | tr -d '\r' > .devcontainer/postCreate.sh
#!/bin/bash
set -e

# rotating n8n creds
N8N_USER="admin"
N8N_PASSWORD="$(openssl rand -hex 12)"

# fixed Postgres creds (persistent)
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="n8n"
POSTGRES_DB="n8n"

# write env for docker-compose
cat > "$(dirname "$0")/credentials.env" <<ENV
N8N_USER=$N8N_USER
N8N_PASSWORD=$N8N_PASSWORD
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
ENV

# start stack
docker compose up -d

echo
echo "📦 Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

LOGIN_URL="http://${N8N_USER}:${N8N_PASSWORD}@localhost:5678"
echo
echo "🚀 n8n is running!"
echo "🔗 $LOGIN_URL"
echo "👤 $N8N_USER"
echo "🔑 $N8N_PASSWORD"
echo
echo "🗄️ Postgres (persistent): user=$POSTGRES_USER pass=$POSTGRES_PASSWORD db=$POSTGRES_DB"
BASH

chmod +x .devcontainer/postCreate.sh

# --- docker-compose.yml ---
cat <<'YAML' | tr -d '\r' > docker-compose.yml
version: "3.8"

services:
  postgres:
    image: postgres:14
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  postgres_data:
  n8n_data:
YAML

echo "✅ All files generated:"
ls -la .devcontainer docker-compose.yml
echo
echo "👉 Next:"
echo "  1) git add -A"
echo "  2) git commit -m 'Add devcontainer + n8n setup'"
echo "  3) git push"
echo "  4) Command Palette → Codespaces: Rebuild Container"
