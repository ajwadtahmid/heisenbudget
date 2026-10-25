import 'package:flutter/material.dart' show ThemeMode;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/currencies.dart';
import '../../core/design/app_colors.dart' show AccentColor;
import '../../core/design/app_font.dart' show AppFont;
import '../../domain/transaction_type.dart';
import '../../domain/week_mode.dart';

/// Everything the Settings screen controls, plus the last-used categories.
class AppSettings {
  const AppSettings({
    required this.currency,
    required this.themeMode,
    required this.accent,
    required this.textFont,
    required this.labFlavor,
    required this.openingBalanceCents,
    required this.onboardingDone,
    required this.weekMode,
    required this.weekStartDay,
    required this.lastExpenseCategoryId,
    required this.lastIncomeCategoryId,
  });

  final Currency currency;

  /// Light, dark, or follow the phone (the default).
  final ThemeMode themeMode;

  /// Colour of interface chrome (buttons, selected states).
  final AccentColor accent;

  /// Font for UI text. Numbers always use Geist Mono.
  final AppFont textFont;

  /// The playful layer: the PURITY readout and instrument-style wording.
  /// The look itself is the same either way.
  final bool labFlavor;

  /// Money you already had when you started. It counts toward the balance but
  /// never toward Received, so monthly numbers stay honest.
  final int openingBalanceCents;

  /// True once the first-run welcome has been finished or skipped.
  final bool onboardingDone;
  final WeekMode weekMode;

  /// 1 = Monday ... 7 = Sunday (ISO).
  final int weekStartDay;
  final int? lastExpenseCategoryId;
  final int? lastIncomeCategoryId;

  /// What amounts are written with, e.g. `৳`.
  String get currencySymbol => currency.symbol;

  int? lastCategoryFor(TransactionType type) => type == TransactionType.expense
      ? lastExpenseCategoryId
      : lastIncomeCategoryId;
}

/// The currency code for a locale such as `bn-BD` (BDT), falling back to USD
/// when the locale is unknown or its currency is not in [currencies].
String defaultCurrencyCodeFor(String localeTag) {
  try {
    final code = NumberFormat.simpleCurrency(locale: localeTag).currencyName;
    if (currencyByCode(code) != null) return code!;
  } catch (_) {
    // Unknown locale: fall through to the default.
  }
  return defaultCurrencyCode;
}

/// Typed wrapper around SharedPreferences. Returns defaults for missing keys.
class SettingsRepository {
  SettingsRepository(this._prefs, {required this.defaultCurrency});

  final SharedPreferences _prefs;

  /// Used until the user picks one (comes from the device locale).
  final String defaultCurrency;

  static const _currencyKey = 'currency_code';
  static const _themeModeKey = 'theme_mode';
  static const _accentKey = 'accent';
  static const _textFontKey = 'text_font';
  static const _labFlavorKey = 'lab_flavor';
  static const _openingBalanceKey = 'opening_balance_cents';
  static const _onboardingKey = 'onboarding_done';
  static const _weekModeKey = 'week_mode';
  static const _weekStartDayKey = 'week_start_day';
  static const _lastExpenseKey = 'last_category_expense';
  static const _lastIncomeKey = 'last_category_income';

  AppSettings load() {
    final storedDay = _prefs.getInt(_weekStartDayKey) ?? 1;
    return AppSettings(
      currency:
          currencyByCode(_prefs.getString(_currencyKey)) ??
          currencyByCode(defaultCurrency) ??
          currencyByCode(defaultCurrencyCode)!,
      themeMode:
          ThemeMode.values.asNameMap()[_prefs.getString(_themeModeKey)] ??
          ThemeMode.system,
      accent: AccentColor.fromName(_prefs.getString(_accentKey)),
      textFont: AppFont.fromName(_prefs.getString(_textFontKey)),
      labFlavor: _prefs.getBool(_labFlavorKey) ?? true,
      openingBalanceCents: _prefs.getInt(_openingBalanceKey) ?? 0,
      onboardingDone: _prefs.getBool(_onboardingKey) ?? false,
      weekMode: _prefs.getString(_weekModeKey) == 'fixed'
          ? WeekMode.fixed
          : WeekMode.calendar,
      weekStartDay: storedDay.clamp(1, 7),
      lastExpenseCategoryId: _prefs.getInt(_lastExpenseKey),
      lastIncomeCategoryId: _prefs.getInt(_lastIncomeKey),
    );
  }

  Future<void> setCurrencyCode(String code) {
    if (currencyByCode(code) == null) {
      throw ArgumentError.value(code, 'code', 'unknown currency');
    }
    return _prefs.setString(_currencyKey, code);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  Future<void> setAccent(AccentColor accent) =>
      _prefs.setString(_accentKey, accent.name);

  Future<void> setTextFont(AppFont font) =>
      _prefs.setString(_textFontKey, font.name);

  Future<void> setLabFlavor(bool value) => _prefs.setBool(_labFlavorKey, value);

  Future<void> setOpeningBalanceCents(int cents) =>
      _prefs.setInt(_openingBalanceKey, cents);

  Future<void> setOnboardingDone(bool value) =>
      _prefs.setBool(_onboardingKey, value);

  Future<void> setWeekMode(WeekMode mode) =>
      _prefs.setString(_weekModeKey, mode.name);

  Future<void> setWeekStartDay(int day) {
    RangeError.checkValueInInterval(day, 1, 7, 'day');
    return _prefs.setInt(_weekStartDayKey, day);
  }

  Future<void> setLastCategory(TransactionType type, int categoryId) {
    final key = type == TransactionType.expense
        ? _lastExpenseKey
        : _lastIncomeKey;
    return _prefs.setInt(key, categoryId);
  }
}
