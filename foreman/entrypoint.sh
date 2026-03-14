#!/usr/bin/env bash
set -euo pipefail

: "${FOREMAN_DB_HOST:?FOREMAN_DB_HOST is required}"
: "${FOREMAN_DB_NAME:?FOREMAN_DB_NAME is required}"
: "${FOREMAN_DB_USER:?FOREMAN_DB_USER is required}"
: "${FOREMAN_DB_PASSWORD:?FOREMAN_DB_PASSWORD is required}"
: "${FOREMAN_HOSTNAME:?FOREMAN_HOSTNAME is required}"
: "${FOREMAN_ADMIN_USER:?FOREMAN_ADMIN_USER is required}"
: "${FOREMAN_ADMIN_PASSWORD:?FOREMAN_ADMIN_PASSWORD is required}"

log() {
  printf '[foreman-app] %s\n' "$*"
}

wait_for_db() {
  local i
  for i in $(seq 1 60); do
    if bash -lc ">/dev/tcp/${FOREMAN_DB_HOST}/${FOREMAN_DB_PORT:-5432}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

mkdir -p /etc/foreman /etc/foreman/plugins /var/lib/foreman/db /var/lib/foreman/public /var/log/foreman /var/run/foreman

cat > /etc/foreman/database.yml <<EOF
production:
  adapter: postgresql
  encoding: unicode
  database: ${FOREMAN_DB_NAME}
  username: ${FOREMAN_DB_USER}
  password: ${FOREMAN_DB_PASSWORD}
  host: ${FOREMAN_DB_HOST}
  port: ${FOREMAN_DB_PORT:-5432}
  pool: ${FOREMAN_DB_POOL:-15}
EOF

cat > /etc/foreman/settings.yaml <<EOF
---
:require_ssl: false
:fqdn: ${FOREMAN_HOSTNAME}
:domain: ${PXE_DOMAIN:-localdomain}
:administrator: ${FOREMAN_ADMIN_EMAIL:-admin@localdomain}
:trusted_puppetmaster_hosts:
  - ${FOREMAN_HOSTNAME}
EOF

touch /etc/foreman/foreman-debug.conf
chown -R foreman:root /etc/foreman /var/lib/foreman /var/log/foreman /var/run/foreman

log "Waiting for PostgreSQL at ${FOREMAN_DB_HOST}:${FOREMAN_DB_PORT:-5432}"
wait_for_db || {
  log "PostgreSQL did not become reachable"
  exit 1
}

export RAILS_ENV=production
export RAILS_LOG_TO_STDOUT=true
export RAILS_SERVE_STATIC_FILES=true
export FOREMAN_BIND=0.0.0.0
export SEED_ADMIN_USER="${FOREMAN_ADMIN_USER}"
export SEED_ADMIN_PASSWORD="${FOREMAN_ADMIN_PASSWORD}"
export SEED_ADMIN_EMAIL="${FOREMAN_ADMIN_EMAIL:-admin@localdomain}"
export SEED_ADMIN_FIRST_NAME="${FOREMAN_ADMIN_FIRST_NAME:-Foreman}"
export SEED_ADMIN_LAST_NAME="${FOREMAN_ADMIN_LAST_NAME:-Admin}"

log "Running database migrations"
su -m -s /bin/bash foreman -c 'cd /usr/share/foreman && /usr/share/foreman/bin/rails db:migrate'
log "Running database seed"
su -m -s /bin/bash foreman -c 'cd /usr/share/foreman && /usr/share/foreman/bin/rails db:seed'
log "Applying admin account settings"
su -m -s /bin/bash foreman -c 'cd /usr/share/foreman && /usr/share/foreman/bin/rails runner '\''User.as_anonymous_admin do; user = User.unscoped.find_by!(login: ENV.fetch("SEED_ADMIN_USER")); internal = AuthSourceInternal.find_by!(type: "AuthSourceInternal"); user.firstname = ENV.fetch("SEED_ADMIN_FIRST_NAME", "Admin"); user.lastname = ENV.fetch("SEED_ADMIN_LAST_NAME", "User"); user.mail = ENV.fetch("SEED_ADMIN_EMAIL", "admin@localdomain"); user.admin = true; user.auth_source = user.auth_source || internal; user.password = ENV.fetch("SEED_ADMIN_PASSWORD"); user.password_confirmation = ENV.fetch("SEED_ADMIN_PASSWORD"); user.save!; end'\'''
log "Starting Foreman application server"
exec su -m -s /bin/bash foreman -c 'cd /usr/share/foreman && exec /usr/share/foreman/bin/rails server --environment production --binding 0.0.0.0 --port 3000'
