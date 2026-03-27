# Publishing and Git Hygiene

This repository mixes infrastructure, runtime state, and recovery tooling, so publish hygiene matters.

## Never track mutable business data

Do not commit:

- live SQL dumps
- imported business/customer dumps
- generated execution artifacts
- runtime logs
- mutable MariaDB contents
- generated backups from recovery runs

## Directories and generated outputs

Scripts should:

- create missing directories safely with `mkdir -p`
- avoid destructive replacement of existing business data
- keep generated reports separate from source-controlled docs

## Examples visible in the working tree

Typical runtime/generated clutter includes:

- backup files in the repo root
- mutable DB files under `mariadb/`
- runtime logs under `data/`

These should remain operational artifacts, not repository content.

## README discipline

Keep the main README lighter.

Move detailed recovery mechanics into dedicated docs and link to them.

## Public positioning

Recommended public identity:

- `invoiceplane-db-import.sh`
- “A self-healing InvoicePlane database import, recovery, and reconciliation tool”

Prefer language like:

- conservative
- staged
- auditable
- backup-first
- app-aware

Avoid language like:

- magic
- one-click for everyone
- first ever
