# Operations

[← Back to README](../README.md)

## Overview

This document covers runtime operations and maintenance tasks.

---

## Resetting a User Password

Use:

```bash
./bin/reset-password.sh
```

### Options

- USER_ID
- USER_EMAIL
- TEMP_PASSWORD
- ADMIN_BOOTSTRAP=true (fallback admin selection)

### Examples

Reset by email:

```bash
USER_EMAIL=user@example.com TEMP_PASSWORD=NewPass123! ./bin/reset-password.sh
```

Reset by user ID:

```bash
USER_ID=1 TEMP_PASSWORD=NewPass123! ./bin/reset-password.sh
```

Admin bootstrap (first admin found):

```bash
ADMIN_BOOTSTRAP=true TEMP_PASSWORD=NewPass123! ./bin/reset-password.sh
```

### What it does

- verifies target user exists
- generates secure password hash inside container
- updates user record safely
- clears sessions
- creates a backup of the original row

### Output

- backup stored under `.backup/`
- password is never printed
- confirmation is shown

---

## Notes

- requires running containers
- requires docker compose
- safe to run multiple times
- does not expose secrets in logs

## Related docs

- [Setup and Startup](./setup.md)
- [Finalizer](./finalizer.md)
- [Recovery and Database Import](./recovery.md)
- [Dev Reset Install](./dev-reset-install.md)
