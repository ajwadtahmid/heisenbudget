import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/category_icons.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/domain/week_mode.dart';
import 'package:heisenbudget/features/shared/category_tile.dart';
import 'package:heisenbudget/features/shared/icon_picker.dart';
import 'package:heisenbudget/features/shared/empty_state.dart';
import 'package:heisenbudget/features/shared/period_selector.dart';
import 'package:heisenbudget/features/shared/transaction_tile.dart';
import 'package:heisenbudget/core/design/section_label.dart';

TransactionWithCategory _item({
  TransactionType type = TransactionType.expense,
  int cents = 1250,
  String? note,
  bool archived = false,
  String category = 'Food',
}) {
  return TransactionWithCategory(
    TransactionRow(
      id: 1,
      amountCents: cents,
      type: type,
      date: '2026-10-05',
      categoryId: 1,
      note: note,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    CategoryRow(
      id: 1,
      name: category,
      type: type,
      isDefault: true,
      isArchived: archived,
      isProtected: false,
      sortOrder: 0,
      icon: 'restaurant',
    ),
  );
}

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? lightTheme() : darkTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Finder _button(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(IconButton),
);

void main() {
  group('TransactionTile', () {
    testWidgets('expense: minus sign, spent color', (tester) async {
      await tester.pumpWidget(
        _host(TransactionTile(item: _item(), currencySymbol: r'$')),
      );
      final text = tester.widget<Text>(find.text(r'-$12.50'));
      expect(text.style!.color, AppColors.light.spent);
      expect(find.byIcon(Icons.restaurant), findsOneWidget);
    });

    testWidgets('income: plus sign, received color', (tester) async {
      await tester.pumpWidget(
        _host(
          TransactionTile(
            item: _item(type: TransactionType.income, category: 'Salary'),
            currencySymbol: r'$',
          ),
        ),
      );
      final text = tester.widget<Text>(find.text(r'+$12.50'));
      expect(text.style!.color, AppColors.light.received);
    });

    testWidgets('archived category is marked', (tester) async {
      await tester.pumpWidget(
        _host(
          TransactionTile(item: _item(archived: true), currencySymbol: r'$'),
        ),
      );
      expect(find.text('Food (archived)'), findsOneWidget);
    });

    testWidgets('note and date show; a long note is cut with an ellipsis', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          TransactionTile(
            item: _item(note: 'n' * 190),
            currencySymbol: r'$',
            showDate: true,
          ),
        ),
      );
      final subtitle = tester.widget<Text>(find.textContaining('Oct 5, 2026'));
      expect(subtitle.maxLines, 1);
      expect(subtitle.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the whole row is tappable and at least 48dp tall', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          TransactionTile(
            item: _item(),
            currencySymbol: r'$',
            onTap: () => taps++,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ListTile)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byType(ListTile));
      expect(taps, 1);
    });

    testWidgets('huge amounts shrink instead of overflowing', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          TransactionTile(
            item: _item(cents: 99999999999, note: 'a long note ' * 10),
            currencySymbol: r'$',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CategoryTile', () {
    testWidgets('shows the icon for its key', (tester) async {
      await tester.pumpWidget(_host(const CategoryTile(iconKey: 'flight')));
      expect(find.byIcon(Icons.flight), findsOneWidget);
    });

    testWidgets('an unknown key falls back to the general icon', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const CategoryTile(iconKey: 'gone')));
      expect(find.byIcon(Icons.category_outlined), findsOneWidget);
    });

    testWidgets('archived tiles are muted but still show the icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const CategoryTile(iconKey: 'pets', archived: true)),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.pets));
      expect(icon.color, isNotNull);
    });
  });

  group('IconPicker', () {
    Widget picker({String selected = 'car', ValueChanged<String>? onChanged}) =>
        _host(
          IconPicker(selectedKey: selected, onChanged: onChanged ?? (_) {}),
        );

    testWidgets('lists every icon and reports a tap', (tester) async {
      String? picked;
      await tester.pumpWidget(picker(onChanged: (k) => picked = k));

      expect(find.byType(IconButton), findsNWidgets(categoryIcons.length));
      final pets = find.byKey(const ValueKey('icon-pets'));
      await tester.ensureVisible(pets);
      await tester.pump();
      await tester.tap(pets);
      expect(picked, 'pets');
    });

    testWidgets('marks the chosen icon', (tester) async {
      await tester.pumpWidget(picker(selected: 'car'));
      expect(tester.widget<IconButton>(_button('icon-car')).isSelected, isTrue);
      expect(
        tester.widget<IconButton>(_button('icon-bus')).isSelected,
        isNot(isTrue),
      );
    });

    testWidgets('shows a heading for each section', (tester) async {
      await tester.pumpWidget(picker(selected: 'category'));
      for (final group in categoryIconGroups) {
        expect(
          find.byKey(ValueKey('icon-group-$group')),
          findsOneWidget,
          reason: group,
        );
      }
    });

    testWidgets('every button is 48dp and has a name for screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'category'));
      for (final option in categoryIcons) {
        final finder = find.byKey(ValueKey('icon-${option.key}'));
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48), reason: option.key);
        expect(size.height, greaterThanOrEqualTo(48), reason: option.key);
        expect(
          tester.widget<IconButton>(_button('icon-${option.key}')).tooltip,
          option.label,
        );
      }
    });

    testWidgets('search narrows the grid and hides empty sections', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'category'));
      await tester.enterText(
        find.byKey(const ValueKey('icon-search')),
        'pizza',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('icon-pizza')), findsOneWidget);
      // One icon, plus the search box's clear button.
      expect(find.byType(IconButton), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('icon-group-Food & drink')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('icon-group-Money & work')),
        findsNothing,
      );
    });

    testWidgets('search also matches a section name', (tester) async {
      await tester.pumpWidget(picker(selected: 'category'));
      await tester.enterText(
        find.byKey(const ValueKey('icon-search')),
        'getting around',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('icon-bus')), findsOneWidget);
      expect(find.byKey(const ValueKey('icon-pizza')), findsNothing);
    });

    testWidgets('no matches says so, and clearing brings everything back', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'category'));
      await tester.enterText(
        find.byKey(const ValueKey('icon-search')),
        'zzzzqq',
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('icon-no-results')), findsOneWidget);
      expect(find.text('No icons match "zzzzqq"'), findsOneWidget);
      expect(
        find.byType(IconButton),
        findsOneWidget,
        reason: 'only the clear button',
      );

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byKey(const ValueKey('icon-no-results')), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(categoryIcons.length));
    });

    testWidgets('the chosen icon stays selected while searching', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'pizza'));
      await tester.enterText(
        find.byKey(const ValueKey('icon-search')),
        'pizza',
      );
      await tester.pump();
      expect(
        tester.widget<IconButton>(_button('icon-pizza')).isSelected,
        isTrue,
      );
    });

    testWidgets('opens scrolled to the chosen icon', (tester) async {
      // "construction" is the very last icon: far below the first screenful.
      await tester.pumpWidget(picker(selected: 'construction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final grid = tester.getRect(find.byType(SingleChildScrollView).last);
      final icon = tester.getRect(
        find.byKey(const ValueKey('icon-construction')),
      );
      expect(grid.overlaps(icon), isTrue);
    });

    testWidgets(
      'opens at the selected icon\'s section heading, not mid-section',
      (tester) async {
        await tester.pumpWidget(picker(selected: 'rocket')); // "Tech & other"
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final grid = tester.getRect(find.byType(SingleChildScrollView).last);
        final heading = tester.getRect(
          find.byKey(const ValueKey('icon-group-Tech & other')),
        );
        expect(
          heading.top,
          greaterThanOrEqualTo(grid.top - 1),
          reason: 'the heading is visible, so no icon is shown headless',
        );
        expect(
          heading.top - grid.top,
          lessThan(24),
          reason: 'and it sits at the top of the grid',
        );
        final icon = tester.getRect(find.byKey(const ValueKey('icon-rocket')));
        expect(grid.overlaps(icon), isTrue);
      },
    );

    testWidgets('selection is a rounded square like everything else', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'car'));
      final button = tester.widget<IconButton>(_button('icon-car'));
      final shape = button.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('an unknown selected key does not break the picker', (
      tester,
    ) async {
      await tester.pumpWidget(picker(selected: 'nope'));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<IconButton>(_button('icon-category')).isSelected,
        isTrue,
        reason: 'falls back to the general icon',
      );
    });
  });

  group('EmptyState', () {
    testWidgets('shows the message and runs the action', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        _host(
          EmptyState(
            icon: Icons.search_off,
            message: 'Nothing here',
            actionLabel: 'Do it',
            onAction: () => pressed = true,
          ),
        ),
      );
      expect(find.text('Nothing here'), findsOneWidget);
      await tester.tap(find.text('Do it'));
      expect(pressed, isTrue);
    });

    testWidgets('has no button without an action', (tester) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(icon: Icons.search_off, message: 'Nothing here'),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('PeriodSelector (Home, compact)', () {
    Widget selector(
      Period period,
      ValueChanged<Period> onChanged, {
      WeekMode mode = WeekMode.calendar,
    }) {
      return _host(
        PeriodSelector(
          period: period,
          today: DateTime(2026, 10, 15),
          weekMode: mode,
          weekStartDay: 1,
          onChanged: onChanged,
        ),
      );
    }

    String label(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('period-label'))).data!;

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('period-menu')));
      await tester.pumpAndSettle();
    }

    testWidgets('one button shows the current choice', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (_) {}),
      );
      expect(label(tester), 'This month');
      expect(find.byType(ChoiceChip), findsNothing, reason: 'no row of chips');

      await tester.pumpWidget(
        selector(ThisWeek(DateTime(2026, 10, 15)), (_) {}),
      );
      expect(label(tester), 'This week');

      await tester.pumpWidget(selector(const WeekOfMonth(2026, 10, 3), (_) {}));
      expect(label(tester), 'Week 3');

      await tester.pumpWidget(
        selector(Custom(DateTime(2026, 10, 1), DateTime(2026, 10, 9)), (_) {}),
      );
      expect(label(tester), 'Custom');
    });

    testWidgets('a stepped period is labeled by its dates', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 11, 1)), (_) {}),
      );
      expect(label(tester), 'November 2026');
      await tester.pumpWidget(
        selector(ThisWeek(DateTime(2026, 10, 22)), (_) {}),
      );
      expect(label(tester), 'Week of Oct 19');
    });

    testWidgets('the menu lists This week, This month, Week 1..N and Custom', (
      tester,
    ) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (_) {}),
      );
      await openMenu(tester);

      expect(find.byKey(const ValueKey('menu-this-week')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-this-month')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-last-week')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-last-month')), findsOneWidget);
      // Oct 2026, Monday weeks: 5.
      for (var n = 1; n <= 5; n++) {
        expect(find.byKey(ValueKey('menu-week-$n')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('menu-week-6')), findsNothing);
      expect(find.byKey(const ValueKey('menu-custom')), findsOneWidget);
    });

    testWidgets('shows only as many weeks as the month has', (tester) async {
      // Feb 2026 in fixed mode: 4 blocks.
      await tester.pumpWidget(
        selector(
          ThisMonth(DateTime(2026, 2, 10)),
          (_) {},
          mode: WeekMode.fixed,
        ),
      );
      await openMenu(tester);
      expect(find.byKey(const ValueKey('menu-week-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-week-5')), findsNothing);
    });

    testWidgets('menu choices report the new period', (tester) async {
      Period? last;
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (p) => last = p),
      );

      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('menu-this-week')));
      await tester.pumpAndSettle();
      expect(last, isA<ThisWeek>());

      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('menu-week-3')));
      await tester.pumpAndSettle();
      final week = last as WeekOfMonth;
      expect((week.year, week.month, week.n), (2026, 10, 3));

      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('menu-this-month')));
      await tester.pumpAndSettle();
      expect(last, isA<ThisMonth>());
    });

    testWidgets('Custom is in the menu and opens the range picker', (
      tester,
    ) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (_) {}),
      );
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('menu-custom')));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });

    testWidgets('swiping the ruler steps to the previous and next period', (
      tester,
    ) async {
      Period? last;
      await tester.pumpWidget(
        selector(const WeekOfMonth(2026, 10, 2), (p) => last = p),
      );
      await tester.fling(
        find.byKey(const ValueKey('period-swipe')),
        const Offset(-300, 0),
        1500,
      );
      var week = last as WeekOfMonth;
      expect((week.month, week.n), (11, 2));

      await tester.fling(
        find.byKey(const ValueKey('period-swipe')),
        const Offset(300, 0),
        1500,
      );
      week = last as WeekOfMonth;
      expect((week.month, week.n), (9, 2));
    });

    testWidgets('a slow drag does not change the period', (tester) async {
      Period? last;
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (p) => last = p),
      );
      await tester.drag(
        find.byKey(const ValueKey('period-swipe')),
        const Offset(-40, 0),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(last, isNull);
    });

    testWidgets('screen readers get Previous and Next period actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      Period? last;
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (p) => last = p),
      );
      final data = tester
          .getSemantics(find.byKey(const ValueKey('period-swipe')))
          .getSemanticsData();
      final actions = data.customSemanticsActionIds ?? <int>[];
      final labels = [
        for (final id in actions) CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(labels, containsAll(['Previous period', 'Next period']));
      handle.dispose();
      expect(last, isNull);
    });

    testWidgets('there are no arrow buttons any more', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (_) {}),
      );
      expect(find.byKey(const ValueKey('step-forward')), findsNothing);
      expect(find.byKey(const ValueKey('step-back')), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('a custom range cannot be stepped but shows its dates', (
      tester,
    ) async {
      Period? last;
      await tester.pumpWidget(
        selector(
          Custom(DateTime(2026, 10, 1), DateTime(2026, 10, 9)),
          (p) => last = p,
        ),
      );
      expect(find.text('Oct 1 – Oct 9, 2026'), findsOneWidget);
      await tester.fling(
        find.byKey(const ValueKey('period-swipe')),
        const Offset(-300, 0),
        1500,
      );
      expect(last, isA<Custom>(), reason: 'unchanged');
    });

    testWidgets(
      'Last week and Last month are in the menu and pick the right dates',
      (tester) async {
        Period? last;
        await tester.pumpWidget(
          selector(ThisMonth(DateTime(2026, 10, 15)), (p) => last = p),
        );

        await openMenu(tester);
        await tester.tap(find.byKey(const ValueKey('menu-last-month')));
        await tester.pumpAndSettle();
        final month = last as ThisMonth;
        expect((month.anchor.year, month.anchor.month), (2026, 9));

        await openMenu(tester);
        await tester.tap(find.byKey(const ValueKey('menu-last-week')));
        await tester.pumpAndSettle();
        // Today is Thursday Oct 15 2026; last week (Monday start) is Oct 5-11.
        final week = last as ThisWeek;
        expect(
          thisWeek(week.anchor, WeekMode.calendar, 1),
          DateRange(DateTime(2026, 10, 5), DateTime(2026, 10, 11)),
        );
      },
    );

    testWidgets('the button names last week and last month', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 9, 1)), (_) {}),
      );
      expect(label(tester), 'Last month');
      await tester.pumpWidget(
        selector(ThisWeek(DateTime(2026, 10, 7)), (_) {}),
      );
      expect(label(tester), 'Last week');
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 8, 1)), (_) {}),
      );
      expect(
        label(tester),
        'August 2026',
        reason: 'older months name themselves',
      );
    });

    testWidgets('the menu ticks the entry that matches', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 9, 1)), (_) {}),
      );
      await openMenu(tester);
      bool checked(String key) => tester
          .widget<CheckedPopupMenuItem<Object>>(find.byKey(ValueKey(key)))
          .checked;
      expect(checked('menu-last-month'), isTrue);
      expect(checked('menu-this-month'), isFalse);
      expect(checked('menu-this-week'), isFalse);
    });

    testWidgets('the period button is at least 48dp', (tester) async {
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 10, 15)), (_) {}),
      );
      final size = tester.getSize(find.byKey(const ValueKey('period-menu')));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('fits a 360dp screen at 200% text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(
        selector(ThisMonth(DateTime(2026, 11, 1)), (_) {}),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PeriodChips (History filter)', () {
    Widget chips(Period? period, ValueChanged<Period?> onChanged) {
      return _host(
        PeriodChips(
          period: period,
          today: DateTime(2026, 10, 15),
          weekMode: WeekMode.calendar,
          weekStartDay: 1,
          onChanged: onChanged,
        ),
      );
    }

    ChoiceChip chip(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(ValueKey('chip-$key')));

    testWidgets('offers exactly: All time, This week, This month, Last month, '
        'Custom, and no week chips', (tester) async {
      await tester.pumpWidget(chips(null, (_) {}));
      final labels = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(labels, [
        'All time',
        'This week',
        'This month',
        'Last month',
        'Custom',
      ]);
      expect(find.textContaining('Week 1'), findsNothing);
    });

    testWidgets('the chips wrap instead of scrolling sideways', (tester) async {
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(chips(null, (_) {}));

      expect(find.byType(Wrap), findsOneWidget);
      expect(
        find.byType(SingleChildScrollView),
        findsOneWidget, // only the test host
        reason: 'no horizontal scroller of its own',
      );
      final firstY = tester
          .getTopLeft(find.byKey(const ValueKey('chip-all-time')))
          .dy;
      final lastY = tester
          .getTopLeft(find.byKey(const ValueKey('chip-custom')))
          .dy;
      expect(lastY, greaterThan(firstY), reason: 'wrapped onto a second line');
      for (final key in [
        'all-time',
        'this-week',
        'this-month',
        'last-month',
        'custom',
      ]) {
        final right = tester.getTopRight(find.byKey(ValueKey('chip-$key'))).dx;
        expect(right, lessThanOrEqualTo(300), reason: '$key stays on screen');
      }
    });

    testWidgets('marks the selected chip', (tester) async {
      await tester.pumpWidget(chips(null, (_) {}));
      expect(chip(tester, 'all-time').selected, isTrue);

      await tester.pumpWidget(chips(ThisWeek(DateTime(2026, 10, 15)), (_) {}));
      expect(chip(tester, 'this-week').selected, isTrue);
      expect(chip(tester, 'all-time').selected, isFalse);

      await tester.pumpWidget(chips(ThisMonth(DateTime(2026, 10, 1)), (_) {}));
      expect(chip(tester, 'this-month').selected, isTrue);
      expect(chip(tester, 'last-month').selected, isFalse);

      await tester.pumpWidget(chips(ThisMonth(DateTime(2026, 9, 1)), (_) {}));
      expect(chip(tester, 'last-month').selected, isTrue);
      expect(chip(tester, 'this-month').selected, isFalse);

      await tester.pumpWidget(
        chips(Custom(DateTime(2026, 10, 1), DateTime(2026, 10, 9)), (_) {}),
      );
      expect(chip(tester, 'custom').selected, isTrue);
    });

    testWidgets('chips report the new period', (tester) async {
      Period? last = const WeekOfMonth(2026, 1, 1);
      await tester.pumpWidget(chips(null, (p) => last = p));

      await tester.tap(find.byKey(const ValueKey('chip-this-week')));
      expect(last, isA<ThisWeek>());

      await tester.tap(find.byKey(const ValueKey('chip-this-month')));
      expect((last as ThisMonth).anchor, DateTime(2026, 10, 15));

      await tester.tap(find.byKey(const ValueKey('chip-last-month')));
      final lastMonth = (last as ThisMonth).anchor;
      expect((lastMonth.year, lastMonth.month), (2026, 9));

      await tester.tap(find.byKey(const ValueKey('chip-all-time')));
      expect(last, isNull);
    });

    testWidgets('shows the dates for the chosen period, nothing for All time', (
      tester,
    ) async {
      await tester.pumpWidget(chips(null, (_) {}));
      expect(find.byKey(const ValueKey('resolved-range')), findsNothing);

      await tester.pumpWidget(chips(ThisMonth(DateTime(2026, 9, 1)), (_) {}));
      expect(find.text('Sep 1 – Sep 30, 2026'), findsOneWidget);
    });

    testWidgets('Custom opens the date range picker', (tester) async {
      await tester.pumpWidget(chips(null, (_) {}));
      await tester.tap(find.byKey(const ValueKey('chip-custom')));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });
  });

  group('theme', () {
    test('light and dark themes carry the extra colors', () {
      expect(lightTheme().extension<AppColors>(), isNotNull);
      expect(darkTheme().extension<AppColors>(), isNotNull);
      expect(lightTheme().useMaterial3, isTrue);
      expect(darkTheme().brightness, Brightness.dark);
    });

    test('AppColors lerps and copies', () {
      final mid = AppColors.light.lerp(AppColors.dark, 0.5);
      expect(mid.received, isNot(AppColors.light.received));
      expect(AppColors.light.copyWith(spent: Colors.black).spent, Colors.black);
      expect(AppColors.light.lerp(null, 0.5), AppColors.light);
    });
  });

  group('SectionLabel', () {
    Widget host(String text, {required double width, double scale = 1}) =>
        MaterialApp(
          theme: lightTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: SectionLabel(text)),
              ),
            ),
          ),
        );

    testWidgets('draws its hairline when the label leaves room for it', (
      tester,
    ) async {
      await tester.pumpWidget(host('Manage', width: 320));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('at large text a long label keeps the whole line and wraps '
        'between words, with no hairline', (tester) async {
      await tester.pumpWidget(
        host('Appearance and numbers', width: 320, scale: 2),
      );
      expect(find.byType(Divider), findsNothing);
      expect(tester.takeException(), isNull);
      // Every word is whole: none is wider than the line it sits on.
      final label = tester.renderObject<RenderParagraph>(
        find.textContaining('APPEARANCE'),
      );
      expect(label.size.width, lessThanOrEqualTo(320));
      final lineHeight = label.text.style!.fontSize! * 2;
      expect(
        label.size.height / lineHeight,
        lessThan(3.5),
        reason: 'two or three lines, not a word split per line',
      );
    });

    testWidgets('an action is still kept on the line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SectionLabel(
                'Spectrum',
                trailing: TextButton(onPressed: () {}, child: const Text('Go')),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Go'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
