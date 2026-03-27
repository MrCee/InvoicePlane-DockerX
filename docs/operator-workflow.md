# Operator Workflow

[← Back to README](../README.md)

## Overview

This project is built to be operated through `bin/`, not through ad hoc command memory.

The main idea is simple:

- `bin/` is the control plane
- `docs/` is the knowledge base
- `docker/` is the runtime internals

## Supported startup path

Use:

```bash
./bin/up.sh
```

This is the normal startup path because it does more than a plain compose bring-up.

It:

- loads and patches safe runtime values into `.env`
- prepares host paths
- validates compose
- bootstraps the helper bind mount when required
- starts MariaDB first
- waits for DB health
- starts app services only after DB readiness

## Why this matters

Plain bring-up commands are easy to remember, but they do not by themselves encode your project’s operational discipline.

`bin/up.sh` does.

That makes startup:

- more repeatable
- more observable
- less dependent on memory
- less fragile after long gaps between sessions

## Operating posture

Use the repository in this order:

1. `./bin/up.sh`
2. browser installer / finalizer flow
3. docs-guided recovery tools when needed
4. explicit reset or recovery scripts only when you mean it

## Related docs

- [Emergency Recovery](./emergency-recovery.md)
- [Safety Model](./safety-model.md)
- [DB Import](./invoiceplane-db-import.md)
- [PDF Footer Override](./pdf-footer-override.md)
- [Dev Reset Install](./dev-reset-install.md)

