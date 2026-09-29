import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/reminders_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  // Monday 28 September 2026, two in the afternoon.
  final now = DateTime(2026, 9, 28, 14, 0);
  ParsedReminder? p(String s) => parseReminder(s, now);

  test('only messages that ask to be reminded are reminders', () {
    expect(p('Dinner is in the oven'), isNull);
    expect(p('I will remind you later'), isNull);
    expect(p('Remind me to'), isNull);
    expect(p('Remind me to call Mum')!.what, 'Call Mum');
    expect(p('Reminder: dentist')!.what, 'Dentist');
    expect(p("Don't forget the bins")!.what, 'The bins');
    expect(p('Don’t forget to feed the cat')!.what, 'Feed the cat');
    expect(p('Remember to water the plants')!.what, 'Water the plants');
    expect(p('Please remind us to book the MOT')!.what, 'Book the MOT');
    expect(p('Remind me to call Mum')!.due, isNull);
  });

  test('a short message with a clock time is a reminder without asking', () {
    var r = p('Book taxi at 3pm')!;
    expect((r.what, r.due), ('Book taxi', DateTime(2026, 9, 28, 15)));
    r = p('Dentist tomorrow at 9:30')!;
    expect((r.what, r.due), ('Dentist', DateTime(2026, 9, 29, 9, 30)));
    expect(p('Check the oven in 20 minutes')!.due, DateTime(2026, 9, 28, 14, 20));
    // A day alone is news, a question is a question, a long message is a
    // note that happens to mention a time.
    expect(p('The parcel came today'), isNull);
    expect(p('Are you back at 6?'), isNull);
    expect(
      p('We had a lovely walk by the river and stopped for lunch at the pub '
          'before heading home at 3pm through the woods'),
      isNull,
    );
    expect(p('Dinner is in the oven'), isNull);
  });

  test('times and days, taken out of the words', () {
    var r = p('Remind me to call Mum at 6pm')!;
    expect((r.what, r.due), ('Call Mum', DateTime(2026, 9, 28, 18)));

    // A time already gone today is tomorrow's.
    r = p('Remind me to take my tablets at 9:30am')!;
    expect(r.due, DateTime(2026, 9, 29, 9, 30));

    r = p('Reminder: dentist tomorrow at 9.30')!;
    expect((r.what, r.due), ('Dentist', DateTime(2026, 9, 29, 9, 30)));

    // "at 6" in a reminder means the evening.
    expect(p('Remind me to ring Jo at 6')!.due, DateTime(2026, 9, 28, 18));

    r = p("Don't forget the bins tonight")!;
    expect((r.what, r.due, r.allDay), ('The bins', DateTime(2026, 9, 28, 19), false));

    r = p('Remember to water the plants on Saturday')!;
    expect((r.what, r.due, r.allDay),
        ('Water the plants', DateTime(2026, 10, 3, 9), true));

    // "Monday" on a Monday is next week's.
    expect(p('Remind me to pay the window cleaner Monday')!.due,
        DateTime(2026, 10, 5, 9));

    expect(p('Remind me to check the oven in 20 minutes')!.due,
        DateTime(2026, 9, 28, 14, 20));
    expect(p('Remind me to move the car in 2 hours')!.due,
        DateTime(2026, 9, 28, 16));

    r = p('Reminder: parents evening on 12/10 at 7pm')!;
    expect((r.what, r.due), ('Parents evening', DateTime(2026, 10, 12, 19)));

    // Without a year, a date already gone is next year's.
    expect(p('Remind me to renew the passport on 1/3')!.due,
        DateTime(2027, 3, 1, 9));

    expect(p('Remind me to call the vet at noon on Friday')!.due,
        DateTime(2026, 10, 2, 12));
  });

  test('due reminders are announced once, then cleared after a day', () {
    var clock = now;
    final service = RemindersService(clock: () => clock, persist: false);
    final said = <String>[];
    service.onDue = (r) => said.add(r.text);
    service.add(p('Remind me to call Mum at 6pm')!, from: 'Vince');
    service.add(p('Remind me to call the plumber')!);
    service.check();
    expect(said, isEmpty);

    clock = DateTime(2026, 9, 28, 18, 0, 30);
    service.check();
    service.check();
    expect(said, ['Call Mum']);
    expect(service.reminders.first.fired, isTrue);
    // Undated ones sort after dated ones.
    expect(service.reminders.last.text, 'Call the plumber');

    clock = DateTime(2026, 9, 29, 19);
    service.add(p('Remind me to buy milk')!);
    expect(service.reminders.map((r) => r.text), ['Buy milk', 'Call the plumber']);
  });

  testWidgets('the tile fits every shape, and says when', (tester) async {
    registerBuiltInWidgets();
    final service = RemindersService(persist: false);
    final soon = DateTime.now().add(const Duration(hours: 2));
    service.add((what: 'Put the bins out', due: soon, allDay: false), from: 'Vince');
    service.add((what: 'Call the plumber', due: null, allDay: false));
    Future<void> draw(Size size) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find('reminders')!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
            id: 'r', type: 'reminders', x: 0, y: 0, width: 3, height: 3),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<RemindersService?>.value(
          value: service,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: Builder(builder: (context) => t.build(context, w)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final (w, h) in shapes) {
      await draw(tile(w, h));
      expect(tester.takeException(), isNull, reason: '${w}x$h');
    }
    await draw(tile(4, 3));
    expect(find.text('Put the bins out'), findsOneWidget);
    expect(find.text('from Vince'), findsOneWidget);
    expect(find.text('Some time'), findsOneWidget);
  });
}
