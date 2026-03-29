# Language overrides

InvoicePlane-DockerX supports language string overrides through:

```php
invoiceplane_language/custom_lang.php
```

This file lets you override selected labels without modifying the main language file.

## Australian example

For an Australian setup, a common customization is to replace:

- `VAT ID` → `ABN`
- `Item Tax` → `GST`

Use this in `custom_lang.php`:

```php
<?php

$lang = [
    'vat_id'       => 'ABN',
    'vat_id_short' => 'ABN',
    'item_tax'     => 'GST',
];
```

## Notes

- Keep the file as a normal PHP array assignment.
- Add each override on its own line.
- Existing upstream language files remain untouched.
- `custom_lang.php` is the intended place for regional wording changes.
