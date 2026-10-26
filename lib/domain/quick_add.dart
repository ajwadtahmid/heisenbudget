// PURE DART: no Flutter imports. What a launcher shortcut asks the app to do.
import 'transaction_type.dart';

/// Shortcut identifiers, shared by the code that registers them and the code
/// that receives them. Stored by the phone's launcher: never rename one.
const shortcutAddExpense = 'add_expense';
const shortcutAddIncome = 'add_income';
const shortcutFavoritePrefix = 'favorite:';

/// "Open the Add sheet": for a type, or for one favorite.
class QuickAddRequest {
  const QuickAddRequest.type(TransactionType this.type) : favoriteId = null;
  const QuickAddRequest.favorite(int this.favoriteId) : type = null;

  final TransactionType? type;
  final int? favoriteId;

  @override
  bool operator ==(Object other) =>
      other is QuickAddRequest &&
      other.type == type &&
      other.favoriteId == favoriteId;

  @override
  int get hashCode => Object.hash(type, favoriteId);
}

/// The request a shortcut [type] stands for, or null for one this version
/// does not know (an older or newer shortcut left on the launcher).
QuickAddRequest? requestFromShortcut(String type) {
  if (type == shortcutAddExpense) {
    return const QuickAddRequest.type(TransactionType.expense);
  }
  if (type == shortcutAddIncome) {
    return const QuickAddRequest.type(TransactionType.income);
  }
  if (type.startsWith(shortcutFavoritePrefix)) {
    final id = int.tryParse(type.substring(shortcutFavoritePrefix.length));
    if (id != null && id > 0) return QuickAddRequest.favorite(id);
  }
  return null;
}
