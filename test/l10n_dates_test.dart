import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/l10n/dates.dart';
import 'package:home_canvas/l10n/l10n.dart';

void main() {
  final d = DateTime(2026, 9, 8, 14, 5);
  tearDown(() => L10n.instance.debugUse('en-GB', const {}));

  test('British dates: day first', () {
    L10n.instance.debugUse('en-GB', const {});
    expect(numericDate(d), '08/09/2026');
    expect(numericDayMonth(d), '08/09');
    expect(longDate(d), 'Tuesday 8 September');
    expect(fullDate(d), '8 September 2026');
    expect(monthYear(d), 'September 2026');
  });

  test('American dates: month first', () {
    L10n.instance.debugUse('en-US', const {});
    expect(numericDate(d), '09/08/2026');
    expect(numericDayMonth(d), '09/08');
    expect(longDate(d), 'Tuesday, September 8');
    expect(fullDate(d), 'September 8, 2026');
    expect(dayMonth(d), 'Sep 8');
  });

  test('other languages name their own days and months', () {
    L10n.instance.debugUse('de', const {});
    expect(longDate(d), contains('September'));
    expect(weekdayName(d), 'Dienstag');
    expect(numericDate(d), '8.9.2026');
    L10n.instance.debugUse('fr', const {});
    expect(fullDate(d), '8 septembre 2026');
    L10n.instance.debugUse('cy', const {});
    expect(weekdayName(d), 'Dydd Mawrth');
    L10n.instance.debugUse('pt', const {});
    expect(monthName(d), 'setembro');
    expect(weekdayLetters(), hasLength(7));
  });
}
