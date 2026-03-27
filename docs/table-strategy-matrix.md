# Table Strategy Matrix

This file describes how major InvoicePlane tables should be treated by the recovery/import tool.

## Core recovery cluster

These tables should be treated as a business-critical cluster:

- `ip_clients`
- `ip_products`
- `ip_invoices`
- `ip_invoice_items`
- `ip_invoice_amounts`
- `ip_invoice_item_amounts`
- `ip_payments`
- `ip_payment_methods`

## Typical strategy guidance

| Table / Group | Typical Handling | Notes |
|---|---|---|
| `ip_invoices` | Exact replace when schema matches after harmless normalization | Core billing record |
| `ip_invoice_items` | Exact replace when safe | Should align with invoices |
| `ip_invoice_amounts` | Exact replace when safe | Financial totals |
| `ip_invoice_item_amounts` | Exact replace when safe | Item totals |
| `ip_payments` | Exact replace or key-aware handling depending on getting out of sync | Financial event table |
| `ip_products` | Exact replace or additive mapping depending on schema getting out of sync | Business catalogue |
| `ip_clients` | Additive mapped replace if live has new safe columns | Standard table, but often drifted |
| `ip_settings` | Key-based merge | Do not treat as blind replace |
| `ip_custom_fields` | Definition-aware restore/merge | Supports custom value tables |
| `ip_*_custom` tables | Custom-field-aware merge | Requires orphan/null reporting |
| users/sessions/imports/log/version style tables | Skip or special handling | Not generic business promotion targets |

## Important distinction

A table being “standard” does not mean it is `EXACT`.

Example:

- `ip_invoices` can be standard and exact
- `ip_clients` can be standard and additive-compatible

That is expected and correct.

## Manual-review triggers

A table should move toward manual review when:

- temp has columns missing in live
- live introduces new required columns with no safe default
- type mismatch exists on shared columns
- nullability creates unsafe write semantics
- strategy-specific verification fails

## Reporting expectation

Every handled table should end up with:

- planned strategy
- attempted methods
- winning method
- verification mode
- final status
