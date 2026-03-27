# Recovery Philosophy

This repository uses a recovery-first model for InvoicePlane database import and reconciliation.

## Core philosophy

### Temp DB is sacred
The imported old dump is staged into a temporary database and preserved for inspection.

The temp DB is the source of truth for the imported historical data during the recovery run.

### Live DB is backed up first
No live recovery attempt should happen before a live database backup is created.

### No silent schema mutation
The tool should not quietly alter schemas just to make an import appear successful.

### No fake success
A table is not successful because SQL executed. A table is successful when the planned strategy completed and the declared verification passed.

### Classification matters
A standard InvoicePlane table is not automatically an exact-copy table.

Examples:

- a table can be standard and exact
- a table can be standard and additive-compatible
- a table can be standard and still require manual review

## What “self-healing” should mean here

Self-healing should mean:

- strategy-aware fallback
- app-aware table handling
- conservative adaptive execution
- verification-aware outcomes

It should not mean:

- blind retries
- repeating the same failure
- silent forced mutation
- pretending all schema getting out of sync is harmless

## Safety over theatrics

If a table is ambiguous, the correct behaviour is:

- stop
- classify it clearly
- report it
- require manual review if needed

That is safer than aggressive guessing.

## Staged model

The right model is:

1. stage
2. analyze
3. plan
4. execute
5. verify
6. report

That sequence is more important than “finishing everything automatically.”

## Business-value focus

Users care most about whether the core business data came back:

- clients
- invoices
- invoice items
- invoice amounts
- payments
- products

That is why recovery should deliberately treat those tables as a cluster, not as anonymous objects.
