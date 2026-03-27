#!/bin/bash

cd /docker/InvoicePlane-DockerX

set -a
. ./.env
set +a

mkdir -p .backup

ts="$(date +%Y%m%d-%H%M%S)"

docker compose exec -T invoiceplane_db sh -lc '
mariadb-dump \
  -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  invoiceplane
' > ".backup/invoiceplane-live-${ts}.sql"

echo
echo "=== backup created ==="
ls -lh ".backup/invoiceplane-live-${ts}.sql"
