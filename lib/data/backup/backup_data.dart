import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;

import '../../core/category_icons.dart' show defaultCategoryIconKey;
import '../../core/constants.dart';
import '../../core/currencies.dart';
import '../../core/design/app_colors.dart' show AccentColor;
import '../../core/design/app_font.dart' show AppFont;
import '../../domain/budget.dart';
import '../../domain/iso_date.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import '../../domain/week_mode.dart';
import '../database/app_database.dart';

/// Written into every backup so other files are recognised and rejected.
const backupAppId = 'heisenbudget';

/// Bump only when the file layout changes in a way old readers cannot handle.
/// Newer apps must keep reading every older version.
const backupFormatVersion = 1;

/// A real backup is far smaller; this only stops a wrong, huge file from being
/// loaded into memory.
const maxBackupBytes = 50 * 1024 * 1024;

/// A backup file that cannot be restored. [message] is safe to show.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The settings a backup carries. A field is null when the file did not have
/// it (or had a value this version does not understand); restoring leaves
/// those settings as they are.
class BackupSettings {
  const BackupSettings({
    this.currency,
    this.themeMode,
    this.accent,
    this.textFont,
    this.labFlavor,
    this.openingBalanceCents,
    this.weekMode,
    this.weekStartDay,
    this.monthStartDay,
  });

  final String? currency;
  final String? themeMode;
  final String? accent;
  final String? textFont;
  final bool? labFlavor;
  final int? openingBalanceCents;
  final String? weekMode;
  final int? weekStartDay;
  final int? monthStartDay;

  Map<String, Object?> toJson() => {
    'currency': currency,
    'themeMode': themeMode,
    'accent': accent,
    'textFont': textFont,
    'labFlavor': labFlavor,
    'openingBalanceCents': openingBalanceCents,
    'weekMode': weekMode,
    'weekStartDay': weekStartDay,
    'monthStartDay': monthStartDay,
  };

  /// Reads whatever it understands and ignores the rest.
  factory BackupSettings.fromJson(Object? json) {
    final m = json is Map<String, Object?> ? json : const <String, Object?>{};

    String? oneOf(String key, Iterable<String> allowed) {
      final v = m[key];
      return v is String && allowed.contains(v) ? v : null;
    }

    final currency = m['currency'];
    final opening = m['openingBalanceCents'];
    final day = m['weekStartDay'];
    final monthDay = m['monthStartDay'];
    final lab = m['labFlavor'];
    return BackupSettings(
      currency: currency is String && currencyByCode(currency) != null
          ? currency
          : null,
      themeMode: oneOf('themeMode', ThemeMode.values.asNameMap().keys),
      accent: oneOf('accent', AccentColor.values.asNameMap().keys),
      textFont: oneOf('textFont', AppFont.values.asNameMap().keys),
      labFlavor: lab is bool ? lab : null,
      openingBalanceCents:
          opening is int &&
              opening >= -maxAmountCents &&
              opening <= maxAmountCents
          ? opening
          : null,
      weekMode: oneOf('weekMode', WeekMode.values.asNameMap().keys),
      weekStartDay: day is int && day >= 1 && day <= 7 ? day : null,
      monthStartDay: monthDay is int && monthDay >= 1 && monthDay <= 28
          ? monthDay
          : null,
    );
  }
}

/// Everything a backup file holds, already checked: ids are unique, every
/// transaction points at a category of its own type, dates are real dates.
class BackupData {
  const BackupData({
    required this.exportedAt,
    required this.settings,
    required this.categories,
    required this.recurringRules,
    required this.favorites,
    required this.budgetLimits,
    required this.transactions,
  });

  final DateTime exportedAt;
  final BackupSettings settings;
  final List<CategoryRow> categories;
  final List<RecurringRuleRow> recurringRules;
  final List<FavoriteRow> favorites;
  final List<BudgetLimitRow> budgetLimits;
  final List<TransactionRow> transactions;

