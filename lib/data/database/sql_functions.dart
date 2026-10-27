import 'package:sqlite3/common.dart';

import '../../domain/search.dart';

/// The name of the SQL function that applies History's search to one row.
const searchFunctionName = 'hb_search';

/// Teaches SQLite the app's own functions. Called when a database connection
/// is opened (see `AppDatabase.open` and `AppDatabase.memory`).
///
/// `hb_search(category, note, title, amountCents, query)` is 1 when the row
/// matches every word of [query], using exactly [SearchQuery.matches]: case
/// ignored in every script, and a number matching an amount by prefix. Doing
/// it in SQL lets History search a page at a time instead of loading every
/// transaction, with the same results as before.
void registerSqlFunctions(CommonDatabase db) {
  String? lastText;
  SearchQuery? lastQuery;
  db.createFunction(
    functionName: searchFunctionName,
    argumentCount: const AllowedArgumentCount(5),
    deterministic: true,
    function: (args) {
      final text = args[4] as String;
      // The same text arrives for every row; read it once.
      if (text != lastText) {
        lastText = text;
        lastQuery = SearchQuery.parse(text);
      }
      final matches = lastQuery!.matches(
        category: args[0] as String,
        note: args[1] as String?,
        title: args[2] as String?,
        amountCents: args[3] as int,
      );
      return matches ? 1 : 0;
    },
  );
}
