/// App-wide constants.
const appName = 'Heisenbudget';

/// The privacy policy, published on the developer's site. The app does not
/// open it (it has no internet access and no browser plugin); About shows the
/// address and lets you copy it.
const privacyPolicyUrl =
    'https://ajwadtahmid.github.io/privacy-policies/Heisenbudget.html';

/// Keep in sync with `version:` in pubspec.yaml (no package_info_plus).
const appVersion = '1.0.0';

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

/// Name of the catch-all category that exists once per type.
const otherCategoryName = 'Other';