  /// The file's text. Pretty-printed so it can be inspected in any editor.
  String encode() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': backupAppId,
      'format': backupFormatVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'categories': [
        for (final c in categories)
          {
            'id': c.id,
            'name': c.name,
            'type': c.type.name,
            'icon': c.icon,
            'isDefault': c.isDefault,
            'isArchived': c.isArchived,
            'isProtected': c.isProtected,
            'sortOrder': c.sortOrder,
          },
      ],
      'recurringRules': [
        for (final r in recurringRules)
          {
            'id': r.id,
            'amountCents': r.amountCents,
            'type': r.type.name,
            'categoryId': r.categoryId,
            'note': r.note,
            'title': r.title,
            'unit': r.unit.name,
            'interval': r.interval,
            'startDate': r.startDate,
            'endDate': r.endDate,
            'isActive': r.isActive,
            'nextIndex': r.nextIndex,
            'createdAt': r.createdAt.toUtc().toIso8601String(),
          },
      ],
      'favorites': [
        for (final f in favorites)
          {
            'id': f.id,
            'label': f.label,
            'type': f.type.name,
            'amountCents': f.amountCents,
            'categoryId': f.categoryId,
            'note': f.note,
            'title': f.title,
            'sortOrder': f.sortOrder,
            'createdAt': f.createdAt.toUtc().toIso8601String(),
          },
      ],
      'budgetLimits': [
        for (final b in budgetLimits)
          {
            'id': b.id,
            'categoryId': b.categoryId,
            'unit': b.unit.name,
            'repeats': b.repeats,
            'start': b.start,
            'amountCents': b.amountCents,
            'createdAt': b.createdAt.toUtc().toIso8601String(),
          },
      ],
      'transactions': [
        for (final t in transactions)
          {
            'id': t.id,
            'amountCents': t.amountCents,
            'type': t.type.name,
            'date': t.date,
            'categoryId': t.categoryId,
            'note': t.note,
            'title': t.title,
            'createdAt': t.createdAt.toUtc().toIso8601String(),
            'updatedAt': t.updatedAt.toUtc().toIso8601String(),
            'recurringRuleId': t.recurringRuleId,
          },
      ],
    });
  }

  /// Reads and checks a backup file. Throws [BackupFormatException] with a
  /// plain-language reason and never returns half-valid data.
  factory BackupData.parse(Uint8List bytes) {
    if (bytes.length > maxBackupBytes) {
      throw const BackupFormatException(
        'That file is too large to be a backup.',
      );
    }
    const notBackup = BackupFormatException(
      'That file is not a Heisenbudget backup.',
    );
    final Object? root;
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('﻿')) text = text.substring(1);
      root = jsonDecode(text);
    } on FormatException {
      throw notBackup;
    }
    if (root is! Map<String, Object?> || root['app'] != backupAppId) {
      throw notBackup;
    }
    final format = root['format'];
    if (format is! int || format < 1) throw notBackup;
    if (format > backupFormatVersion) {
      throw const BackupFormatException(
        'This backup was made by a newer version of Heisenbudget. '
        'Update the app and try again.',
      );
    }

    final categories = _parseCategories(root['categories']);
    final byId = {for (final c in categories) c.id: c};
    final rules = _parseRules(root['recurringRules'], byId);
    final favorites = _parseFavorites(root['favorites'], byId);
    final settings = BackupSettings.fromJson(root['settings']);
    final limits = _parseBudgetLimits(
      root['budgetLimits'],
      byId,
      monthStartDay: settings.monthStartDay ?? 1,
    );
    final transactions = _parseTransactions(root['transactions'], byId, {
      for (final r in rules) r.id,
    });

    final exported = root['exportedAt'];
    return BackupData(
      exportedAt:
          (exported is String ? DateTime.tryParse(exported) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      settings: settings,
      categories: categories,
      recurringRules: rules,
      favorites: favorites,
      budgetLimits: limits,
      transactions: transactions,
    );
  }
}

BackupFormatException _damaged(String where, String what) =>
    BackupFormatException('This backup file is damaged ($where: $what).');

