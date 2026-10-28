import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/home_notice_providers.dart';
import 'backup_reminder_card.dart';

/// The top of Home: one notice card, or nothing. Which card is decided by
/// [homeNoticeProvider], so two notices never stack.
class HomeNoticeSlot extends ConsumerWidget {
  const HomeNoticeSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(homeNoticeProvider);
    return switch (notice) {
      HomeNotice.backupReminder => const BackupReminderCard(),
      null => const SizedBox.shrink(),
    };
  }
}
