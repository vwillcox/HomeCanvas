import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/widgets/parcels_view.dart';
import 'package:home_canvas/services/parcels_service.dart';

void main() {
  // Tuesday 3 November 2026, half past eight in the morning.
  final now = DateTime(2026, 11, 3, 8, 30);
  DeliveryWindow? f(String s) => findDeliveryWindow(s, now);
  DateTime on(int day, [int h = 0, int m = 0]) => DateTime(2026, 11, day, h, m);

  group('what carriers write', () {
    test('DPD: today, in an hour\'s slot', () {
      expect(
        f('Your DPD parcel will be delivered today between 10:15 and 11:15.'),
        (from: on(3, 10, 15), to: on(3, 11, 15)),
      );
    });

    test('Evri: a day and a morning, in am and pm', () {
      expect(
        f('Good news! Your parcel is arriving Wednesday 4th November, 9am-1pm'),
        (from: on(4, 9), to: on(4, 13)),
      );
      expect(f('Your Evri parcel is due tomorrow 1-3pm'), (
        from: on(4, 13),
        to: on(4, 15),
      ));
    });

    test('Royal Mail: a day, no time', () {
      expect(f('Your item is due to be delivered on Thursday 5 November.'), (
        from: on(5),
        to: null,
      ));
    });

    test('Amazon: by an hour', () {
      expect(f('Arriving tomorrow by 10pm'), (from: on(4), to: on(4, 22)));
    });

    test('Yodel: a date in figures, and a window', () {
      expect(
        f(
          'Your parcel is due for delivery on 06/11/2026 between 08:00 and 18:00',
        ),
        (from: on(6, 8), to: on(6, 18)),
      );
    });

    test('a weekday alone is this week\'s, today\'s if it is today', () {
      expect(f('Expected delivery: Friday'), (from: on(6), to: null));
      expect(f('Arriving Tuesday'), (from: on(3), to: null));
    });

    test('dashes of every kind', () {
      expect(f('Delivery slot today 12:39 – 13:39'), (
        from: on(3, 12, 39),
        to: on(3, 13, 39),
      ));
    });
  });

  group('the rest of an email is not read', () {
    test('only the lines about the delivery', () {
      final email = [
        'Order placed on Monday 2 November 2026 at 21:14.',
        'Thanks for shopping with us.',
        'Your parcel will be delivered on Thursday 5 November between 10:00 and 14:00.',
        'Questions? Call us 9am - 5pm, Monday to Friday.',
      ].join('\n');
      expect(f(email), (from: on(5, 10), to: on(5, 14)));
    });

    test('a long email that never says when says nothing', () {
      final email = List.filled(
        6,
        'We have your order and will send it soon. It is on its way to our warehouse.',
      ).join('\n');
      expect(f(email), isNull);
    });

    test('a link\'s digits are not a time', () {
      expect(f('https://track.dpd.co.uk/parcels/15501234567890*19826'), isNull);
    });

    test('a count of days is not a window', () {
      expect(f('Delivery in 3-5 working days'), isNull);
    });

    test('nor is the sun', () {
      expect(f('Leave it in the sun porch, it is coming soon'), isNull);
    });
  });

  test('a date long gone this year is next year\'s', () {
    expect(f('Arriving 6 January'), (from: DateTime(2027, 1, 6), to: null));
  });

  group('said on the tile', () {
    Parcel parcel(DeliveryWindow w) => Parcel(
      id: 'p',
      carrier: Carrier.amazon,
      url: 'https://www.amazon.co.uk/',
      added: now,
      expected: w.from,
      expectedTo: w.to,
    );

    test('a window, an end alone, a day alone', () {
      expect(
        parcelWhen(parcel((from: on(3, 10, 15), to: on(3, 11, 15))), now),
        'Due today, 10:15–11:15',
      );
      expect(
        parcelWhen(parcel(f('Arriving tomorrow by 10pm')!), now),
        'Due tomorrow, by 22:00',
      );
      expect(parcelWhen(parcel((from: on(4), to: null)), now), 'Due tomorrow');
    });

    test('and as its window opens', () {
      expect(
        parcelDueNow(parcel((from: on(3, 10, 15), to: on(3, 11, 15)))),
        'Due now, until 11:15',
      );
      expect(
        parcelDueNow(parcel(f('Arriving today by 10pm')!)),
        'Due today, by 22:00',
      );
      expect(parcelDueNow(parcel((from: on(3), to: null))), 'Due today');
    });
  });
}
