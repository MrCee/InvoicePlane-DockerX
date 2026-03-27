# Safety Model

This document explains what the InvoicePlane DB import tool should and should not do.

## Safety guarantees

### Backup first
The tool must create a live DB backup before any live mutation.

### Temp import first
Old dumps are first imported into a temp DB, not directly into the live DB.

### Explicit strategy only
Every table should be handled by a known strategy, not by implication.

### Verification is mandatory
Execution without verification is not success.

## Dry-run contract

Dry run should allow:

- temp DB recreation
- dump import
- schema analysis
- plan/report generation

Dry run should not allow:

- truncating live tables
- inserting into live tables
- updating live settings
- live custom-table promotion

Expected console messaging:

- `DRY RUN: no live changes applied`

## Strategy categories

Examples of useful strategy categories:

- `EXACT_REPLACE`
- `ADDITIVE_MAPPED_REPLACE`
- `KEY_BASED_MERGE`
- `CUSTOM_FIELD_MERGE`
- `SKIP`
- `MANUAL_REVIEW`

## Final statuses

Recommended final statuses:

- `SUCCESS`
- `SUCCESS_WITH_WARNING`
- `MANUAL_REVIEW`
- `FAILED_CRITICAL`

## Verification modes

Verification should match the strategy.

### Replace-mode tables
Acceptable verification:

- row count match between temp and live after replace

### Merge or PK-based tables
Acceptable verification:

- primary-key coverage from temp exists in live after merge

### Settings merge
Acceptable verification:

- expected keys exist in live
- expected values match temp for merged keys
- skipped keys are explicitly reported

### Custom field tables
Acceptable verification:

- importable `(owner_id, field_id)` source coverage exists in live
- orphan and null/blank rows are separately reported

## What the tool should not do

- silently mutate schemas
- silently drop ambiguous data
- silently append on anchor mismatch
- silently pretend verification succeeded
- claim a broad recovery success when core tables failed

## Operational discipline

The repository should not track mutable business/runtime outputs, including:

- generated live backups
- mutable MariaDB state
- runtime logs
- imported business dumps
- temp execution artifacts
