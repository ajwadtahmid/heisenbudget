// PURE DART: no Flutter imports.
import '../core/constants.dart';
import 'date_range.dart';
import 'iso_date.dart';
import 'period.dart';
import 'sort_option.dart';
import 'transaction_type.dart';
import 'week_mode.dart';

/// How many filters a person can keep, and how long a name may be.
const maxSavedFilters = 20;
const maxSavedFilterNameLength = 40;

/// Which dates a saved filter covers. The relative ones mean "now" each time
/// the filter is used ("This month" saved in March shows October in October);
/// [custom] keeps the two dates it was saved with.
enum SavedPeriod { allTime, thisWeek, thisMonth, lastMonth, custom }

/// A History filter with a name, kept for later. The search box and a date
/// jump are not part of it: they belong to the moment, not to the filter.
class SavedFilter {
  const SavedFilter({
    required this.name,
    this.type,
    this.categoryIds = const {},
    this.period = SavedPeriod.allTime,
    this.customStart,
    this.customEnd,
    this.minCents,
    this.maxCents,
    this.sort = SortOption.newestFirst,
  });

  final String name;
  final TransactionType? type;
  final Set<int> categoryIds;
  final SavedPeriod period;

  /// Set only for [SavedPeriod.custom].
  final DateTime? customStart;
  final DateTime? customEnd;

  /// Amount bounds in cents, both ends inclusive; null = no bound.
  final int? minCents;
  final int? maxCents;
  final SortOption sort;

  /// The period this filter means on [today] (null = all time).
  Period? periodFor(DateTime today) => switch (period) {
    SavedPeriod.allTime => null,
    SavedPeriod.thisWeek => ThisWeek(today),
    SavedPeriod.thisMonth => ThisMonth(today),
    SavedPeriod.lastMonth => ThisMonth(shiftMonth(today, -1)),
    SavedPeriod.custom => Custom(customStart!, customEnd!),
  };

  /// How a period on the History filter is kept: as one of the relative
  /// choices when it is today's week or this or last month, otherwise as the
  /// dates it covers.
  static SavedPeriod kindOf(
    Period? period,
    DateTime today,
    WeekMode mode,
    int weekStartDay,
  ) {
    switch (period) {
      case null:
        return SavedPeriod.allTime;
      case ThisWeek(:final anchor):
        return thisWeek(anchor, mode, weekStartDay) ==
                thisWeek(today, mode, weekStartDay)
            ? SavedPeriod.thisWeek
            : SavedPeriod.custom;
      case ThisMonth(:final anchor):
        if (_sameMonth(anchor, today)) return SavedPeriod.thisMonth;
        if (_sameMonth(anchor, shiftMonth(today, -1))) {
          return SavedPeriod.lastMonth;
        }
        return SavedPeriod.custom;
      case WeekOfMonth():
      case Custom():
        return SavedPeriod.custom;
    }
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  Map<String, Object?> toJson() => {
    'name': name,
    if (type != null) 'type': type!.name,
    'categoryIds': categoryIds.toList()..sort(),
    'period': period.name,
    if (period == SavedPeriod.custom) ...{
      'start': toIsoDate(customStart!),
      'end': toIsoDate(customEnd!),
    },
    if (minCents != null) 'minCents': minCents,
    if (maxCents != null) 'maxCents': maxCents,
    'sort': sort.name,
  };

  /// Reads one filter from stored or backed-up JSON, or null when it is not a
  /// usable filter. Strict, because it may come from a file.
  static SavedFilter? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxSavedFilterNameLength) {
      return null;
    }

    final typeName = json['type'];
    TransactionType? type;
    if (typeName != null) {
      type = TransactionType.values.asNameMap()[typeName];
      if (type == null) return null;
    }

    final ids = json['categoryIds'];
    if (ids is! List || ids.length > 500) return null;
    final categoryIds = <int>{};
    for (final id in ids) {
      if (id is! int || id < 1) return null;
      categoryIds.add(id);
    }

    final period = SavedPeriod.values.asNameMap()[json['period']];
    if (period == null) return null;
    DateTime? start;
    DateTime? end;
    if (period == SavedPeriod.custom) {
      start = _date(json['start']);
      end = _date(json['end']);
      if (start == null || end == null || end.isBefore(start)) return null;
    }

    int? amount(Object? v) =>
        v is int && v >= 1 && v <= maxAmountCents ? v : null;
    final min = amount(json['minCents']);
    final max = amount(json['maxCents']);
    if (json['minCents'] != null && min == null) return null;
    if (json['maxCents'] != null && max == null) return null;
    if (min != null && max != null && min > max) return null;

    return SavedFilter(
      name: trimmed,
      type: type,
      categoryIds: categoryIds,
      period: period,
      customStart: start,
      customEnd: end,
      minCents: min,
      maxCents: max,
      sort:
          SortOption.values.asNameMap()[json['sort']] ?? SortOption.newestFirst,
    );
  }

  /// A real date written `yyyy-MM-dd`, within the years the app stores.
  static DateTime? _date(Object? text) {
    if (text is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return null;
    }
    final d = fromIsoDate(text);
    if (toIsoDate(d) != text) return null; // 2026-02-31 rolls over
    if (d.year < minDataYear || d.year > maxDataYear) return null;
    return d;
  }

  /// [filters] with [filter] added, or replacing the one with the same name
  /// (case aside). Null when the list is full and the name is new.
  static List<SavedFilter>? upsert(
    List<SavedFilter> filters,
    SavedFilter filter,
  ) {
    final key = filter.name.toLowerCase();
    final at = filters.indexWhere((f) => f.name.toLowerCase() == key);
    if (at >= 0) return [...filters]..[at] = filter;
    if (filters.length >= maxSavedFilters) return null;
    return [...filters, filter];
  }

  /// The usable filters in [json] (a list), at most [maxSavedFilters], with
  /// repeated names dropped (the first wins). Anything unusable is skipped.
  static List<SavedFilter> listFromJson(Object? json) {
    if (json is! List) return const [];
    final out = <SavedFilter>[];
    final names = <String>{};
    for (final item in json) {
      final f = fromJson(item);
      if (f == null || !names.add(f.name.toLowerCase())) continue;
      out.add(f);
      if (out.length == maxSavedFilters) break;
    }
    return out;
  }
}
