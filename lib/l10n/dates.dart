import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'l10n.dart';

/// Dates as the panel writes them, in its language.
///
/// Numbers in the order the language's readers expect — 28/09/2026 in
/// Britain, 09/28/2026 in America — and month and weekday names from intl's
/// calendar data, so every language names its own days without a string of
/// ours to translate.

bool _loaded = false;

/// intl's name for the panel's language. Portuguese is the European kind,
/// as its pack is.
String get _locale {
  if (!_loaded) {
    // The local data is filled in at once; the future is only a formality.
    initializeDateFormatting();
    _loaded = true;
  }
  final code = L10n.instance.code;
  return switch (code) {
    'pt' => 'pt_PT',
    _ => L10n.instance.language.intlCode,
  };
}

DateFormat _format(DateFormat Function(String locale) make) {
  try {
    return make(_locale);
  } catch (_) {
    return make('en_GB');
  }
}

/// 28/09/2026 — or 09/28/2026 in US English, 28.9.2026 in German.
String numericDate(DateTime d) => switch (L10n.instance.code) {
  'en-GB' => DateFormat('dd/MM/yyyy').format(d),
  'en-US' => DateFormat('MM/dd/yyyy').format(d),
  _ => _format(DateFormat.yMd).format(d),
};

/// 28/09 — or 09/28 in US English: a day this year.
String numericDayMonth(DateTime d) => switch (L10n.instance.code) {
  'en-GB' => DateFormat('dd/MM').format(d),
  'en-US' => DateFormat('MM/dd').format(d),
  _ => _format(DateFormat.Md).format(d),
};

/// "Monday".
String weekdayName(DateTime d) => _format(DateFormat.EEEE).format(d);

/// "Mon".
String weekdayShort(DateTime d) => _format(DateFormat.E).format(d);

/// "M", "T"… — Monday first, for a month grid's heading.
List<String> weekdayLetters() {
  final monday = DateTime(2024, 1, 1);
  final f = _format(DateFormat.EEEEE);
  return [for (var i = 0; i < 7; i++) f.format(monday.add(Duration(days: i)))];
}

/// "28 Sept" — or "Sep 28" in US English.
String dayMonth(DateTime d) => _format(DateFormat.MMMd).format(d);

/// "Mon 28 Sept" — or "Mon, Sep 28".
String weekdayDayMonth(DateTime d) => _format(DateFormat.MMMEd).format(d);

/// "Monday 28 September" — or "Monday, September 28".
String longDate(DateTime d) => _format(DateFormat.MMMMEEEEd).format(d);

/// "28 September 2026" — or "September 28, 2026".
String fullDate(DateTime d) => _format(DateFormat.yMMMMd).format(d);

/// "September 2026".
String monthYear(DateTime d) => _format(DateFormat.yMMMM).format(d);

/// "September".
String monthName(DateTime d) => _format(DateFormat.MMMM).format(d);

/// "Sept 26" — a month on a year's chart.
String monthShortYear(DateTime d) =>
    _format((l) => DateFormat('MMM yy', l)).format(d);
