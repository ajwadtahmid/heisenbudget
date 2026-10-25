/// A currency the user can pick in Settings. Only the symbol is used when
/// showing amounts: there is no conversion.
class Currency {
  const Currency(this.code, this.name, this.symbol);

  /// ISO 4217 code, e.g. `BDT`.
  final String code;
  final String name;
  final String symbol;

  /// `৳ Bangladeshi Taka (BDT)`
  String get label => '$symbol $name ($code)';
}

const defaultCurrencyCode = 'USD';

/// Common world currencies, including Bangladesh (listed by code).
const currencies = <Currency>[
  Currency('AED', 'UAE Dirham', 'AED'),
  Currency('ARS', 'Argentine Peso', 'AR\$'),
  Currency('AUD', 'Australian Dollar', 'A\$'),
  Currency('BDT', 'Bangladeshi Taka', '৳'),
  Currency('BRL', 'Brazilian Real', 'R\$'),
  Currency('CAD', 'Canadian Dollar', 'C\$'),
  Currency('CHF', 'Swiss Franc', 'CHF'),
  Currency('CLP', 'Chilean Peso', 'CL\$'),
  Currency('CNY', 'Chinese Yuan', '¥'),
  Currency('COP', 'Colombian Peso', 'CO\$'),
  Currency('CZK', 'Czech Koruna', 'Kč'),
  Currency('DKK', 'Danish Krone', 'kr'),
  Currency('EGP', 'Egyptian Pound', 'E£'),
  Currency('EUR', 'Euro', '€'),
  Currency('GBP', 'British Pound', '£'),
  Currency('GHS', 'Ghanaian Cedi', 'GH₵'),
  Currency('HKD', 'Hong Kong Dollar', 'HK\$'),
  Currency('HUF', 'Hungarian Forint', 'Ft'),
  Currency('IDR', 'Indonesian Rupiah', 'Rp'),
  Currency('ILS', 'Israeli Shekel', '₪'),
  Currency('INR', 'Indian Rupee', '₹'),
  Currency('JPY', 'Japanese Yen', '¥'),
  Currency('KES', 'Kenyan Shilling', 'KSh'),
  Currency('KRW', 'South Korean Won', '₩'),
  Currency('KWD', 'Kuwaiti Dinar', 'KWD'),
  Currency('LKR', 'Sri Lankan Rupee', 'Rs'),
  Currency('MAD', 'Moroccan Dirham', 'MAD'),
  Currency('MXN', 'Mexican Peso', 'MX\$'),
  Currency('MYR', 'Malaysian Ringgit', 'RM'),
  Currency('NGN', 'Nigerian Naira', '₦'),
  Currency('NOK', 'Norwegian Krone', 'kr'),
  Currency('NPR', 'Nepalese Rupee', 'Rs'),
  Currency('NZD', 'New Zealand Dollar', 'NZ\$'),
  Currency('PEN', 'Peruvian Sol', 'S/'),
  Currency('PHP', 'Philippine Peso', '₱'),
  Currency('PKR', 'Pakistani Rupee', 'Rs'),
  Currency('PLN', 'Polish Zloty', 'zł'),
  Currency('QAR', 'Qatari Riyal', 'QAR'),
  Currency('RUB', 'Russian Ruble', '₽'),
  Currency('SAR', 'Saudi Riyal', 'SAR'),
  Currency('SEK', 'Swedish Krona', 'kr'),
  Currency('SGD', 'Singapore Dollar', 'S\$'),
  Currency('THB', 'Thai Baht', '฿'),
  Currency('TRY', 'Turkish Lira', '₺'),
  Currency('TWD', 'New Taiwan Dollar', 'NT\$'),
  Currency('UAH', 'Ukrainian Hryvnia', '₴'),
  Currency('USD', 'US Dollar', '\$'),
  Currency('VND', 'Vietnamese Dong', '₫'),
  Currency('ZAR', 'South African Rand', 'R'),
];

/// [currencies] ordered by name, as shown in the Settings dropdown.
final currenciesByName = [...currencies]
  ..sort((a, b) => a.name.compareTo(b.name));

/// The currency with this code, or null if it is not in [currencies].
Currency? currencyByCode(String? code) {
  for (final c in currencies) {
    if (c.code == code) return c;
  }
  return null;
}
