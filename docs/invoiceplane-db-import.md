# InvoicePlane DB Import

[← Back to README](../README.md)

`bin/invoiceplane-db-import.sh` is a staged database import, recovery, and reconciliation tool for InvoicePlane.

## Related docs

- [Recovery and Database Import](./recovery.md)
- [Table Strategy Matrix](./table-strategy-matrix.md)
- [Dev Reset Install](./dev-reset-install.md)

---

## Purpose

## Why This Script Is Reconcile-Only

This project intentionally does **not** support direct database imports.

Instead, it uses a **reconcile-only model**.

### The problem with direct imports

Direct SQL imports assume:

- the source schema matches the destination schema
- the application version is identical
- all required columns and tables exist

In practice, these assumptions are often false.

This leads to:

- failed imports
- missing data
- corrupted state
- silent inconsistencies

### The reconcile approach

This script avoids those problems by:

1. importing the dump into a temporary database
2. using the InvoicePlane installer to create a correct, current schema
3. comparing temp data against the live schema
4. applying controlled merge strategies
5. skipping unsafe or runtime-managed tables

### Why this works across versions

The key idea is:

> the destination schema is always created fresh by the installer

This means:

- the schema always matches the running application
- old data is adapted into the new structure
- schema differences are handled safely

### Result

Reconcile mode:

- works across InvoicePlane versions
- tolerates schema changes
- avoids destructive overwrites
- produces consistent results

### Design decision

This script is reconcile-only by design.

Direct import mode is intentionally not supported, because it is less reliable and more dangerous.



This tool exists to safely recover older InvoicePlane data into a current Docker deployment without assuming that every table can be blindly copied.

It is designed to:

1. optionally back up the current live database (live mode only)
2. import an old dump into a temporary database
3. analyze shared tables and schema differences
4. assign a strategy per table
5. execute only supported strategies
6. verify results based on strategy
7. produce clear, auditable reports

---

## Operating modes

### Interactive mode

Prompts before applying any live changes.

---

### Non-interactive mode

```bash
bin/invoiceplane-db-import.sh --yes --dump /path/to/file.sql
```

---

### Dry run

```bash
bin/invoiceplane-db-import.sh --dry-run --dump /path/to/file.sql
```

Dry run will:

- recreate the temp DB
- import the dump into temp
- analyze schemas and classify strategies
- generate full reports
- **NOT modify the live database**
- **NOT create a live DB backup**

Expected output includes:

- `Mode          : DRY RUN`
- `DRY RUN: skipping live DB backup`
- `DRY RUN: no live changes applied`

---

## CLI flags

- `--dump <file>` — path to SQL dump
- `--yes` — non-interactive execution
- `--dry-run` — analysis only, no live mutation
- `--help` — show usage

---

## Execution phases

### 1. Environment validation

Checks for:

- repo root
- `.env`
- docker / docker compose
- python3
- database container availability

---

### 2. Backup (live mode only)

In live execution mode:

- creates a full backup of the current database
- stored under `.backup/` (ignored by Git)

In dry run:

- backup is intentionally skipped

---

### 3. Temp DB staging

- drops and recreates the temp database
- imports the dump without modification

---

### 4. Analysis

- discovers shared tables
- compares schema structure
- classifies compatibility

---

### 5. Strategy planning

Each table is assigned a declared strategy.

Typical strategies:

- `REPLACE_EXACT`
- `REPLACE_MAPPED`
- `MERGE_BY_PK`
- `SPECIAL_SETTINGS`
- `SPECIAL_CUSTOM_VALUES`
- `SKIP`
- `MANUAL_REVIEW`

---

### 6. Execution

- only supported strategies are executed
- unsafe tables are not forced
- critical failures are flagged explicitly

---

### 7. Verification

Verification depends on strategy:

- replace → row count match
- merge → primary key coverage
- settings → key/value validation
- custom → owner/field coverage

---

### 8. Reporting

Reports include:

- planned strategy
- attempted methods
- winning method
- verification mode
- final status
- row counts before/after
- notes

---

## Recovery cluster

These tables are treated as a core recovery cluster:

- `ip_clients`
- `ip_products`
- `ip_invoices`
- `ip_invoice_items`
- `ip_invoice_amounts`
- `ip_invoice_item_amounts`
- `ip_payments`
- `ip_payment_methods`

These represent the business-critical invoice and payment model.

---

## Important special handling

### `ip_settings`

- merged by `setting_key`
- not blindly replaced

---

### Custom-field tables

- require definition-aware handling
- orphan/null values are filtered or reported
- merged by `(owner_id, field_id)`

---

### Skip tables

Tables such as:

- users
- sessions
- logs
- import/version tracking

are intentionally skipped or handled separately.

---

## Rollback

In live execution mode:

- a full database backup is created before any changes
- rollback = restore that backup

Dry run:

- no backup is created
- no rollback is required

---

## Operator expectations

This tool is intentionally conservative.

It prioritizes:

- safety
- transparency
- auditability

It does **not**:

- blindly force schema compatibility
- silently drop ambiguous data
- pretend success without verification

If a table cannot be handled safely, it will be reported for manual review.

