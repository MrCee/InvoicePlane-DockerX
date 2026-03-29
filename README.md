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

**InvoicePlane-DockerX** is a **rebuild-safe, recovery-aware Docker operating model for InvoicePlane**.

It is designed to behave predictably across:

- fresh installs  
- rebuilds  
- migrations  
- recovery scenarios  

This is not just a container that starts.

It is a system that:

- keeps application, environment, and runtime state aligned  
- prevents configuration drift  
- preserves user data across rebuilds  
- safely introduces new templates and overrides  
- supports schema-aware database recovery  

### Result

- predictable behaviour  
- reproducible environments  
- safe customization  
- reliable recovery across versions  

---

## ⚡ Quick Start (Recommended Path)

### 1. Get the project

```bash
git clone https://github.com/MrCee/InvoicePlane-DockerX.git
cd InvoicePlane-DockerX
```

---

### 2. Prepare your environment

```bash
cp .env.example .env
```

Edit `.env` to suit your system.

---

### 3. Start the stack

```bash
./bin/up.sh
```

This is the **only supported startup method**.

It ensures consistent preparation, validation, and startup behaviour across macOS, Linux, and NAS environments.

For startup and day-to-day operator flow, see:

- [`docs/operations.md`](docs/operations.md)

---

### 4. Complete setup

- open the installer in your browser  
- complete the InvoicePlane setup  
- wait for the finalizer to finish  
- click **Continue to Login**

For the finalize flow and setup behaviour, see:

- [`docs/finalizer.md`](docs/finalizer.md)

---

### 5. Done

You should now have:

- a completed install  
- synchronized `.env` and runtime state  
- no setup or login loops  

---

## 🧱 Architecture Overview

This project separates **source**, **runtime**, and **execution** cleanly:

- `docker/templates/` → authoritative template source  
- `invoiceplane_*` → bind-mounted runtime state  
- container → execution layer  

At startup:

- missing files are seeded safely  
- user changes are preserved  
- managed templates (e.g. `2026*.php`) are enforced  
- runtime stays aligned with the repository  

### Result

- predictable behaviour  
- reproducible environments  
- safe customization  
- reliable recovery across versions  

This provides a production-grade operational baseline without sacrificing flexibility or control.

---

## ✨ What This Setup Actually Does

### 🔁 Operator-first startup

```bash
./bin/up.sh
```

Ensures:

- bind mounts are prepared  
- environment is aligned  
- services start in the correct order  
- database readiness is handled  
- application startup is consistent  

For more operator details, see:

- [`docs/operations.md`](docs/operations.md)

---

### 🧭 Guided install + finalisation

Combines:

- standard InvoicePlane installer  
- backend-aware finalizer  

![InvoicePlane Finalizer](docs/images/finalizer.png)

The finalizer:

- aligns `.env` with runtime state  
- ensures setup completion is correct  
- generates encryption values  
- validates application reachability  
- exposes backend logs  
- provides a clean **Continue to Login** path  

Default templates are applied automatically, so the system is usable immediately after setup.

More:

- [`docs/finalizer.md`](docs/finalizer.md)

---

### 💾 Persistent storage with bind mounts

Key data lives on the host:

- MariaDB data  
- uploads  
- logs  
- finalize state  
- helper overrides  
- views / CSS / language overrides  

This makes:

- rebuilds safe  
- debugging easy  
- customizations visible  
- recovery predictable  

---

### 📄 Document presentation and template system

Provides a **safe, non-destructive customization layer** for invoices and quotes.

Includes:

- 2026 compact invoice and quote templates  
- aligned PDF + web presentation  
- improved footer handling  

#### Behaviour

- templates are seeded automatically  
- existing files are never overwritten  
- user changes are preserved  
- deleted files are restored  
- managed templates (e.g. `2026*.php`) are enforced  

#### Structure

```text
docker/templates/views/
  invoice_templates/
    pdf/
    public/
    html/
  quote_templates/
    pdf/
    public/
    html/
```

#### Result

- consistent document design across PDF and web  
- safe customization without losing defaults  
- upgrade-safe template evolution  

More:

- [`docs/pdf-footer-override.md`](docs/pdf-footer-override.md)

---

### 🛡️ Recovery-first database tooling

Database imports are **reconcile-only**.

Instead of direct imports:

- data is loaded into a temporary database  
- compared against a clean schema  
- merged using controlled strategies  

This approach:

- works across versions  
- tolerates schema differences  
- avoids destructive imports  
- produces safer recovery outcomes  

Run:

```bash
./bin/invoiceplane-db-import.sh
```

More:

- [`docs/recovery.md`](docs/recovery.md)  
- [`docs/table-strategy-matrix.md`](docs/table-strategy-matrix.md)

---

## 🧠 Design Principles

### 🔍 No hidden state

Everything important is visible and inspectable.

---

### 🔁 Host and container must agree

`.env`, runtime, and application state must stay aligned.

---

### 🛠️ No blind operations

- no direct DB imports  
- no silent overwrites  
- no unsafe assumptions  

---

### 🧬 Schema-aware recovery

Data is adapted into the correct schema, not forced into it.

---

### 🔐 Explicit overrides

All overrides are:

- tracked  
- intentional  
- reviewable  

---

### 🧭 Predictable operation

You should always know:

- what state the system is in  
- why it is in that state  
- what will happen next  

---

## 🕹️ Operator Interface

### `bin/` → control plane

- startup  
- recovery  
- reset  
- backup  

---

### `docs/` → knowledge base

- setup  
- operations  
- recovery  
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

Resets:

- MariaDB  
- install state  
- encryption config  

Read first:

- [`docs/dev-reset-install.md`](docs/dev-reset-install.md)

---

## 🌏 Regional language overrides

Customize terminology via:

```text
invoiceplane_language/custom_lang.php
```

Example (Australia):

- ABN  
- GST  

See example implementation:

- [`docs/language-overrides.md`](docs/language-overrides.md)

---

## 🎯 Who This Is For

- developers who want predictable Docker behaviour  
- operators who care about data safety and recovery  
- people migrating older InvoicePlane installs  
- anyone tired of broken imports and setup loops  

---

## 🧭 Where to Go Next

- first install → run `./bin/up.sh`  
- importing old data → see [`docs/recovery.md`](docs/recovery.md)  
- customizing templates → see [`docs/pdf-footer-override.md`](docs/pdf-footer-override.md)  
- regional language changes → see [`docs/language-overrides.md`](docs/language-overrides.md)  
- destructive reset → see [`docs/dev-reset-install.md`](docs/dev-reset-install.md)  

---

## 🧩 Final Thought

This is not:

> “InvoicePlane in Docker”

This is:

> **A rebuild-safe, recovery-aware, state-consistent InvoicePlane operating model.**

---

## ⭐ If This Helped You

Star the repo — it saves real operator time.

