/// App-wide constants.
const appName = 'Heisenbudget';

/// Keep in sync with `version:` in pubspec.yaml (no package_info_plus).
const appVersion = '1.0.0';

/// Largest amount a single transaction may have, in cents (999,999,999.99).
const maxAmountCents = 99999999999;

/// Maximum characters in a transaction note.
const maxNoteLength = 200;

/// Most favorites (one-tap quick adds) a person can keep.
const maxFavorites = 12;

/// Longest favorite name.
const maxFavoriteLabelLength = 30;

/// Name of the catch-all category that exists once per type.
const otherCategoryName = 'Other';
