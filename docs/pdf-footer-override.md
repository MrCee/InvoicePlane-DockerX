# PDF Footer Override

[← Back to README](../README.md)

## Overview

This project intentionally uses a bind-mounted override for `mpdf_helper.php`.

Host path:

```text
./invoiceplane_helpers/mpdf_helper.php
```

Container path:

```text
/var/www/html/application/helpers/mpdf_helper.php
```

The pristine source path inside the image remains:

```text
/var/www/html_default/application/helpers/mpdf_helper.php
```

## Why the override exists

The upstream footer behavior was not clean enough for this project’s needs.

Observed problems included:

- fragmented footer naming
- inconsistent behavior across pages
- quote footer logic that was not aligned cleanly with invoice behavior
- template-level footer control that was misleading compared to helper-level behavior

## Chosen project behavior

This repository now uses a unified footer model that intentionally keeps:

- document reference visible on every page
- page numbers visible on every page
- split footer layout
- invoice and quote footer handling aligned
- helper-level control for stable rendering

Left-side content comes from InvoicePlane footer settings.

That means:

- invoice left footer content = `pdf_invoice_footer`
- quote left footer content = `pdf_quote_footer`

If those settings are blank, the right-side metadata can still remain useful.

## Why bind mount this override

The override is bind mounted on purpose.

That keeps it:

- explicit
- Git-tracked
- rebuild-safe
- easy to diff against upstream
- easy to maintain without hiding changes inside an image layer

## Maintenance notes

When reviewing or changing footer behavior:

- check the host override file first
- confirm the live container path
- compare against the pristine helper when needed

## Related docs

- [Setup](./setup.md)
- [Dev Reset Install](./dev-reset-install.md)
