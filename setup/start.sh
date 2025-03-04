#!/bin/sh

# Redirect all output to start.log while still printing to terminal.
# exec > >(tee start.log) 2>&1

# set -e  # Stop script on first error

echo "🔄 Starting InvoicePlane container..."

######################################
# Dynamic User & Logging Setup
######################################
# Compute PHP_VERSION_CLEAN by stripping the decimal (e.g., "8.1" becomes "81")
PHP_VERSION_CLEAN=$(echo "$PHP_VERSION" | cut -d. -f1-2 | tr -d '.')

# Create the directory where the PHP log symlink will reside.
mkdir -p /var/log/php${PHP_VERSION_CLEAN}
chmod -R 775 /var/log/php${PHP_VERSION_CLEAN}
chown nobody:nginx /var/log/php${PHP_VERSION_CLEAN}

# Redirect PHP and Nginx logs to stdout for Docker logging.
ln -sf /dev/stdout /var/log/php${PHP_VERSION_CLEAN}/error.log
ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stdout /var/log/nginx/error.log

######################################
# Dynamic User Setup
######################################
# Set default PUID and PGID if not provided.
PUID=${PUID:-911}
PGID=${PGID:-911}

# Check and update the UID of user "abc" if it doesn't match the desired PUID.
if [ "$(id -u abc)" -ne "$PUID" ]; then
    echo "🔄 Updating user 'abc' UID to $PUID..."
    usermod -o -u "$PUID" abc
fi

# Check and update the GID of group "abc" if it doesn't match the desired PGID.
if [ "$(id -g abc)" -ne "$PGID" ]; then
    echo "🔄 Updating group 'abc' GID to $PGID..."
    groupmod -o -g "$PGID" abc
fi

echo "✅ Dynamic user setup complete. User 'abc' now has UID: $(id -u abc) and GID: $(id -g abc)."

