#!/bin/bash
set -e

# Step 1: Create devcontainer config folder
mkdir -p .devcontainer

# Step 2: Write devcontainer.json
cat > .devcontainer/devcontainer.json <<'EOF'
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
EOF

# Step 3: Write postCreate.sh
cat > .devcontainer/postCreate.sh <<'EOF'
#!/bin/bash
set -e

# --- CONFIGURE EMAIL SETTINGS IF YOU WANT EMAIL NOTIFICATIONS ---
EMAIL_FROM="youremail@gmail.com"
EMAIL_TO="youremail@gmail.com"
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="youremail@gmail.com"
SMTP_PASS="your_app_password"
# ---------------------------------------------------------------

# Step 1: Generate rotating n8n creds, fixed Postgres creds
N8N_USER=admin
N8N_PASSWORD=$(openssl rand -hex 12)

POSTGRES_USER=n8n
POSTGRES_PASSWORD=n8n
POSTGRES_DB=n8n

# Save creds for docker-compose
cat > "$(dirname "$0")/credentials.env" <<EOF2
N8N_USER=$N8N_USER
N8N_PASSWORD=$N8N_PASSWORD
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
EOF2

# Step 2: Restart n8n with new creds, keep Postgres data persistent
docker compose down n8n || true
docker compose up -d

echo ""
echo "📦 Checking container health..."

# Step 3: Health check loop
for cid in $(docker ps -q); do
  name=$(docker inspect --format='{{.Name}}' $cid | sed 's/^\/\?//')
  status=$(docker inspect --format='{{.State.Health.Status}}' $cid 2>/dev/null || echo "unknown")

  case "$status" in
    healthy) icon="✅" ;;
    unhealthy) icon="❌" ;;
    starting) icon="⏳" ;;
    *) icon="❓" ;;
  esac

  ports=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{$p}} -> {{$conf 0).HostPort}}{{end}} {{end}}' $cid 2>/dev/null)

  echo "   $icon $name  (status: $status)  ports: ${ports:-none}"
done

# Step 4: Build clickable login URL
LOGIN_URL="http://${N8N_USER}:${N8N_PASSWORD}@localhost:5678"

echo ""
echo "🚀 n8n is running!"
echo "👉 Auto-forwarded on port 5678 (browser should open automatically)."
echo "👤 User: $N8N_USER"
echo "🔑 Password: $N8N_PASSWORD"
echo "🔗 One-click login: $LOGIN_URL"
echo ""
echo "🗄️ Postgres credentials (fixed for persistence):"
echo "   User: $POSTGRES_USER"
echo "   Pass: $POSTGRES_PASSWORD"
echo "   DB:   $POSTGRES_DB"
echo ""

# Step 5: Optional email notification
if [ -n "$SMTP_PASS" ] && [ "$EMAIL_TO" != "youremail@gmail.com" ]; then
  echo "Sending credentials email to $EMAIL_TO..."
  EMAIL_SUBJECT="n8n Codespace Credentials"
  EMAIL_BODY=$(cat <<EOM
🚀 Your n8n Codespace is running!

Login here:
$LOGIN_URL

Credentials:
  User: $N8N_USER
  Pass: $N8N_PASSWORD

Postgres (persistent):
  User: $POSTGRES_USER
  Pass: $POSTGRES_PASSWORD
  DB:   $POSTGRES_DB
EOM
)

  curl -s --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
    --ssl-reqd \
    --mail-from "$EMAIL_FROM" \
    --mail-rcpt "$EMAIL_TO" \
    --user "$SMTP_USER:$SMTP_PASS" \
    -T <(echo -e "From: $EMAIL_FROM\nTo: $EMAIL_TO\nSubject: $EMAIL_SUBJECT\n\n$EMAIL_BODY")

  echo "📧 Email sent!"
fi
EOF
chmod +x .devcontainer/postCreate.sh

# Step 4: Write docker-compose.yml
cat > docker-compose.yml <<'EOF'
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
EOF

echo "✅ Setup script finished."
echo "👉 Commit these files, then run: Codespaces: Rebuild Container"