List<CategoryRow> _parseCategories(Object? json) {
  if (json is! List) throw _damaged('categories', 'missing');
  final rows = <CategoryRow>[];
  final ids = <int>{};
  final names = <String>{};
  for (final item in json) {
    if (item is! Map<String, Object?>) {
      throw _damaged('category', 'not an object');
    }
    final id = item['id'];
    if (id is! int || id < 1 || !ids.add(id)) {
      throw _damaged('category', 'bad or repeated id');
    }
    final where = 'category $id';
    final name = item['name'];
    if (name is! String || name.trim().isEmpty) {
      throw _damaged(where, 'no name');
    }
    final type = _type(item['type']);
    if (type == null) throw _damaged(where, 'unknown type');
    if (!names.add('${type.name}:${name.trim().toLowerCase()}')) {
      throw _damaged(where, 'duplicate name');
    }
    final icon = item['icon'];
    final sortOrder = item['sortOrder'];
    rows.add(
      CategoryRow(
        id: id,
        name: name.trim(),
        type: type,
        icon: icon is String && icon.isNotEmpty ? icon : defaultCategoryIconKey,
        isDefault: item['isDefault'] == true,
        isArchived: item['isArchived'] == true,
        isProtected: item['isProtected'] == true,
        sortOrder: sortOrder is int ? sortOrder : 0,
      ),
    );
  }
  return rows;
}

/// Backups made before repeating transactions existed have no
/// `recurringRules`; that restores as "no rules".
List<RecurringRuleRow> _parseRules(
  Object? json,
  Map<int, CategoryRow> categories,
) {
  if (json == null) return const [];
  if (json is! List) throw _damaged('recurring rules', 'not a list');
  final rows = <RecurringRuleRow>[];
  final ids = <int>{};
  for (final item in json) {
    if (item is! Map<String, Object?>) {
      throw _damaged('recurring rule', 'not an object');
    }
    final id = item['id'];
    if (id is! int || id < 1 || !ids.add(id)) {
      throw _damaged('recurring rule', 'bad or repeated id');
    }
    final where = 'recurring rule $id';
    final amount = item['amountCents'];
    if (amount is! int || amount < 1 || amount > maxAmountCents) {
      throw _damaged(where, 'amount out of range');
    }
    final type = _type(item['type']);
    if (type == null) throw _damaged(where, 'unknown type');
    final category = categories[item['categoryId']];
    if (category == null) throw _damaged(where, 'unknown category');
    if (category.type != type) throw _damaged(where, 'category type differs');
    final unit = item['unit'] is String
        ? RecurrenceUnit.values.asNameMap()[item['unit']]
        : null;
    if (unit == null) throw _damaged(where, 'unknown repeat unit');
    final interval = item['interval'];
    if (interval is! int || interval < 1 || interval > maxRecurrenceInterval) {
      throw _damaged(where, 'repeat interval out of range');
    }
    final start = item['startDate'];
    if (start is! String || !_isRealDate(start)) {
      throw _damaged(where, 'start date is not a real date');
    }
    final end = item['endDate'];
    if (end != null &&
        (end is! String || !_isRealDate(end) || end.compareTo(start) < 0)) {
      throw _damaged(where, 'end date is not valid');
    }
    final next = item['nextIndex'];
    if (next is! int || next < 0 || next > 100000000) {
      throw _damaged(where, 'bad schedule position');
    }
    final note = item['note'];
    if (note != null && (note is! String || note.length > maxNoteLength)) {
      throw _damaged(where, 'bad note');
    }
    final title = _title(item['title'], where);
    final created = _time(item['createdAt']);
    if (created == null) throw _damaged(where, 'bad timestamp');
    final clean = (note as String?)?.trim();
    rows.add(
      RecurringRuleRow(
        id: id,
        amountCents: amount,
        type: type,
        categoryId: category.id,
        note: clean == null || clean.isEmpty ? null : clean,
        title: title,
        unit: unit,
        interval: interval,
        startDate: start,
        endDate: end as String?,
        isActive: item['isActive'] != false,
        nextIndex: next,
        createdAt: created,
      ),
    );
  }
  return rows;
}

