#!/usr/bin/env bash
set -euo pipefail

# small helper to ensure tools exist
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Installing $1 ..."
    sudo apt-get update -y
    sudo apt-get install -y "$1"
  fi
}

# make sure core tools exist
need openssl
need curl

mkdir -p .devcontainer

# devcontainer.json with auto open on port 5678 and a postCreate script
cat > .devcontainer/devcontainer.json <<'JSON'
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
    {
      "port": 5678,
      "label": "n8n",
      "onAutoForward": "openBrowser"
    }
  ],
  "postCreateCommand": ".devcontainer/postCreate.sh"
}
JSON

# postCreate.sh
cat > .devcontainer/postCreate.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

# optional email settings, fill in to enable email
EMAIL_FROM="youremail@gmail.com"
EMAIL_TO="youremail@gmail.com"
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="youremail@gmail.com"
SMTP_PASS="your_app_password"   # use a Gmail App Password if you enable this

# rotating n8n credentials on every rebuild
N8N_USER="admin"
N8N_PASSWORD="$(openssl rand -hex 12)"

# fixed Postgres credentials for persistence
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="n8n"
POSTGRES_DB="n8n"

# write env for docker compose
cat > "$(dirname "$0")/credentials.env" <<ENV
N8N_USER=$N8N_USER
N8N_PASSWORD=$N8N_PASSWORD
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
ENV

# restart only n8n so Postgres data stays
docker compose down n8n || true
docker compose up -d

echo
echo "Checking container health ..."

for cid in $(docker ps -q); do
  name="$(docker inspect --format='{{.Name}}' "$cid" | sed 's#^/##')"
  status="$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "unknown")"
  case "$status" in
    healthy) icon="✅" ;;
    unhealthy) icon="❌" ;;
    starting) icon="⏳" ;;
    *) icon="❓" ;;
  esac
  ports="$(docker inspect --format='{{range $p,$conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{$conf 0).HostPort}}{{end}} {{end}}' "$cid" 2>/dev/null)"
  echo "   $icon $name  status: $status  ports: ${ports:-none}"
done

LOGIN_URL="http://${N8N_USER}:${N8N_PASSWORD}@localhost:5678"

echo
echo "n8n is running"
echo "Port 5678 is auto forwarded"
echo "User: $N8N_USER"
echo "Password: $N8N_PASSWORD"
echo "One click login: $LOGIN_URL"
echo
echo "Postgres is persistent"
echo "DB user: $POSTGRES_USER"
echo "DB pass: $POSTGRES_PASSWORD"
echo "DB name: $POSTGRES_DB"
echo

# optional email notification
if [ -n "$SMTP_PASS" ] && [ "$EMAIL_TO" != "youremail@gmail.com" ]; then
  echo "Sending credentials email to $EMAIL_TO ..."
  SUBJECT="n8n Codespace credentials"
  BODY=$(cat <<EOM
Your n8n Codespace is running

Login
$LOGIN_URL

n8n
  user: $N8N_USER
  pass: $N8N_PASSWORD

Postgres
  user: $POSTGRES_USER
  pass: $POSTGRES_PASSWORD
  db:   $POSTGRES_DB
EOM
)
  curl -s --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
    --ssl-reqd \
    --mail-from "$EMAIL_FROM" \
    --mail-rcpt "$EMAIL_TO" \
    --user "$SMTP_USER:$SMTP_PASS" \
    -T <(printf "From: %s\nTo: %s\nSubject: %s\n\n%s" "$EMAIL_FROM" "$EMAIL_TO" "$SUBJECT" "$BODY") >/dev/null || true
  echo "Email sent"
fi
BASH
chmod +x .devcontainer/postCreate.sh

# docker compose file with health checks and persistent volumes
cat > docker-compose.yml <<'YAML'
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

echo "Setup files written"
echo "Add and commit, then rebuild the container"