######################################
# Functions for Directory Setup
######################################
copy_directory_if_empty() {
    local source="$1"
    local target="$2"
    if [ ! -d "$target" ]; then
        echo "📁 Directory '$target' does not exist. Creating and copying from '$source'..."
        cp -r "$source" "$target"
    elif [ -z "$(ls -A "$target")" ]; then
        echo "📁 Directory '$target' exists but is empty. Populating from '$source'..."
        cp -r "$source"/* "$target"/
    else
        echo "✅ Directory '$target' exists and is not empty. Skipping."
    fi
}

copy_language_directory_preserve_custom() {
    local source="$1"
    local target="$2"
    echo "🔄 Updating language directory '$target' from '$source' (preserving custom_lang.php)..."
    
    # Ensure the target directory exists.
    [ ! -d "$target" ] && mkdir -p "$target"
    
    for file in "$source"/*; do
        base=$(basename "$file")
        if [ "$base" = "custom_lang.php" ] && [ -f "$target/$base" ]; then
            echo "⏩ Skipping $base as it exists in destination"
            continue
        fi
        cp -r "$file" "$target/"
        echo "📄 Copied $base"
    done
}

######################################
# Populate Application Directories
######################################
copy_directory_if_empty "/var/www/html_default/uploads" "/var/www/html/uploads"
copy_directory_if_empty "/var/www/html_default/assets/core/css" "/var/www/html/assets/core/css"
copy_directory_if_empty "/var/www/html_default/application/views" "/var/www/html/application/views"
copy_language_directory_preserve_custom "/var/www/html_default/application/language/${IP_LANGUAGE}" "/var/www/html/application/language/${IP_LANGUAGE}"

# Ensure ipconfig.php exists; if not, create it from the example.
if [ ! -f "/var/www/html/ipconfig.php" ]; then
    echo "🛠️ Creating ipconfig.php from ipconfig.php.example..."
    cp /var/www/html/ipconfig.php.example /var/www/html/ipconfig.php
    chown nobody:nginx /var/www/html/ipconfig.php
    chmod 644 /var/www/html/ipconfig.php
fi

######################################
# Adjust Ownership & Permissions for Bind Mounts
######################################
echo "🔄 Adjusting ownership and permissions for bind mounts..."

# Define the directories (bind mounts) to be set to user abc:abc.
# (Excluding /var/www/html/application/logs for separate handling and any mariadb directories.)
OWN_DIRS="/var/www/html/uploads /var/www/html/assets/core/css /var/www/html/application/views /var/www/html/application/language/${IP_LANGUAGE}"

# For non-macOS hosts, update ownership and permissions.
if [ "$HOST_OS" = "macos" ]; then
    echo "Running on macOS: skipping chown for bind mount directories."
else
    for dir in $OWN_DIRS; do
        if [ -d "$dir" ]; then
            echo "Changing ownership of $dir to abc:abc and setting permissions to 775..."
            chown -R abc:abc "$dir"
            chmod -R 775 "$dir"
        else
            echo "Notice: Directory $dir does not exist; skipping..."
        fi
    done
fi

echo "✅ Bind mount ownership and permissions set."

######################################
# Update ipconfig.php with Environment Variables
######################################
update_config() {
    local key="$1"
    local value="$2"
    local file="/var/www/html/ipconfig.php"
    if grep -q "^$key=" "$file"; then
        sed -i "s|^$key=.*|$key=${value}|" "$file"
        echo "🔧 Updated $key in ipconfig.php"
    else
        echo "⚠️ Warning: $key not found in ipconfig.php, skipping update."
    fi
}

[ -n "$IP_URL" ] && update_config "IP_URL" "$IP_URL"
[ -n "$ENABLE_DEBUG" ] && update_config "ENABLE_DEBUG" "$ENABLE_DEBUG"
[ -n "$DISABLE_SETUP" ] && update_config "DISABLE_SETUP" "$DISABLE_SETUP"
[ -n "$REMOVE_INDEXPHP" ] && update_config "REMOVE_INDEXPHP" "$REMOVE_INDEXPHP"
[ -n "$MYSQL_HOST" ] && update_config "DB_HOSTNAME" "$MYSQL_HOST"
[ -n "$MYSQL_USER" ] && update_config "DB_USERNAME" "$MYSQL_USER"
[ -n "$MYSQL_PASSWORD" ] && update_config "DB_PASSWORD" "$MYSQL_PASSWORD"
[ -n "$MYSQL_DB" ] && update_config "DB_DATABASE" "$MYSQL_DB"
[ -n "$MYSQL_PORT" ] && update_config "DB_PORT" "$MYSQL_PORT"
[ -n "$SESS_EXPIRATION" ] && update_config "SESS_EXPIRATION" "$SESS_EXPIRATION"
[ -n "$SESS_MATCH_IP" ] && update_config "SESS_MATCH_IP" "$SESS_MATCH_IP"
[ -n "$ENABLE_INVOICE_DELETION" ] && update_config "ENABLE_INVOICE_DELETION" "$ENABLE_INVOICE_DELETION"
[ -n "$DISABLE_READ_ONLY" ] && update_config "DISABLE_READ_ONLY" "$DISABLE_READ_ONLY"

if [ -n "$SETUP_COMPLETED" ] && [ -n "$ENCRYPTION_KEY" ]; then
    echo "🔑 Both setup is complete and an encryption key is provided."
    echo "🔑 Setting encryption keys using .env file..."
    [ -n "$ENCRYPTION_KEY" ] && update_config "ENCRYPTION_KEY" "$ENCRYPTION_KEY"
    [ -n "$ENCRYPTION_CIPHER" ] && update_config "ENCRYPTION_CIPHER" "$ENCRYPTION_CIPHER"
    update_config "SETUP_COMPLETED" "$SETUP_COMPLETED"
fi

######################################
# Inject Composer Autoloader if Needed
######################################
if [ -f "/var/www/html/index.php" ]; then
    if ! grep -q "vendor/autoload.php" /var/www/html/index.php; then
        echo "Injecting Composer autoloader into index.php..."
        sed -i "/^<\?php/a require_once __DIR__ . '\/vendor\/autoload.php';" /var/www/html/index.php
    else
        echo "Composer autoloader already injected in index.php, skipping."
    fi
else
    echo "⚠️ index.php not found, cannot inject Composer autoloader."
fi

######################################
# Wait for the Database to be Available
######################################
echo "⏳ Waiting for the database to be available..."
/config/wait-for-db.sh

######################################
# Start Services
######################################
echo "🚀 Starting PHP-FPM..."
php-fpm --daemonize
sleep 2  # Allow time for PHP-FPM to start

echo "🌍 Starting Nginx..."
exec nginx -g "daemon off;"

