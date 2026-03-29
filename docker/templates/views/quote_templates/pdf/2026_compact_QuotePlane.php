<?php
// Fix item table head when numerous (>= 12) items (overflowing in 2nd page)
$add_table_and_head_for_sums = 1; // Set to 0/false/null/'', return to original IP

// Init vars
$colspan = $show_item_discounts ? 5 : 4;

$client_contact_name = '';
if (isset($custom_fields['client']['Contact Name']) && !empty($custom_fields['client']['Contact Name'])) {
    $client_contact_name = $custom_fields['client']['Contact Name'];
}
?><!DOCTYPE html>
<html lang="<?php _trans('cldr'); ?>">
<head>
    <meta charset="utf-8">
    <title><?php echo get_setting('custom_title', 'InvoicePlane', true); ?> - <?php _trans('quote'); ?></title>
    <link rel="stylesheet" href="<?php _theme_asset('css/templates.css'); ?>" type="text/css">
    <link rel="stylesheet" href="<?php _core_asset('css/custom-pdf.css'); ?>" type="text/css">
</head>
<body>

<header class="clearfix">
    <div id="logo" style="margin-bottom: 18px; padding: 5px 0;">
        <?php echo invoice_logo_pdf(); ?>
    </div>

    <table style="width:100%; border-collapse:collapse;" cellspacing="0" cellpadding="0">
        <tr>
            <td style="width:52%; vertical-align:top; text-align:left; padding-right:14px;">
                <div id="client">
                    <div><b><?php _htmlsc(format_client($quote)); ?></b></div>
<?php
if ($quote->client_vat_id) {
    echo '<div>' . trans('vat_id_short') . ': ' . htmlsc($quote->client_vat_id) . '</div>';
}
if ($quote->client_tax_code) {
    echo '<div>' . trans('tax_code_short') . ': ' . htmlsc($quote->client_tax_code) . '</div>';
}
if ($quote->client_address_1) {
    echo '<div>' . htmlsc($quote->client_address_1) . '</div>';
}
if ($quote->client_address_2) {
    echo '<div>' . htmlsc($quote->client_address_2) . '</div>';
}
if ($quote->client_city || $quote->client_state || $quote->client_zip) {
    echo '<div>';
    if ($quote->client_city) {
        echo htmlsc($quote->client_city);
        if ($quote->client_state || $quote->client_zip) {
            echo ', ';
        }
    }
    if ($quote->client_state) {
        echo htmlsc($quote->client_state) . ' ';
    }
    if ($quote->client_zip) {
        echo htmlsc($quote->client_zip);
    }
    echo '</div>';
}
if ($quote->client_country) {
    echo '<div>' . get_country_name(trans('cldr'), htmlsc($quote->client_country)) . '</div>';
}
if ($client_contact_name) {
    echo '<div>Contact: ' . htmlsc($client_contact_name) . '</div>';
}
if ($quote->client_email) {
    echo '<div>' . htmlsc($quote->client_email) . '</div>';
}

echo '<br>';

if ($quote->client_phone) {
    echo '<div>' . trans('phone_abbr') . ': ' . htmlsc($quote->client_phone) . '</div>';
}
?>
                </div>

                <div style="margin-top: 16px;">
                    <h1 class="invoice-title" style="margin:0;">
                        <?php _trans('quote') ?> <?php _htmlsc($quote->quote_number) ?>
                    </h1>
                </div>
            </td>

            <td style="width:48%; vertical-align:top; text-align:right; padding-left:14px;">
                <div id="company">
                    <div><b><?php _htmlsc($quote->user_name); ?></b></div>
<?php
if ($quote->user_vat_id) {
    echo '<div>' . trans('vat_id_short') . ': ' . htmlsc($quote->user_vat_id) . '</div>';
}
if ($quote->user_tax_code) {
    echo '<div>' . trans('tax_code_short') . ': ' . htmlsc($quote->user_tax_code) . '</div>';
}
if ($quote->user_address_1) {
    echo '<div>' . htmlsc($quote->user_address_1) . '</div>';
}
if ($quote->user_address_2) {
    echo '<div>' . htmlsc($quote->user_address_2) . '</div>';
}
if ($quote->user_city || $quote->user_state || $quote->user_zip) {
    echo '<div>';
    if ($quote->user_city) {
        echo htmlsc($quote->user_city);
        if ($quote->user_state || $quote->user_zip) {
            echo ', ';
        }
    }
    if ($quote->user_state) {
        echo htmlsc($quote->user_state) . ' ';
    }
    if ($quote->user_zip) {
        echo htmlsc($quote->user_zip);
    }
    echo '</div>';
}
if ($quote->user_country) {
    echo '<div>' . get_country_name(trans('cldr'), htmlsc($quote->user_country)) . '</div>';
}

echo '<br>';

if ($quote->user_phone) {
    echo '<div>' . trans('phone_abbr') . ': ' . htmlsc($quote->user_phone) . '</div>';
}
if ($quote->user_fax) {
    echo '<div>' . trans('fax_abbr') . ': ' . htmlsc($quote->user_fax) . '</div>';
}
?>
                </div>

                <div class="invoice-details clearfix" style="margin-top: 12px;">
                    <table style="width:100%; border-collapse:collapse; margin-left:auto;" cellspacing="0" cellpadding="0">
                        <tr>
                            <td style="text-align:left; padding:2px 0;"><?php _trans('quote_date'); ?>:</td>
                            <td style="text-align:right; padding:2px 0;"><?php echo date_from_mysql($quote->quote_date_created, true); ?></td>
                        </tr>
                        <tr>
                            <td style="text-align:left; padding:2px 0;"><?php _trans('expires'); ?>:</td>
                            <td style="text-align:right; padding:2px 0;">
                                <?php echo $quote->quote_date_expires ? date_from_mysql($quote->quote_date_expires, true) : ''; ?>
                            </td>
                        </tr>
                        <tr>
                            <td style="text-align:left; padding:2px 0;"><?php _trans('total'); ?>:</td>
                            <td style="text-align:right; padding:2px 0;"><?php echo format_currency($quote->quote_total); ?></td>
                        </tr>
                    </table>
                </div>
            </td>
        </tr>
    </table>
