import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;

import '../../core/category_icons.dart' show defaultCategoryIconKey;
import '../../core/constants.dart';
import '../../core/currencies.dart';
import '../../core/design/app_colors.dart' show AccentColor;
import '../../core/design/app_font.dart' show AppFont;
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
  });

  final String? currency;
  final String? themeMode;
  final String? accent;
  final String? textFont;
  final bool? labFlavor;
  final int? openingBalanceCents;
  final String? weekMode;
  final int? weekStartDay;

  Map<String, Object?> toJson() => {
    'currency': currency,
    'themeMode': themeMode,
    'accent': accent,
    'textFont': textFont,
    'labFlavor': labFlavor,
    'openingBalanceCents': openingBalanceCents,
    'weekMode': weekMode,
    'weekStartDay': weekStartDay,
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
    required this.transactions,
  });

  final DateTime exportedAt;
  final BackupSettings settings;
  final List<CategoryRow> categories;
  final List<RecurringRuleRow> recurringRules;
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
            'unit': r.unit.name,
            'interval': r.interval,
            'startDate': r.startDate,
            'endDate': r.endDate,
            'isActive': r.isActive,
            'nextIndex': r.nextIndex,
            'createdAt': r.createdAt.toUtc().toIso8601String(),
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
    final transactions = _parseTransactions(root['transactions'], byId, {
      for (final r in rules) r.id,
    });

    final exported = root['exportedAt'];
    return BackupData(
      exportedAt:
          (exported is String ? DateTime.tryParse(exported) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      settings: BackupSettings.fromJson(root['settings']),
      categories: categories,
      recurringRules: rules,
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
        createdAt: created,
        updatedAt: updated,
        recurringRuleId: ruleId as int?,
      ),
    );
  }
  return rows;
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
