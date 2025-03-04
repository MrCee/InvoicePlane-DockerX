#!/bin/sh

echo "Waiting for MariaDB to be ready. This may take a while. Timeout set to 3 minutes."
TIMEOUT=180  # timeout in seconds
START_TIME=$(date +%s)

until mariadb --ssl=0 -h "${MYSQL_HOST}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1" >/dev/null 2>&1; do
    sleep 5
    echo "Waiting for database connection..."
    CURRENT_TIME=$(date +%s)
    ELAPSED=$(( CURRENT_TIME - START_TIME ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "Error: Timed out waiting for MariaDB after ${TIMEOUT} seconds."
        exit 1
    fi
done
echo
echo "MariaDB is ready. Starting InvoicePlane..."
echo
echo "SETUP COMPLETE........."
echo "=============================================================="
echo "Setup logs will now print to stdout below."
echo "You can CONTROL + C to stop the logs being reported."
echo "This will not intterupt or affect setup."
echo "=============================================================="
echo
echo

exec "$@"

