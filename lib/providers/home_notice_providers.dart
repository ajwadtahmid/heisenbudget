import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_providers.dart';
import 'lab_report_providers.dart';

/// What Home may say in its notice slot at the top. At most one is shown at a
/// time, so cards never stack. Listed in priority order: the first that applies
/// wins.
enum HomeNotice { monthReport, backupReminder }

/// The notice to show on Home now, or null when there is none.
final homeNoticeProvider = Provider<HomeNotice?>((ref) {
  if (ref.watch(reportNoticeProvider) != null) return HomeNotice.monthReport;
  if (ref.watch(backupReminderProvider) != null) {
    return HomeNotice.backupReminder;
  }
  return null;
});