</header>

<main>

    <table class="item-table" style="width:100%; margin-top:12px;" cellspacing="0" cellpadding="0">
        <thead>
        <tr>
            <th class="item-name"><?php _trans('item'); ?></th>
            <th class="item-desc"><?php _trans('description'); ?></th>
            <th class="item-amount text-right"><?php _trans('qty'); ?></th>
            <th class="item-price text-right"><?php _trans('price'); ?></th>
<?php
if ($show_item_discounts) {
?>
            <th class="item-discount text-right"><?php _trans('discount'); ?></th>
<?php
}
?>
            <th class="item-total text-right"><?php _trans('total'); ?></th>
        </tr>
        </thead>
        <tbody>

<?php
foreach ($items as $item) {
?>
            <tr>
                <td style="vertical-align:top;"><?php _htmlsc($item->item_name); ?></td>
                <td style="vertical-align:top;"><?php echo nl2br(htmlsc($item->item_description)); ?></td>
                <td class="text-right" style="vertical-align:top;">
                    <?php echo format_quantity($item->item_quantity); ?>
<?php
    if ($item->item_product_unit) {
?>
                    <br>
                    <small><?php _htmlsc($item->item_product_unit); ?></small>
<?php
    }
?>
                </td>
                <td class="text-right" style="vertical-align:top;">
                    <?php echo format_currency(htmlsc($item->item_price)); ?>
                </td>
<?php
    if ($show_item_discounts) {
?>
                <td class="text-right" style="vertical-align:top;">
                    <?php echo format_currency($item->item_discount); ?>
                </td>
<?php
    }
?>
                <td class="text-right" style="vertical-align:top;">
                    <?php echo format_currency(htmlsc($item->item_total)); ?>
                </td>
            </tr>
<?php
}
?>

        </tbody>

<?php
// Fix for mpdf: table head of items printed on 2nd page
if ($add_table_and_head_for_sums) {
    $colspan .= '" style="width:543px';
?>
    </table>

    <table class="item-table" style="width:100%;" cellspacing="0" cellpadding="0">
        <thead>
        <tr>
            <th colspan="<?php echo $colspan ?>">&nbsp;</th>
            <th class="text-right"><?php _trans('total'); ?></th>
        </tr>
        </thead>
<?php
}
?>

        <tbody class="invoice-sums">

<?php
if ( ! $legacy_calculation) {
    discount_global_print_in_pdf($quote, $show_item_discounts, 'quote');
}
?>

        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <?php _trans('subtotal'); ?>
            </td>
            <td class="text-right">
                <?php echo format_currency($quote->quote_item_subtotal); ?>
            </td>
        </tr>

<?php
if ($quote->quote_item_tax_total > 0) {
?>
        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <?php _trans('item_tax'); ?>
            </td>
            <td class="text-right">
                <?php echo format_currency($quote->quote_item_tax_total); ?>
            </td>
        </tr>
<?php
}
?>

<?php
foreach ($quote_tax_rates as $quote_tax_rate) {
?>
        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <?php echo htmlsc($quote_tax_rate->quote_tax_rate_name) . ' (' . format_amount($quote_tax_rate->quote_tax_rate_percent) . '%)'; ?>
            </td>
            <td class="text-right">
                <?php echo format_currency($quote_tax_rate->quote_tax_rate_amount); ?>
            </td>
        </tr>
<?php
}
?>

<?php
if ($legacy_calculation) {
    discount_global_print_in_pdf($quote, $show_item_discounts, 'quote');
}
?>

<?php if ($quote->quote_discount_percent != '0.00') { ?>
        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <?php _trans('discount'); ?> (%)
            </td>
            <td class="text-right">
                <?php echo format_amount(htmlsc($quote->quote_discount_percent)); ?>%
            </td>
        </tr>
<?php } ?>

<?php if ($quote->quote_discount_amount != '0.00') { ?>
        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <?php _trans('discount'); ?>
            </td>
            <td class="text-right">
                <?php echo format_currency(htmlsc($quote->quote_discount_amount)); ?>
            </td>
        </tr>
<?php } ?>

        <tr>
            <td class="text-right" colspan="<?php echo $colspan ?>">
                <b><?php _trans('total'); ?></b>
            </td>
            <td class="text-right">
                <b><?php echo format_currency(htmlsc($quote->quote_total)); ?></b>
            </td>
        </tr>
        </tbody>
    </table>
</main>

<div class="invoice-terms">
<?php
if ($quote->notes) {
?>
    <div class="notes">
        <b><?php _trans('notes'); ?></b><br/>
        <?php echo nl2br(htmlsc($quote->notes)); ?>
    </div>
<?php
}
?>
</div>
<sethtmlpagefooter name="defaultFooter" value="on" />
<!-- To use the template with page numbering, uncomment the following line -->
<!-- <sethtmlpagefooter name="footerWithPageNumbers" value="on" /> -->
</body>
</html>
