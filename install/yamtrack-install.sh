#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jeff.erlandsson
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/FuzzyGrim/Yamtrack

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  redis-server \
  nginx \
  supervisor
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv
import_local_ip
fetch_and_deploy_gh_release "yamtrack" "FuzzyGrim/Yamtrack" "tarball" "latest" "/opt/yamtrack"

msg_info "Installing Python Dependencies"
cd /opt/yamtrack
$STD uv venv .venv
source .venv/bin/activate
$STD uv pip install -r requirements.txt
$STD uv pip install supervisor
msg_ok "Installed Python Dependencies"

msg_info "Configuring Yamtrack"
SECRET_KEY=$(openssl rand -hex 32)
mkdir -p /opt/yamtrack/db

cat <<EOF >/opt/yamtrack/.env
SECRET=${SECRET_KEY}
REDIS_URL=redis://localhost:6379
URLS=http://${LOCAL_IP}:8000
DEBUG=False
TZ=UTC
EOF
msg_ok "Configured Yamtrack"

msg_info "Running Database Migrations"
cd /opt/yamtrack
source .venv/bin/activate
export $(grep -v '^#' /opt/yamtrack/.env | xargs)
$STD python src/manage.py migrate --noinput
$STD python src/manage.py collectstatic --noinput
msg_ok "Ran Database Migrations"

msg_info "Configuring Nginx"
cat <<'EOF' >/etc/nginx/sites-available/yamtrack
server {
    listen 8000;
    server_name _;

    location /static/ {
        alias /opt/yamtrack/staticfiles/;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/yamtrack /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Configured Nginx"

msg_info "Configuring Supervisor"
cat <<'EOF' >/etc/supervisor/conf.d/yamtrack.conf
[program:gunicorn]
command=/opt/yamtrack/.venv/bin/gunicorn --chdir /opt/yamtrack/src --bind 127.0.0.1:8080 config.wsgi:application
directory=/opt/yamtrack
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/yamtrack-gunicorn.log
environment=PATH="/opt/yamtrack/.venv/bin:%(ENV_PATH)s"

[program:celery]
command=/opt/yamtrack/.venv/bin/celery --app config worker --loglevel INFO --without-mingle --without-gossip
directory=/opt/yamtrack/src
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/yamtrack-celery.log
stopwaitsecs=60
stopasgroup=true
environment=PATH="/opt/yamtrack/.venv/bin:%(ENV_PATH)s"

[program:celery-beat]
command=/opt/yamtrack/.venv/bin/celery --app config beat --loglevel INFO
directory=/opt/yamtrack/src
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/yamtrack-celery-beat.log
stopasgroup=true
environment=PATH="/opt/yamtrack/.venv/bin:%(ENV_PATH)s"

[group:yamtrack]
programs=gunicorn,celery,celery-beat
EOF
msg_ok "Configured Supervisor"

msg_info "Creating Service"
cat <<'EOF' >/etc/systemd/system/yamtrack.service
[Unit]
Description=Yamtrack Media Tracker
After=network.target redis-server.service
Wants=redis-server.service

[Service]
Type=simple
EnvironmentFile=/opt/yamtrack/.env
ExecStart=/usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
ExecStop=/usr/bin/supervisorctl shutdown
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Service"

msg_info "Starting Services"
systemctl enable -q --now redis-server
systemctl enable -q --now nginx
systemctl enable -q --now yamtrack
msg_ok "Started Services"

motd_ssh
customize
cleanup_lxc
