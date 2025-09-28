
cat <<'BASH' | tr -d '\r' > .devcontainer/postCreate.sh
#!/bin/bash
set -e

# Rotate n8n creds each rebuild; keep Postgres fixed for persistence
N8N_USER="admin"
N8N_PASSWORD="$(openssl rand -hex 12)"
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="n8n"
POSTGRES_DB="n8n"

# Write the env file consumed by docker-compose via env_file
cat > "$(dirname "$0")/credentials.env" <<ENV
N8N_USER=$N8N_USER
N8N_PASSWORD=$N8N_PASSWORD
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
ENV

chmod 600 "$(dirname "$0")/credentials.env" || true

# Bring the stack up (n8n waits for Postgres to be healthy)
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
