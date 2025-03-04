#!/bin/bash
set -e

######################################
# Auto-detect Host UID and GID
######################################
PUID=$(id -u)
PGID=$(id -g)
echo "Auto-detected PUID: $PUID"
echo "Auto-detected PGID: $PGID"

######################################
# Set Default Values for MariaDB UID/GID (if not provided)
######################################
if [ -z "$MYSQL_UID" ]; then
  MYSQL_UID=999
  echo "Using default MYSQL_UID: $MYSQL_UID"
fi

if [ -z "$MYSQL_GID" ]; then
  MYSQL_GID=999
  echo "Using default MYSQL_GID: $MYSQL_GID"
fi

######################################
# Determine Host Operating System
######################################
HOST_OS_VAR=$(uname)
if [ "$HOST_OS_VAR" = "Darwin" ]; then
    HOST_OS="macos"
else
    HOST_OS="linux"
fi
echo "Detected HOST_OS: $HOST_OS"

######################################
# Update .env File with Detected Values
######################################
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    # Update PUID, PGID, and HOST_OS in the .env file
    sed -i.bak "s/^PUID=.*/PUID=${PUID}/" "$ENV_FILE"
    sed -i.bak "s/^PGID=.*/PGID=${PGID}/" "$ENV_FILE"
    sed -i.bak "s/^HOST_OS=.*/HOST_OS=${HOST_OS}/" "$ENV_FILE"

    # Update MYSQL_UID, appending if not present
    if grep -q "^MYSQL_UID=" "$ENV_FILE"; then
        sed -i.bak "s/^MYSQL_UID=.*/MYSQL_UID=${MYSQL_UID}/" "$ENV_FILE"
    else
        echo "MYSQL_UID=${MYSQL_UID}" >> "$ENV_FILE"
    fi

    # Update MYSQL_GID, appending if not present
    if grep -q "^MYSQL_GID=" "$ENV_FILE"; then
        sed -i.bak "s/^MYSQL_GID=.*/MYSQL_GID=${MYSQL_GID}/" "$ENV_FILE"
    else
        echo "MYSQL_GID=${MYSQL_GID}" >> "$ENV_FILE"
    fi

    echo "Updated PUID, PGID, HOST_OS, MYSQL_UID, and MYSQL_GID in .env"
else
    echo "Error: .env file not found. Please create your .env file from .env.example before running this script."
    exit 1
fi

######################################
# Create Required Directories
######################################
# List of required directories for InvoicePlane
DIRS=("invoiceplane_uploads" "invoiceplane_css" "invoiceplane_views" "invoiceplane_language" "mariadb")
for dir in "${DIRS[@]}"; do
    mkdir -p "./$dir"
    echo "Created directory: $dir"
done

######################################
# Set Ownership and Permissions on Host Directories
######################################
echo "Setting ownership and permissions..."

if [ "$HOST_OS" = "macos" ]; then
    echo "Running on macOS: setting ownership and permissions (775) for directories."
    for dir in "${DIRS[@]}"; do
        if [ "$dir" = "mariadb" ]; then
            sudo chown -R ${MYSQL_UID}:${MYSQL_GID} "./$dir"
            sudo chmod -R 775 "./$dir"
            echo "Set ownership ${MYSQL_UID}:${MYSQL_GID} and permissions 775 for: $dir"
        else
            sudo chown -R ${PUID}:${PGID} "./$dir"
            sudo chmod -R 775 "./$dir"
            echo "Set ownership ${PUID}:${PGID} and permissions 775 for: $dir"
        fi
    done
else
    echo "Running on Linux: setting ownership and permissions (775) for directories."
    for dir in "${DIRS[@]}"; do
        if [ "$dir" = "mariadb" ]; then
            sudo chown -R ${MYSQL_UID}:${MYSQL_GID} "./$dir"
            sudo chmod -R 775 "./$dir"
            echo "Set ownership ${MYSQL_UID}:${MYSQL_GID} and permissions 775 for: $dir"
        else
            sudo chown -R ${PUID}:${PGID} "./$dir"
            sudo chmod -R 775 "./$dir"
            echo "Set ownership ${PUID}:${PGID} and permissions 775 for: $dir"
        fi
    done
fi

echo "Initialization complete. All required files and directories have been created and permissions set accordingly."

######################################
# Bring Up Docker Containers
######################################
docker-compose pull
docker-compose up -d && docker logs invoiceplane_app -f



