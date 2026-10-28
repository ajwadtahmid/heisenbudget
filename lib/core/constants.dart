import 'dart:ui' show Locale;

/// App-wide constants.
const appName = 'Heisenbudget';

/// The one language and region of the app. It is English only; dates, numbers
/// and the system dialogs it opens (such as the date picker) use this locale.
const appLocale = Locale('en', 'US');

/// The privacy policy, published on the developer's site. The app does not
/// open it (it has no internet access and no browser plugin); About shows the
/// address and lets you copy it.
const privacyPolicyUrl =
    'https://ajwadtahmid.github.io/privacy-policies/Heisenbudget.html';

/// The logo shown in the app (About, Welcome). It is also what the launcher
/// icons are made from (`tools/make_icon_from_logo.py` draws `logo.svg`).
const appLogoAsset = 'assets/logos/logo.png';

/// Keep in sync with `version:` in pubspec.yaml (no package_info_plus).
const appVersion = '1.0.0';

/// The years a stored date may fall in. Backups accept this whole span, so
/// every date picker offers it too (a restored date must always be editable).
const minDataYear = 1900;
const maxDataYear = 2999;
final earliestDate = DateTime(minDataYear);
final latestDate = DateTime(maxDataYear, 12, 31);

/// Largest amount a single transaction may have, in cents (999,999,999.99).
const maxAmountCents = 99999999999;

/// Maximum characters in a transaction title (a short name such as a shop).
const maxTitleLength = 40;

/// Maximum characters in a transaction note.
const maxNoteLength = 200;

/// Most favorites (one-tap quick adds) a person can keep.
const maxFavorites = 12;

/// Longest favorite name.
const maxFavoriteLabelLength = 30;

/// Characters the new-category field allows, and the longest name stored
/// (a backup or the repository rejects more; older names may be longer than the
/// field now allows, so the stored limit is wider).
const categoryNameFieldLength = 30;
const maxCategoryNameLength = 100;

/// Name of the catch-all category that exists once per type.
const otherCategoryName = 'Other';
