# Emergency Recovery

Use this page when you need the shortest path during a live recovery incident.

## Immediate priorities

1. stop guessing
2. preserve the live state
3. identify the dump
4. stage into temp DB
5. analyze before promotion
6. verify core business tables first

## Core business tables to check first

- `ip_clients`
- `ip_invoices`
- `ip_invoice_items`
- `ip_invoice_amounts`
- `ip_invoice_item_amounts`
- `ip_payments`
- `ip_products`

## Safe operator sequence

### 1. Confirm the DB container is healthy
```bash
docker compose ps
docker compose logs --tail=200 invoiceplane_db
```

### 2. Review importer help
```bash
bin/invoiceplane-db-import.sh --help
```

### 3. Run a dry run first
```bash
bin/invoiceplane-db-import.sh --dry-run --dump /path/to/file.sql
```

### 4. Review the generated report
Inspect:

- strategy classification
- blocked/manual-review tables
- core recovery cluster outcomes
- settings/custom handling notes

### 5. Only then run live recovery
```bash
bin/invoiceplane-db-import.sh --yes --dump /path/to/file.sql
```

## If live data is still missing

Check whether the data exists in temp but not live.

That usually means:

- import worked
- promotion strategy failed or was blocked
- live app is only showing the consequence of an empty live table

## If a core table is blocked

Treat that as a safety stop, not as a nuisance.

A blocked critical table means the script avoided forcing ambiguous writes.

## Rollback

Use the live backup created before recovery execution.

That backup is your first rollback path.