/// Backups made before budgets existed have no `budgetLimits`; that restores
/// as "no limits". Limits written when budgets were monthly only have a
/// `startMonth` (`2026-10`) and no `unit`: they read as repeating monthly
/// limits starting on that budget month's first day.
List<BudgetLimitRow> _parseBudgetLimits(
  Object? json,
  Map<int, CategoryRow> categories, {
  required int monthStartDay,
}) {
  if (json == null) return const [];
  if (json is! List) throw _damaged('budget limits', 'not a list');
  if (json.length > 10000) throw _damaged('budget limits', 'far too many');
  final rows = <BudgetLimitRow>[];
  final ids = <int>{};
  final seen = <String>{};
  for (final item in json) {
    if (item is! Map<String, Object?>) {
      throw _damaged('budget limit', 'not an object');
    }
    final id = item['id'];
    if (id is! int || id < 1 || !ids.add(id)) {
      throw _damaged('budget limit', 'bad or repeated id');
    }
    final where = 'budget limit $id';
    final categoryId = item['categoryId'];
    if (categoryId != null) {
      final category = categories[categoryId];
      if (category == null) throw _damaged(where, 'unknown category');
      if (category.type != TransactionType.expense) {
        throw _damaged(where, 'not an expense category');
      }
    }

    // The older monthly form: only `startMonth`.
    final legacyMonth = item['startMonth'];
    final BudgetUnit unit;
    final String start;
    if (item['unit'] == null && legacyMonth != null) {
      if (legacyMonth is! String ||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(legacyMonth)) {
        throw _damaged(where, 'bad month');
      }
      unit = BudgetUnit.month;
      start = '$legacyMonth-${monthStartDay.toString().padLeft(2, '0')}';
    } else {
      final name = item['unit'];
      final parsed = name is String
          ? BudgetUnit.values.asNameMap()[name]
          : null;
      if (parsed == null) throw _damaged(where, 'unknown period');
      unit = parsed;
      final date = item['start'];
      if (date is! String || !_isRealDate(date)) {
        throw _damaged(where, 'start is not a real date');
      }
      start = date;
    }
    final repeats = item['repeats'];
    if (repeats != null && repeats is! bool) {
      throw _damaged(where, 'bad repeat setting');
    }
    // One row per category and first day; the database enforces it too.
    if (!seen.add('$categoryId:$start')) {
      throw _damaged(where, 'two limits for one start');
    }
    final amount = item['amountCents'];
    if (amount != null &&
        (amount is! int || amount < 1 || amount > maxAmountCents)) {
      throw _damaged(where, 'amount out of range');
    }
    final created = _time(item['createdAt']);
    if (created == null) throw _damaged(where, 'bad timestamp');
    rows.add(
      BudgetLimitRow(
        id: id,
        categoryId: categoryId as int?,
        unit: unit,
        repeats: repeats as bool? ?? true,
        start: start,
        amountCents: amount as int?,
        createdAt: created,
      ),
    );
  }
  return rows;
}

