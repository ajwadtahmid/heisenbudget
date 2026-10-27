import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/copy.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_font.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/saved_filter.dart';
import '../domain/transaction_type.dart';
import '../domain/week_mode.dart';

/// Must be overridden in `main()` with the loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final locale = ui.PlatformDispatcher.instance.locale.toLanguageTag();
  return SettingsRepository(
    ref.watch(sharedPreferencesProvider),
    defaultCurrency: defaultCurrencyCodeFor(locale),
  );
});

/// Current settings. Every setter saves, then publishes the new state.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> setCurrencyCode(String code) =>
      _save(() => _repo.setCurrencyCode(code));

  Future<void> setThemeMode(ThemeMode mode) =>
      _save(() => _repo.setThemeMode(mode));

  Future<void> setAccent(AccentColor accent) =>
      _save(() => _repo.setAccent(accent));

  Future<void> setTextFont(AppFont font) =>
      _save(() => _repo.setTextFont(font));

  Future<void> setLabFlavor(bool value) =>
      _save(() => _repo.setLabFlavor(value));

  Future<void> setOpeningBalanceCents(int cents) =>
      _save(() => _repo.setOpeningBalanceCents(cents));

  Future<void> setOnboardingDone(bool value) =>
      _save(() => _repo.setOnboardingDone(value));

  Future<void> setWeekMode(WeekMode mode) =>
      _save(() => _repo.setWeekMode(mode));

  Future<void> setWeekStartDay(int day) =>
      _save(() => _repo.setWeekStartDay(day));

  Future<void> setMonthStartDay(int day) =>
      _save(() => _repo.setMonthStartDay(day));

  Future<void> setFavoriteShortcut(bool value) =>
      _save(() => _repo.setFavoriteShortcut(value));

  Future<void> setSavedFilters(List<SavedFilter> filters) =>
      _save(() => _repo.setSavedFilters(filters));

  Future<void> setBackupReminders(bool value) =>
      _save(() => _repo.setBackupReminders(value));

  Future<void> setBackupSnoozedUntil(DateTime day) =>
      _save(() => _repo.setBackupSnoozedUntil(day));

  Future<void> setLastBackupAt(DateTime when) =>
      _save(() => _repo.setLastBackupAt(when));

  Future<void> setLastCategory(TransactionType type, int categoryId) =>
      _save(() => _repo.setLastCategory(type, categoryId));

  Future<void> _save(Future<void> Function() write) async {
    await write();
    state = _repo.load();
  }
}

/// The wording for the current Lab flavor setting.
final copyProvider = Provider<Copy>(
  (ref) => Copy(lab: ref.watch(settingsProvider.select((s) => s.labFlavor))),
);
