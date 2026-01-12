#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/erljef/ProxmoxVED/yamtrack/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: jeff.erlandsson
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/FuzzyGrim/Yamtrack

# App Default Values
APP="Yamtrack"
var_tags="${var_tags:-media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/yamtrack ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "yamtrack" "FuzzyGrim/Yamtrack"; then
    msg_info "Stopping Services"
    supervisorctl stop yamtrack:*
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    cp -r /opt/yamtrack/db /tmp/yamtrack_backup
    cp /opt/yamtrack/.env /tmp/yamtrack_backup/
    msg_ok "Backup completed"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "yamtrack" "FuzzyGrim/Yamtrack" "tarball" "latest" "/opt/yamtrack"

    msg_info "Restoring Data"
    cp -r /tmp/yamtrack_backup/db /opt/yamtrack/
    cp /tmp/yamtrack_backup/.env /opt/yamtrack/
    rm -rf /tmp/yamtrack_backup
    msg_ok "Data restored"

    msg_info "Updating Python Dependencies"
    cd /opt/yamtrack
    source .venv/bin/activate
    $STD pip install --upgrade -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Running Migrations"
    export $(grep -v '^#' /opt/yamtrack/.env | xargs)
    $STD python src/manage.py migrate --noinput
    $STD python src/manage.py collectstatic --noinput
    deactivate
    msg_ok "Ran Migrations"

    msg_info "Starting Services"
    supervisorctl reread
    supervisorctl update
    supervisorctl start yamtrack:*
    msg_ok "Started Services"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
