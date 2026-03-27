# Execution Report

The recovery/import tool should produce both human-readable and machine-readable reporting.

## Purpose

The report exists so planned action is not confused with actual result.

## Per-table fields

Recommended fields:

- `table_name`
- `category`
- `planned_strategy`
- `attempted_methods`
- `winning_method`
- `verification_mode`
- `final_status`
- `temp_row_count`
- `live_row_count_before`
- `live_row_count_after`
- `note`

## Why this matters

A good report lets an operator answer:

- What was supposed to happen?
- What was actually attempted?
- What finally succeeded?
- How was it verified?
- What still needs manual review?

## Final statuses

Use statuses like:

- `SUCCESS`
- `SUCCESS_WITH_WARNING`
- `MANUAL_REVIEW`
- `FAILED_CRITICAL`

## Verification examples

### Replace mode
- row counts match after replace

### PK merge mode
- temp PK coverage exists in live after merge

### Settings mode
- target keys exist and values match expected merged state

### Custom merge mode
- importable business rows are represented in live
- orphan/null rows are separately reported

## Human-readable summary

At the end of a run, the operator should see a clean summary of:

- live backup path
- temp DB name
- dry-run or live execution mode
- success count
- warning count
- manual review count
- failed critical count
- report locations

## Machine-readable format

A TSV or CSV execution report is enough to start.

JSON is also acceptable if the data remains easy to inspect.

The key requirement is that the report distinguishes:

- plan
- execution
- verification
- final result
