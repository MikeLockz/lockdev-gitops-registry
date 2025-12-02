#!/bin/bash

# Generate random values
APP_ID=$(openssl rand -hex 16)
APP_KEY="base64:$(openssl rand -base64 32)"
DB_PASSWORD=$(openssl rand -base64 16)
REDIS_PASSWORD=$(openssl rand -base64 16)
APP_URL="http://localhost:8000"

# Create .env file
cat <<EOF > .env
APP_ID=$APP_ID
APP_KEY=$APP_KEY
DB_PASSWORD=$DB_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
APP_ENV=production
APP_URL=$APP_URL
APP_PORT=8000
EOF

echo "Generated .env file with secure credentials."
echo "Starting Coolify..."

docker-compose up -d

echo "Coolify is starting. Access it at $APP_URL"
echo "Default user/password will be requested on first login."
