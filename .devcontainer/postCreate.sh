#!/bin/bash
set -e

# rotating n8n creds
N8N_USER="admin"
N8N_PASSWORD="$(openssl rand -hex 12)"

# fixed Postgres creds (persistent)
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="n8n"
POSTGRES_DB="n8n"

# save env for docker compose
cat > "$(dirname "$0")/credentials.env" <<ENV
N8N_USER=$N8N_USER
N8N_PASSWORD=$N8N_PASSWORD
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
ENV

# start stack (n8n waits for Postgres via service_healthy)
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
