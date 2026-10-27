import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/recurring/recurring_service.dart';
import '../data/repositories/recurring_repository.dart';
import '../domain/iso_date.dart';
import 'category_providers.dart';
import 'database_providers.dart';
import 'period_providers.dart';

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(ref.watch(appDatabaseProvider)),
);

final recurringServiceProvider = Provider<RecurringService>(
  (ref) => RecurringService(
    ref.watch(appDatabaseProvider),
    now: ref.watch(nowProvider),
  ),
);

/// Every repeating rule, paused and ended ones included.
final recurringRulesProvider = StreamProvider<List<RecurringRuleRow>>((ref) {
  return ref.watch(recurringRepositoryProvider).watchAll();
});

/// How many times in a row the check for repeating transactions that are due
/// has failed (0 = it last worked, or has not run). It never throws at the
/// person; this is how a failure that keeps happening gets noticed.
final recurringCatchUpFailuresProvider = NotifierProvider<CatchUpFailures, int>(
  CatchUpFailures.new,
);

class CatchUpFailures extends Notifier<int> {
  @override
  int build() {
    ref.keepAlive();
    return 0;
  }

  /// Records a failure and returns how many in a row there have been.
  int failed() => ++state;

  void worked() => state = 0;
}

/// The app-wide snackbar host, so work that finishes after a screen has been
/// closed (the recurring catch-up) can still show its message.
final rootMessengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

/// A repeating transaction that will be added soon.
class ComingUp {
  const ComingUp(this.rule, this.category, this.date);

  final RecurringRuleRow rule;
  final CategoryRow? category;
  final DateTime date;
}

/// How far ahead Home looks, in days.
const comingUpDays = 7;

/// How many Home shows.
const comingUpLimit = 3;

/// Active rules whose next transaction is after today and within the next
/// [comingUpDays] days, soonest first. Worked out on the fly, never stored
/// and never part of any total.
final comingUpProvider = Provider<List<ComingUp>>((ref) {
  final rules = ref.watch(recurringRulesProvider).value ?? const [];
  final categories = ref.watch(allCategoriesProvider).value ?? const [];
  final today = ref.watch(clockProvider);
  final horizon = DateTime(today.year, today.month, today.day + comingUpDays);
  final soon = <ComingUp>[];
  for (final rule in rules) {
    if (!rule.isActive) continue;
    final date = rule.nextDate;
    if (date == null || !date.isAfter(today) || date.isAfter(horizon)) continue;
    CategoryRow? category;
    for (final c in categories) {
      if (c.id == rule.categoryId) category = c;
    }
    soon.add(ComingUp(rule, category, dateOnly(date)));
  }
  soon.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.rule.id.compareTo(b.rule.id);
  });
  return soon.take(comingUpLimit).toList();
});
