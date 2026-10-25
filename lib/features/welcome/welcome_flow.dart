import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/text_scale.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../providers/settings_providers.dart';
import '../shared/appearance_pickers.dart';

/// First-run tour, three short steps. Everything chosen here applies at once
/// (the app restyles behind it) and can be changed later in Settings. Skip is
/// always available.
class WelcomeFlow extends ConsumerStatefulWidget {
  const WelcomeFlow({super.key});

  @override
  ConsumerState<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends ConsumerState<WelcomeFlow> {
  static const _pageCount = 3;

  final _pages = PageController();
  final _opening = TextEditingController();
  int _page = 0;
  String? _openingError;

  @override
  void dispose() {
    _pages.dispose();
    _opening.dispose();
    super.dispose();
  }

  Duration get _slide => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  void _go(int page) =>
      _pages.animateToPage(page, duration: _slide, curve: Curves.easeOutCubic);

  /// Ends the tour. An empty opening balance is simply skipped.
  Future<void> _finish() async {
    final text = _opening.text.trim();
    if (text.isNotEmpty) {
      final result = parseMoney(text, allowNegative: true, allowZero: true);
      if (!result.isValid) {
        setState(() => _openingError = result.error);
        return;
      }
      await ref
          .read(settingsProvider.notifier)
          .setOpeningBalanceCents(result.cents!);
    }
    await ref.read(settingsProvider.notifier).setOnboardingDone(true);
  }

  Future<void> _skip() =>
      ref.read(settingsProvider.notifier).setOnboardingDone(true);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final c = context.appColors;
    final last = _page == _pageCount - 1;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.l),
      child: Text(
        text,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
      ),
    );

    Widget fact(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c.accent, size: 22),
          const SizedBox(width: Gap.l),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 0),
                child: TextButton(
                  key: const ValueKey('welcome-skip'),
                  onPressed: _skip,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  // 1. What this app is.
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.panel),
                              border: Border.all(color: c.accent),
                            ),
                            child: Icon(
                              Icons.science_outlined,
                              color: c.accent,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: Gap.xl),
                          heading('Your money,\nmeasured.'),
                          fact(
                            Icons.airplanemode_active_outlined,
                            'Works fully offline',
                          ),
                          fact(
                            Icons.person_off_outlined,
                            'No account, no sign-in',
                          ),
                          fact(
                            Icons.lock_outline,
                            'Nothing ever leaves this phone',
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 2. Make it yours.
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading('Make it yours'),
                          KeyedSubtree(
                            key: const ValueKey('currency-dropdown'),
                            child: CurrencyDropdown(
                              selected: settings.currency,
                              onChanged: (cur) =>
                                  notifier.setCurrencyCode(cur.code),
                            ),
                          ),
                          const SizedBox(height: Gap.xl),
                          Text(
                            'Appearance',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.dim,
                            ),
                          ),
                          const SizedBox(height: Gap.s),
                          KeyedSubtree(
                            key: const ValueKey('theme-mode'),
                            child: ThemeModePicker(
                              selected: settings.themeMode,
                              onChanged: notifier.setThemeMode,
                            ),
                          ),
                          const SizedBox(height: Gap.xl),
                          Text(
                            'Accent',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.dim,
                            ),
                          ),
                          const SizedBox(height: Gap.s),
                          AccentPicker(
                            selected: settings.accent,
                            onChanged: notifier.setAccent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 3. Opening balance.
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading('Opening balance'),
                          Text(
                            'How much do you have right now? It becomes your '
                            'starting balance. You can skip this and set it '
                            'later in Settings.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.dim,
                            ),
                          ),
                          const SizedBox(height: Gap.xl),
                          ClampedTextScale(
                            child: TextField(
                              key: const ValueKey('opening-field'),
                              controller: _opening,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,\s-]'),
                                ),
                              ],
                              style: monoText(
                                size: 32,
                                weight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Amount (optional)',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                prefixText: '${settings.currencySymbol} ',
                                prefixStyle: monoText(
                                  size: 32,
                                  weight: FontWeight.w500,
                                  color: c.dim,
                                ),
                                errorText: _openingError,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                              ),
                              onChanged: (_) {
                                if (_openingError != null) {
                                  setState(() => _openingError = null);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: _bottomBar(
                c,
                last: last,
                large: MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Position ticks plus Back and Next/Finish. With large text the buttons
  /// would not fit beside the ticks, so the ticks move above them.
  Widget _bottomBar(AppColors c, {required bool last, required bool large}) {
    final ticks = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _pageCount; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AnimatedContainer(
              duration: _slide,
              width: i == _page ? 24 : 12,
              height: 3,
              decoration: BoxDecoration(
                color: i == _page ? c.accent : c.faint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );

    final buttons = [
      if (_page > 0)
        TextButton(
          key: const ValueKey('welcome-back'),
          onPressed: () => _go(_page - 1),
          child: const Text('Back'),
        ),
      FilledButton(
        key: const ValueKey('welcome-next'),
        onPressed: last ? _finish : () => _go(_page + 1),
        child: Text(last ? 'Finish' : 'Next'),
      ),
    ];

    if (!large) {
      return Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: ticks),
          ),
          for (final b in buttons) ...[b, const SizedBox(width: Gap.s)],
        ]..removeLast(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: ticks),
        const SizedBox(height: Gap.m),
        // Side by side if they fit, stacked if not: never overflows.
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: Gap.s,
          overflowSpacing: Gap.s,
          overflowAlignment: OverflowBarAlignment.end,
          children: buttons,
        ),
      ],
    );
  }
}
