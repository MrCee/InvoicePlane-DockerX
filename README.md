# 🚀 InvoicePlane-DockerX

<div align="center">

![Platform](https://img.shields.io/badge/platform-Docker-blue)
![OS](https://img.shields.io/badge/os-macOS%20%7C%20Linux-lightgrey)
![PHP](https://img.shields.io/badge/php-8.4-blueviolet)
![Database](https://img.shields.io/badge/database-MariaDB_11.8.6-orange)
![App](https://img.shields.io/badge/app-InvoicePlane-6f42c1)
![Workflow](https://img.shields.io/badge/workflow-bin%2Fup.sh-critical)
![Recovery](https://img.shields.io/badge/recovery-first-success)
![Storage](https://img.shields.io/badge/storage-bind--mounted-brightgreen)
![Safety](https://img.shields.io/badge/safety-destructive%20reset%20guarded-red)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 🧠 What This Project Is

**InvoicePlane-DockerX** is a **modern, recovery-aware Docker setup for InvoicePlane** designed to behave predictably across installs, rebuilds, and data recovery scenarios.

This is not just a container that starts.

It is a controlled system that:

- installs cleanly  
- avoids setup and login loops  
- keeps host and container state aligned  
- exposes what the system is actually doing  
- safely recovers older InvoicePlane data across versions  

It is built for the reality that systems do not stay perfect.

They get rebuilt, reset, migrated, and repaired.

---

## 🧩 Why This Repository Exists

Most InvoicePlane Docker setups aim for one thing:

> “Get the container running.”

That is not the hard part.

The real problems show up after that:

- installs that loop or never fully complete  
- `.env` and runtime state drifting out of sync  
- rebuilds breaking previously working systems  
- database imports failing across versions  
- no clear signal that the system is actually ready  

This repository exists to solve those problems.

It introduces:

- a controlled startup interface (`bin/up.sh`)  
- a guided install with a backend-aware finalizer  
- a reconcile-only database import model  
- explicit, host-visible state  
- a recovery-first operating approach  

The goal is simple:

> **Make InvoicePlane safe to run over time — not just easy to start once.**

---

## ✨ What Makes This Different

Most Docker repos stop at:

> “Container is running. Good luck.”

This project goes further.

---

### 🔁 Operator-first startup

The stack should be started through:

```bash
./bin/up.sh
```

Not through ad hoc `docker compose up` commands.

Why?

Because `bin/up.sh` handles what people usually forget:

- prepares bind-mounted directories  
- synchronizes environment expectations  
- validates compose configuration  
- starts services in correct order  
- waits for database readiness  
- ensures application startup stability  

This gives you a **repeatable, predictable startup path**.

Read more:  
[`docs/setup.md`](docs/setup.md)

---

### 🧭 Guided install + finalisation (no setup loops)

This project provides a **guided install flow** combining:

- the standard InvoicePlane installer  
- a backend-aware finalizer  

![InvoicePlane Finalizer](docs/images/finalizer.png)

After completing the installer, the finalizer:

- synchronizes `.env` with container runtime state  
- ensures `SETUP_COMPLETED` and `DISABLE_SETUP` are aligned  
- generates and verifies encryption values  
- validates application reachability  
- exposes a full backend log  
- provides a clear **“Continue to Login”** path  

#### Why this matters

Without this layer, systems commonly fail with:

- setup loops  
- login loops  
- mismatched `.env` vs container state  
- partially completed installs  
- rebuilds breaking previously working setups  

#### What this solves

The finalizer acts as a **single source of truth**, ensuring:

- no hidden getting out of sync between host and container  
- no ambiguity about install completion  
- no guessing when the system is safe to use  

#### Result

- predictable install → login transition  
- faster time to first use  
- dramatically reduced setup failure cases  

---

### 💾 Persistent storage with explicit bind mounts

Important state is kept on the host, not inside containers.

This includes:

- MariaDB data  
- uploads  
- logs  
- finalize state  
- helper overrides  
- views / CSS / language overrides  

This makes:

- rebuilds safe  
- customizations visible  
- debugging easier  
- recovery predictable  

---

### 🛡️ Recovery-first database tooling

This project uses a **reconcile-only import model**.

Instead of importing SQL dumps directly into the live database, data is:

- loaded into a temporary database  
- compared against a fresh installer-created schema  
- merged using controlled strategies  

This approach:

- works across InvoicePlane versions  
- tolerates schema differences  
- avoids fragile direct imports  
- produces consistent, safe recovery results  

Run:

```bash
./bin/invoiceplane-db-import.sh
```

Read more:

- [`docs/recovery.md`](docs/recovery.md)  
- [`docs/table-strategy-matrix.md`](docs/table-strategy-matrix.md)  

---

### 📄 Enhanced PDF footer behavior

This project includes a custom helper override for PDF rendering.

Highlights:

- unified invoice and quote footer behavior  
- split footer layout  
- document reference on every page  
- page numbers on every page  
- consistent multi-page rendering  
- override tracked via bind mount  

Read more:

- [`docs/pdf-footer-override.md`](docs/pdf-footer-override.md)

---

## 🧠 Design Principles

This project is built around a small set of core design choices:

### 🔍 No hidden state

Everything that matters should be:

- visible  
- inspectable  
- traceable  

If something affects runtime behavior, it should not be buried inside a container.

---

### 🔁 No getting out of sync between host and container

The host `.env`, container environment, and application state must agree.

If they do not, the system is considered broken.

The finalizer exists to enforce this alignment.

---

### 🛠️ No blind operations

No direct database imports.  
No silent overwrites.  
No “just run this and hope.”

Every operation should be:

- staged  
- understood  
- controlled  

---

### 🧬 Schema-aware recovery over fragile imports

Data should be adapted into the correct schema, not forced into it.

That is why reconcile-only import exists.

---

### 🔐 Explicit over implicit

Overrides (helpers, views, config) should be:

- bind-mounted  
- tracked in Git  
- easy to audit  

Nothing important should live only inside a container layer.

---

### 🧭 Predictable operation

You should always know:

- what state the system is in  
- why it is in that state  
- what will happen next  

---

## ⚡ Quick Start

### 1. Prepare your environment

```bash
cp .env.example .env
```

Adjust values as needed.

---

### 2. Start the stack (correct way)

```bash
./bin/up.sh
```

This is the **supported startup path**.

---

### 3. Complete setup

- run installer  
- allow finalizer to complete  
- click **Continue to Login**  

---

### 4. Use docs when needed

- [`docs/setup.md`](docs/setup.md)  
- [`docs/recovery.md`](docs/recovery.md)  
- [`docs/dev-reset-install.md`](docs/dev-reset-install.md)  
- [`docs/pdf-footer-override.md`](docs/pdf-footer-override.md)

---

## 🕹️ Operator Interface

### `bin/` → control plane

- startup  
- recovery  
- reset  
- backup  

---

### `docs/` → knowledge base

- safety  
- recovery  
- behavior  
- overrides  

---

### `docker/` → runtime internals

- entrypoints  
- finalizer  
- validation  

---

## 🧼 Clean Rebuild Philosophy

> Rebuild with intent. Never mutate containers casually.

Everything should be:

- explicit  
- reproducible  
- recoverable  

---

## ☠️ Destructive Developer Reset

```bash
./bin/dev-reset-install.sh
```

This will reset:

- MariaDB  
- install state  
- encryption config  

⚠️ Read first:  
[`docs/dev-reset-install.md`](docs/dev-reset-install.md)

---

## 🎯 Who This Is For

- developers who want predictable Docker behavior  
- operators who care about recovery and data safety  
- people migrating old InvoicePlane installs  
- anyone tired of setup loops and broken imports  

---

## 🧩 Final Thought

This is not:

> “InvoicePlane in Docker”

This is:

> **A recovery-aware, rebuild-safe, state-consistent InvoicePlane operating model.**

---

## ⭐ If This Helped You

Star the repo — it saves real operator time.