/// Backups made before favorites existed have no `favorites`; that restores
/// as "no favorites".
List<FavoriteRow> _parseFavorites(
  Object? json,
  Map<int, CategoryRow> categories,
) {
  if (json == null) return const [];
  if (json is! List) throw _damaged('favorites', 'not a list');
  if (json.length > 100) throw _damaged('favorites', 'far too many');
  final rows = <FavoriteRow>[];
  final ids = <int>{};
  for (final item in json) {
    if (item is! Map<String, Object?>) {
      throw _damaged('favorite', 'not an object');
    }
    final id = item['id'];
    if (id is! int || id < 1 || !ids.add(id)) {
      throw _damaged('favorite', 'bad or repeated id');
    }
    final where = 'favorite $id';
    final label = item['label'];
    if (label is! String ||
        label.trim().isEmpty ||
        label.trim().length > maxFavoriteLabelLength) {
      throw _damaged(where, 'bad name');
    }
    final type = _type(item['type']);
    if (type == null) throw _damaged(where, 'unknown type');
    final amount = item['amountCents'];
    if (amount != null &&
        (amount is! int || amount < 1 || amount > maxAmountCents)) {
      throw _damaged(where, 'amount out of range');
    }
    final category = categories[item['categoryId']];
    if (category == null) throw _damaged(where, 'unknown category');
    if (category.type != type) throw _damaged(where, 'category type differs');
    final note = item['note'];
    if (note != null && (note is! String || note.length > maxNoteLength)) {
      throw _damaged(where, 'bad note');
    }
    final title = _title(item['title'], where);
    final sort = item['sortOrder'];
    final created = _time(item['createdAt']);
    if (created == null) throw _damaged(where, 'bad timestamp');
    final clean = (note as String?)?.trim();
    rows.add(
      FavoriteRow(
        id: id,
        label: label.trim(),
        type: type,
        amountCents: amount as int?,
        categoryId: category.id,
        note: clean == null || clean.isEmpty ? null : clean,
        title: title,
        sortOrder: sort is int ? sort : 0,
        createdAt: created,
      ),
    );
  }
  return rows;
}

List<TransactionRow> _parseTransactions(
  Object? json,
  Map<int, CategoryRow> categories,
  Set<int> ruleIds,
) {
  if (json is! List) throw _damaged('transactions', 'missing');
  final rows = <TransactionRow>[];
  final ids = <int>{};
  // A rule makes at most one transaction per day.
  final ruleDays = <String>{};
  for (final item in json) {
    if (item is! Map<String, Object?>) {
      throw _damaged('transaction', 'not an object');
    }
    final id = item['id'];
    if (id is! int || id < 1 || !ids.add(id)) {
      throw _damaged('transaction', 'bad or repeated id');
    }
    final where = 'transaction $id';
    final amount = item['amountCents'];
    if (amount is! int || amount < 1 || amount > maxAmountCents) {
      throw _damaged(where, 'amount out of range');
    }
    final type = _type(item['type']);
    if (type == null) throw _damaged(where, 'unknown type');
    final date = item['date'];
    if (date is! String || !_isRealDate(date)) {
      throw _damaged(where, 'not a real date');
    }
    final category = categories[item['categoryId']];
    if (category == null) throw _damaged(where, 'unknown category');
    if (category.type != type) throw _damaged(where, 'category type differs');
    final note = item['note'];
    if (note != null && (note is! String || note.length > maxNoteLength)) {
      throw _damaged(where, 'bad note');
    }
    final title = _title(item['title'], where);
    final created = _time(item['createdAt']);
    final updated = _time(item['updatedAt']);
    if (created == null || updated == null) {
      throw _damaged(where, 'bad timestamp');
    }
    final ruleId = item['recurringRuleId'];
    if (ruleId != null) {
      if (ruleId is! int || !ruleIds.contains(ruleId)) {
        throw _damaged(where, 'unknown repeating rule');
      }
      if (!ruleDays.add('$ruleId:$date')) {
        throw _damaged(where, 'repeating rule has two on one day');
      }
    }
    final clean = (note as String?)?.trim();
    rows.add(
      TransactionRow(
        id: id,
        amountCents: amount,
        type: type,
        date: date,
        categoryId: category.id,
        note: clean == null || clean.isEmpty ? null : clean,
        title: title,
        createdAt: created,
        updatedAt: updated,
        recurringRuleId: ruleId as int?,
      ),
    );
  }
  return rows;
}

/// A transaction title from a file: absent or blank is none, otherwise it
/// must be text within the limit.
String? _title(Object? value, String where) {
  if (value == null) return null;
  if (value is! String || value.length > maxTitleLength) {
    throw _damaged(where, 'bad title');
  }
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

TransactionType? _type(Object? v) =>
    v is String ? TransactionType.values.asNameMap()[v] : null;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `yyyy-MM-dd` that is an actual calendar day (rejects 2026-02-31).
bool _isRealDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final year = int.parse(s.substring(0, 4));
  return year >= 1900 && year <= 2999 && toIsoDate(fromIsoDate(s)) == s;
}
