# Finalizer

[← Back to README](../README.md)

## Overview

The finalizer completes setup as an operational step, not a guess.

It ensures the application, environment, and runtime state are aligned.

## What it does

- marks setup complete
- aligns `.env` with runtime
- generates encryption values
- recreates the app container correctly
- validates reachability

## Operator flow

1. run `./bin/up.sh`
2. complete installer
3. wait for finalizer
4. proceed to login

## State location

```text
./data/finalize/
```

- status.json
- finalizer.log

## Related docs

- [Setup and Startup](./setup.md)
- [Operations](./operations.md)
- [Recovery and Database Import](./recovery.md)
