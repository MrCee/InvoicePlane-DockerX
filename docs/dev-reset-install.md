# Dev Reset Install

[← Back to README](../README.md)

## Overview

`./bin/dev-reset-install.sh` is a destructive developer reset.

Its purpose is to return the project to a new-install state and then hand off to:

```bash
./bin/up.sh
```

## What it resets

This workflow is intended to reset installation state, not merely restart containers.

It can remove or recreate:

- `mariadb/`
- `data/finalize/`
- setup completion flags
- encryption values tied to the current install state

## Why the warning matters

This script is dangerous by design.

It is useful during controlled development work, but it should never be treated like a harmless cleanup helper.

If you run it casually, you can erase local MariaDB state and force the stack back toward a fresh install posture.

## Operating rule

Read the warning.
Respect the prompt.
Use it only when you actually want to destroy local install state.

## Supported flow

1. stop the running stack
2. confirm destructive intent
3. reset install-related state
4. hand off to `./bin/up.sh` with full rebuild

## Related docs

- [Operator Workflow](./operator-workflow.md)
- [Emergency Recovery](./emergency-recovery.md)

