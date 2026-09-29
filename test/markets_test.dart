import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/markets_service.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  group('Yahoo chart', () {
    Map<String, dynamic> chart(Map<String, dynamic> meta, List<num?> closes) => {
      'chart': {
        'result': [
          {
            'meta': meta,
            'indicators': {
              'quote': [
                {'close': closes},
              ],
            },
          },
        ],
        'error': null,
      },
    };

    test('a London share: pence, its plain name, today\'s change', () {
      final q = MarketsService.parseChart(
        chart({
          'symbol': 'VOD.L',
          'currency': 'GBp',
          'instrumentType': 'EQUITY',
          'regularMarketPrice': 125.8,
          'regularMarketChangePercent': 0.399,
          'longName': 'Vodafone Group Public Limited Company',
          'shortName': 'VODAFONE GROUP PLC ORD USD0.20 ',
        }, [125.3, null, 125.9, 125.8]),
      )!;
      expect(q.symbol, 'VOD.L');
      expect(q.name, 'Vodafone Group');
      expect(q.currency, 'GBp');
      expect(q.changePercent, closeTo(0.399, 1e-9));
      // Gaps in the chart, where nothing traded, are left out.
      expect(q.history, [125.3, 125.9, 125.8]);
    });

    test('an index goes by its short name, and works out its change', () {
      final q = MarketsService.parseChart(
        chart({
          'symbol': '^FTSE',
          'currency': 'GBP',
          'instrumentType': 'INDEX',
          'range': '1d',
          'regularMarketPrice': 10200,
          'chartPreviousClose': 10000,
          'shortName': 'FTSE 100',
        }, []),
      )!;
      expect(q.name, 'FTSE 100');
      expect(q.changePercent, closeTo(2, 1e-9));
    });

    test('an unknown symbol is null', () {
      expect(
        MarketsService.parseChart({
          'chart': {
            'result': null,
            'error': {'code': 'Not Found'},
          },
        }),
        isNull,
      );
    });
  });

  test('CoinGecko markets: the period\'s change and its part of the week', () {
    final week = [for (var i = 0; i < 168; i++) i.toDouble()];
    final coins = MarketsService.parseMarkets(
      [
        {
          'id': 'bitcoin',
          'symbol': 'btc',
          'name': 'Bitcoin',
          'image': 'https://example.com/btc.png',
          'current_price': 62844,
          'price_change_percentage_24h_in_currency': -1.46,
          'sparkline_in_7d': {'price': week},
        },
        {'id': 'broken', 'symbol': 'x', 'current_price': null},
      ],
      'gbp',
      '24h',
    );
    expect(coins, hasLength(1));
    final q = coins.single.quote;
    expect(coins.single.id, 'bitcoin');
    expect(q.symbol, 'BTC');
    expect(q.currency, 'GBP');
    expect(q.changePercent, -1.46);
    expect(q.history, hasLength(24));
    // The week's prices come in dollars; scaled, they end at the price in
    // pounds and keep their shape.
    expect(q.history.last, closeTo(62844, 1e-6));
    expect(q.history.first, closeTo(144 * 62844 / 167, 1e-6));
  });

  test('a day\'s chart is the last session, or the one before if it has '
      'barely begun', () {
    // 09:00 and 10:00 on two days, then 08:00 on a third: London, in summer.
    final day = [
      DateTime.utc(2026, 9, 24, 8),
      DateTime.utc(2026, 9, 24, 9),
      DateTime.utc(2026, 9, 25, 8),
      DateTime.utc(2026, 9, 25, 9),
      DateTime.utc(2026, 9, 28, 7),
    ];
    Map<String, dynamic> chart(List<DateTime> at, List<num> closes) => {
      'chart': {
        'result': [
          {
            'meta': {
              'symbol': 'RPI.L',
              'currency': 'GBp',
              'regularMarketPrice': closes.last,
              'gmtoffset': 3600,
              'range': '5d',
            },
            'timestamp': [
              for (final t in at) t.millisecondsSinceEpoch ~/ 1000,
            ],
            'indicators': {
              'quote': [
                {'close': closes},
              ],
            },
          },
        ],
      },
    };

    // One point into the morning: Friday's session, against Thursday's close.
    var q = MarketsService.parseChart(
      chart(day, [700, 710, 720, 730, 740]),
      lastSession: true,
    )!;
    expect(q.history, [720, 730]);
    expect(q.previousClose, 710);

    // Two points in: today, against Friday's close.
    q = MarketsService.parseChart(
      chart(
        [...day, DateTime.utc(2026, 9, 28, 8)],
        [700, 710, 720, 730, 740, 745],
      ),
      lastSession: true,
    )!;
    expect(q.history, [740, 745]);
    expect(q.previousClose, 730);
  });

  test('a symbol without its exchange finds the same ticker elsewhere', () {
    final found = {
      'quotes': [
        {'symbol': 'RPI.L', 'quoteType': 'EQUITY'},
        {'symbol': 'RPID', 'quoteType': 'EQUITY'},
      ],
    };
    expect(MarketsService.pickSearch('rpi', found), 'RPI.L');
    // A name has no ticker to match, so Yahoo's first answer stands.
    expect(
      MarketsService.pickSearch('rolls royce', {
        'quotes': [
          {'symbol': 'RYCEY'},
          {'symbol': 'RR.L'},
        ],
      }),
      'RYCEY',
    );
    expect(MarketsService.pickSearch('zzz', {'quotes': []}), isNull);
  });

  test('a chart keeps its times alongside its prices, and the day\'s figures',
      () {
    final q = MarketsService.parseChart({
      'chart': {
        'result': [
          {
            'meta': {
              'symbol': 'RPI.L',
              'currency': 'GBp',
              'regularMarketPrice': 711.5,
              'previousClose': 700,
              'regularMarketDayHigh': 715,
              'regularMarketDayLow': 698,
              'fiftyTwoWeekHigh': 800,
              'fiftyTwoWeekLow': 300,
              'regularMarketVolume': 1200000,
              'exchangeName': 'LSE',
            },
            'timestamp': [1000, 2000, 3000],
            'indicators': {
              'quote': [
                {
                  'close': [700, null, 711.5],
                },
              ],
            },
          },
        ],
      },
    })!;
    expect(q.history, [700, 711.5]);
    expect(q.times.map((t) => t.millisecondsSinceEpoch), [1000000, 3000000]);
    expect(q.changePercent, closeTo(1.642857, 1e-5));
    expect((q.low, q.high, q.yearLow, q.yearHigh), (698, 715, 300, 800));
    expect(q.volume, 1200000);
    expect(q.exchange, 'LSE');
  });

  test('a long coin history is thinned, keeping its first and latest', () {
    final start = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    final h = MarketsService.parseHistory({
      'prices': [
        for (var i = 0; i < 2161; i++) [start + i * 3600000, 100.0 + i],
        ['bad', 1],
      ],
    });
    expect(h.history.length, lessThanOrEqualTo(241));
    expect(h.history.first, 100);
    expect(h.history.last, 2260);
    expect(h.times, hasLength(h.history.length));
    expect(h.times.last.millisecondsSinceEpoch, start + 2160 * 3600000);

    final short = MarketsService.parseHistory({
      'prices': [
        [start, 1],
        [start + 1, 2],
      ],
    });
    expect(short.history, [1, 2]);
  });

  test('a holding is worth its price times how many, less what it cost', () {
    const rpi = Quote(
      symbol: 'RPI.L',
      name: 'Raspberry Pi Holdings',
      price: 700,
      currency: 'GBp',
    );
    final h = Holding.of(
      rpi,
      quantity: '100',
      paid: '5.98',
      fees: '9.99',
      bought: '2025-03-12',
    )!;
    // In pounds, not pence.
    expect(h.currency, 'GBP');
    expect(h.value, closeTo(700, 1e-9));
    expect(h.cost, closeTo(598 + 9.99, 1e-9));
    expect(h.gain, closeTo(700 - 607.99, 1e-9));
    expect(h.percent, closeTo((700 - 607.99) / 607.99 * 100, 1e-9));
    expect(h.bought, DateTime(2025, 3, 12));

    // A value without a price paid, and nothing without a quantity.
    const btc = Quote(symbol: 'BTC', name: 'Bitcoin', price: 60000,
        currency: 'GBP');
    final coins = Holding.of(btc, quantity: '0.05', paid: '')!;
    expect(coins.value, closeTo(3000, 1e-9));
    expect(coins.gain, isNull);
    expect(Holding.of(btc, quantity: '', paid: '40000'), isNull);
    expect(Holding.of(btc, quantity: '0', paid: '40000'), isNull);
  });

  test('purchase dates as the picker stores them or as typed', () {
    expect(parseDay('2025-03-12'), DateTime(2025, 3, 12));
    expect(parseDay('12/03/2025'), DateTime(2025, 3, 12));
    expect(parseDay('12/3/25'), DateTime(2025, 3, 12));
    expect(parseDay('12 Mar 2025'), DateTime(2025, 3, 12));
    expect(parseDay('12 March 2025'), DateTime(2025, 3, 12));
    expect(parseDay('31/02/2025'), isNull);
    expect(parseDay('soon'), isNull);
    expect(parseDay(''), isNull);
  });

  test('how long something has been held', () {
    final now = DateTime(2026, 9, 28);
    expect(heldFor(DateTime(2025, 3, 12), now), '1 year 6 months');
    expect(heldFor(DateTime(2024, 9, 28), now), '2 years');
    expect(heldFor(DateTime(2026, 8, 29), now), '30 days');
    expect(heldFor(DateTime(2026, 9, 27), now), '1 day');
    expect(heldFor(DateTime(2026, 9, 28), now), 'today');
    expect(formatGain(-96.2, 'GBP'), '−£96.20');
    expect(formatGain(1214.5, 'GBP'), '+£1,215');
  });

  test('a price paid is read in the units the price is quoted in', () {
    expect(parsePaid('650', 'GBp'), 650);
    expect(parsePaid('650p', 'GBp'), 650);
    expect(parsePaid('£6.50', 'GBp'), 650);
    // A bare number on a share priced in pence is whichever of pence or
    // pounds is nearer today's price.
    expect(parsePaid('5.98', 'GBp', now: 709.5), 598);
    expect(parsePaid('650', 'GBp', now: 709.5), 650);
    expect(parsePaid('5.98p', 'GBp', now: 709.5), 5.98);
    expect(parsePaid('7', 'GBp', now: 709.5), 700);
    expect(parsePaid('£62,000', 'GBP'), 62000);
    expect(parsePaid('50p', 'GBP'), 0.5);
    expect(parsePaid(r'$241.20', 'USD'), 241.2);
    expect(parsePaid('', 'USD'), isNull);
    expect(parsePaid('none', 'USD'), isNull);
    expect(parsePaid('0', 'USD'), isNull);
  });

  test('prices and changes read the way they are written', () {
    expect(formatPrice(62844.4, 'GBP'), '£62,844');
    expect(formatPrice(1234567, 'USD'), r'$1,234,567');
    expect(formatPrice(125.8, 'GBp'), '125.80p');
    expect(formatPrice(0.5123, 'EUR'), '€0.5123');
    expect(formatPrice(0.00001234, 'USD'), r'$0.000012');
    expect(formatPrice(99.5, 'CHF'), '99.50 CHF');
    expect(formatChange(0.399), '+0.40%');
    expect(formatPrice(0, 'GBP'), '£0.00');
    expect(formatChange(-1.46), '−1.46%');
    expect(formatCompact(52510918), '52.5M');
    expect(formatCompact(1262534998953), '1.26T');
    expect(formatCompact(940), '940');
    expect(formatCompactPrice(21.7e9, 'GBP'), '£21.7B');
  });

  group('tiles', () {
    setUpAll(registerBuiltInWidgets);

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size,
      MarketsService markets, {
      Map<String, dynamic>? options,
    }) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find(type)!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'w',
          type: type,
          x: 0,
          y: 0,
          width: 3,
          height: 2,
          options: options,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: markets,
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

    testWidgets('stocks fit every tile shape', (tester) async {
      final markets = MarketsService();
      addTearDown(markets.dispose);
      final history = [for (var i = 0; i < 30; i++) 100.0 + i % 7];
      markets
        ..debugSetStock(
          '^FTSE',
          '1d',
          Quote(
            symbol: '^FTSE',
            name: 'FTSE 100',
            price: 10695.25,
            currency: 'GBP',
            changePercent: 0.14,
            history: history,
            previousClose: 10680,
            high: 10720,
            low: 10650,
            yearHigh: 10900,
            yearLow: 7800,
            volume: 5.2e8,
            exchange: 'FTSE',
          ),
        )
        ..debugSetStock(
          '^GSPC',
          '1d',
          Quote(
            symbol: '^GSPC',
            name: 'S&P 500',
            price: 6512.1,
            currency: 'USD',
            changePercent: -0.31,
            history: history,
          ),
        )
        ..debugSetStock(
          'AAPL',
          '1d',
          Quote(
            symbol: 'AAPL',
            name: 'Apple',
            price: 241.2,
            currency: 'USD',
            changePercent: 1.02,
            history: history,
          ),
        );
      for (final view in ['list', 'cards', 'single']) {
        for (final (w, h) in shapes) {
          await draw(tester, 'stocks', tile(w, h), markets,
              options: {'view': view});
          expect(tester.takeException(), isNull, reason: '$view ${w}x$h');
        }
      }
      // Paid near today's prices, and far below them: a line on the chart,
      // and a note at its edge.
      final paid = {
        'stocks': [
          {'symbol': '^FTSE', 'name': '', 'paid': '10690'},
          {'symbol': 'AAPL', 'name': '', 'paid': '20'},
        ],
      };
      for (final view in ['list', 'cards', 'single']) {
        for (final (w, h) in shapes) {
          await draw(tester, 'stocks', tile(w, h), markets,
              options: {...paid, 'view': view});
          expect(tester.takeException(), isNull, reason: 'paid $view ${w}x$h');
        }
      }
      await draw(tester, 'stocks', tile(6, 4), markets,
          options: {...paid, 'view': 'list'});
      expect(find.textContaining('+0.05% on £10,690'), findsOneWidget);
      await draw(tester, 'stocks', tile(6, 8), markets,
          options: {...paid, 'view': 'single'});
      expect(find.text('Since you paid £10,690'), findsOneWidget);

      // Holdings: a total above the list, and each one's worth and gain.
      final held = {
        'stocks': [
          {
            'symbol': '^FTSE',
            'name': '',
            'paid': '10000',
            'quantity': 2,
            'bought': '2026-01-05',
            'fees': 10,
          },
          {'symbol': 'AAPL', 'name': '', 'quantity': 3},
        ],
      };
      for (final view in ['list', 'cards', 'single']) {
        for (final (w, h) in shapes) {
          await draw(tester, 'stocks', tile(w, h), markets,
              options: {...held, 'view': view});
          expect(tester.takeException(), isNull, reason: 'held $view ${w}x$h');
        }
      }
      await draw(tester, 'stocks', tile(6, 8), markets,
          options: {...held, 'view': 'single'});
      expect(find.text('Your 2 shares'), findsOneWidget);
      expect(find.text('£21,391'), findsOneWidget);
      expect(find.text('Holdings'), findsWidgets);

      await draw(tester, 'stocks', tile(4, 3), markets);
      expect(find.text('FTSE 100'), findsOneWidget);
      expect(find.text('£10,695'), findsOneWidget);
      expect(find.text('−0.31%'), findsOneWidget);
    });

    testWidgets('crypto fits every tile shape', (tester) async {
      final markets = MarketsService();
      addTearDown(markets.dispose);
      for (final (entry, name, price) in [
        ('bitcoin', 'Bitcoin', 62844.0),
        ('ethereum', 'Ethereum', 1912.5),
      ]) {
        markets.debugSetCoin(
          entry,
          'gbp',
          '24h',
          Quote(
            symbol: entry.substring(0, 3).toUpperCase(),
            name: name,
            price: price,
            currency: 'GBP',
            changePercent: -1.2,
            history: const [1, 3, 2, 4],
            times: [
              for (var i = 0; i < 4; i++) DateTime(2026, 9, 28, 9 + i),
            ],
            high: price * 1.02,
            low: price * 0.97,
            marketCap: price * 2e7,
            volume: price * 3e5,
            allTimeHigh: price * 1.4,
            rank: 1,
          ),
        );
      }
      for (final view in ['list', 'cards', 'single']) {
        for (final (w, h) in shapes) {
          await draw(tester, 'crypto', tile(w, h), markets,
              options: {'view': view});
          expect(tester.takeException(), isNull, reason: '$view ${w}x$h');
        }
      }
      await draw(tester, 'crypto', tile(6, 8), markets,
          options: {'view': 'cards'});
      expect(find.text('Market cap'), findsWidgets);
      expect(find.text('£62,844'), findsOneWidget);
    });
  });

  test('Coinbase candles, oldest to newest, when CoinGecko can’t be asked', () {
    final q = MarketsService.parseCoinbase(
      [
        // Newest first, as Coinbase sends them: time, low, high, open, close.
        [1790679600, 99.0, 112.0, 105.0, 110.0, 3.1],
        [1790676000, 95.0, 106.0, 100.0, 105.0, 2.2],
        ['bad'],
      ],
      'BTC',
      'Bitcoin',
      'gbp',
    )!;
    expect(q.price, 110);
    expect(q.changePercent, closeTo(10, 1e-9));
    expect(q.history, [105, 110]);
    expect(q.high, 112);
    expect(q.low, 95);
    expect(q.currency, 'GBP');
    expect(q.exchange, 'Coinbase');
    expect(MarketsService.parseCoinbase([], 'BTC', 'Bitcoin', 'gbp'), isNull);
  });
}
