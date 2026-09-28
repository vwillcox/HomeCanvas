import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';

/// A price, how it has moved, and the recent path it took to get there.
@immutable
class Quote {
  const Quote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.currency,
    this.changePercent,
    this.history = const [],
    this.times = const [],
    this.image,
    this.previousClose,
    this.high,
    this.low,
    this.yearHigh,
    this.yearLow,
    this.allTimeHigh,
    this.volume,
    this.marketCap,
    this.rank,
    this.exchange,
  });

  /// "VOD.L", "BTC".
  final String symbol;
  final String name;
  final double price;

  /// ISO code, except Yahoo's "GBp" for London prices quoted in pence.
  final String currency;

  /// Today's move for a stock, the chosen period's for a coin.
  final double? changePercent;

  /// Oldest first, for the sparkline.
  final List<double> history;

  /// When each of [history] was, where known — the same length, or empty.
  final List<DateTime> times;

  /// The coin's logo. Stocks have none without a paid service.
  final String? image;

  // The detail the card view shows, each only where the source gives it.

  /// Yesterday's close — the line a day's chart is measured against.
  final double? previousClose;

  /// The day's range for a stock, the last 24 hours' for a coin.
  final double? high;
  final double? low;

  /// The 52-week range. Stocks only.
  final double? yearHigh;
  final double? yearLow;

  /// Coins only.
  final double? allTimeHigh;

  /// Shares traded today, or a coin's 24-hour volume in [currency].
  final double? volume;

  /// Coins only: stocks' needs a paid service.
  final double? marketCap;

  /// A coin's place by market cap.
  final int? rank;

  /// "LSE", "NasdaqGS".
  final String? exchange;

  /// The same quote over a different stretch of history.
  Quote withHistory(
    List<double> history,
    List<DateTime> times, {
    double? changePercent,
  }) => Quote(
    symbol: symbol,
    name: name,
    price: price,
    currency: currency,
    changePercent: changePercent ?? this.changePercent,
    history: history,
    times: times,
    image: image,
    previousClose: previousClose,
    high: high,
    low: low,
    yearHigh: yearHigh,
    yearLow: yearLow,
    allTimeHigh: allTimeHigh,
    volume: volume,
    marketCap: marketCap,
    rank: rank,
    exchange: exchange,
  );
}

/// Share prices from Yahoo Finance's chart endpoint, and coin prices from
/// CoinGecko. Both free and without a key; Yahoo's is unofficial, so a
/// change on their side shows as "Not found" rather than a crash.
///
/// Widgets call [ensureStocks] and [ensureCoins] as often as they like —
/// each only fetches what is older than the age it is given.
class MarketsService extends ChangeNotifier {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // Yahoo turns away requests with no browser-like agent.
      headers: const {'User-Agent': 'Mozilla/5.0 (X11; Linux) HomeCanvas/1.0'},
    ),
  );

  final Map<String, Quote> _quotes = {};
  final Map<String, String> _errors = {};
  final Map<String, DateTime> _fetched = {};
  final Set<String> _busy = {};
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _dio.close(force: true);
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Holds [q] as if just fetched — for tests.
  @visibleForTesting
  void debugSetStock(String symbol, String range, Quote q) =>
      _debugSet(_stockKey(symbol, range), q);

  @visibleForTesting
  void debugSetCoin(String entry, String currency, String period, Quote q) =>
      _debugSet(_coinKey(entry, currency, period), q);

  void _debugSet(String key, Quote q) {
    _quotes[key] = q;
    _fetched[key] = DateTime.now();
    _changed();
  }

  bool _due(String key, Duration maxAge, bool force) {
    if (_busy.contains(key)) return false;
    final last = _fetched[key];
    return force || last == null || DateTime.now().difference(last) > maxAge;
  }

  /// Marks [key] fetched — or, after a failure, due again in a few minutes
  /// rather than a whole [maxAge] later.
  void _done(String key, Duration maxAge, {required bool ok}) {
    const retry = Duration(minutes: 3);
    _fetched[key] = ok || maxAge <= retry
        ? DateTime.now()
        : DateTime.now().subtract(maxAge - retry);
  }

  // ---------------------------------------------------------------- stocks

  static String _stockKey(String symbol, String range) =>
      'stock|${symbol.toUpperCase()}|$range';

  Quote? stock(String symbol, String range) =>
      _quotes[_stockKey(symbol, range)];

  String? stockError(String symbol, String range) =>
      _errors[_stockKey(symbol, range)];

  /// [range] is Yahoo's: `1d`, `5d`, `1mo`, `3mo` or `1y`.
  Future<void> ensureStocks(
    List<String> symbols, {
    required String range,
    required Duration maxAge,
    bool force = false,
  }) async {
    final due = [
      for (final s in symbols)
        if (_due(_stockKey(s, range), maxAge, force)) s,
    ];
    if (due.isEmpty) return;
    await Future.wait([for (final s in due) _fetchStock(s, range, maxAge)]);
    _changed();
  }

  /// What an entry that wasn't a symbol turned out to mean — "RPI" is
  /// "RPI.L" — so the search is made once, not at every refresh.
  final Map<String, String> _resolved = {};

  Future<void> _fetchStock(String symbol, String range, Duration maxAge) async {
    final key = _stockKey(symbol, range);
    _busy.add(key);
    try {
      final entry = symbol.toUpperCase();
      var quote = await _chart(_resolved[entry] ?? entry, range);
      if (quote == null && !_resolved.containsKey(entry)) {
        final found = await _search(symbol);
        if (found != null && found != entry) {
          quote = await _chart(found, range);
          if (quote != null) _resolved[entry] = found;
        }
      }
      if (quote == null) {
        _errors[key] = tr('widget.markets.notFound', 'Not found');
      } else {
        _quotes[key] = quote;
        _errors.remove(key);
      }
      _done(key, maxAge, ok: true);
    } catch (e) {
      _errors[key] = tr('widget.markets.unreachable', 'Unreachable');
      _done(key, maxAge, ok: false);
      debugPrint('Markets: $symbol: $e');
    } finally {
      _busy.remove(key);
    }
  }

  Future<Quote?> _chart(String symbol, String range) async {
    // A day's chart is asked for as five days and cut to the last session,
    // so that before the market opens — or just after, with one point —
    // there is still a day to show.
    final day = range == '1d';
    final interval = switch (range) {
      '5d' => '1h',
      '1mo' || '3mo' || '1y' => '1d',
      _ => '15m',
    };
    final r = await _dio.get<Map<String, dynamic>>(
      'https://query1.finance.yahoo.com/v8/finance/chart/'
      '${Uri.encodeComponent(symbol)}',
      queryParameters: {'range': day ? '5d' : range, 'interval': interval},
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    return r.data == null ? null : parseChart(r.data!, lastSession: day);
  }

  /// The listing Yahoo's search thinks [query] means, for a symbol given
  /// without its exchange ("RPI") or a company's name ("raspberry pi").
  Future<String?> _search(String query) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://query2.finance.yahoo.com/v1/finance/search',
        queryParameters: {'q': query, 'quotesCount': 8, 'newsCount': 0},
      );
      return r.data == null ? null : pickSearch(query, r.data!);
    } catch (e) {
      debugPrint('Markets: search $query: $e');
      return null;
    }
  }

  /// The same ticker on another exchange if there is one — "RPI" finds
  /// "RPI.L" ahead of anything merely similar — or else Yahoo's first answer.
  @visibleForTesting
  static String? pickSearch(String query, Map<String, dynamic> json) {
    final symbols = [
      for (final q in (json['quotes'] as List? ?? const []).whereType<Map>())
        if (q['symbol'] is String && '${q['symbol']}'.isNotEmpty)
          '${q['symbol']}',
    ];
    final ticker = '${query.trim().toUpperCase()}.';
    return symbols.where((s) => s.startsWith(ticker)).firstOrNull ??
        symbols.firstOrNull;
  }

  /// A Yahoo chart response, or null for "no such symbol".
  ///
  /// With [lastSession], only the latest day's trading is kept — or the day
  /// before, if the latest has barely begun — and the close before it is the
  /// previous close.
  @visibleForTesting
  static Quote? parseChart(
    Map<String, dynamic> json, {
    bool lastSession = false,
  }) {
    final results = (json['chart'] as Map?)?['result'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      return null;
    }
    final result = results.first as Map;
    final meta = (result['meta'] as Map?) ?? const {};
    final price = meta['regularMarketPrice'];
    if (price is! num) return null;

    final quotes = ((result['indicators'] as Map?)?['quote'] as List?) ?? [];
    final closes = quotes.isEmpty ? null : (quotes.first as Map?)?['close'];
    final stamps = result['timestamp'];
    // Gaps, where nothing traded, are left out — along with their times.
    final history = <double>[];
    final times = <DateTime>[];
    if (closes is List) {
      final timed = stamps is List && stamps.length == closes.length;
      for (var i = 0; i < closes.length; i++) {
        final c = closes[i];
        if (c is! num) continue;
        history.add(c.toDouble());
        if (timed && stamps[i] is num) {
          times.add(
            DateTime.fromMillisecondsSinceEpoch((stamps[i] as num).toInt() * 1000),
          );
        }
      }
      if (times.length != history.length) times.clear();
    }
    double? number(String key) {
      final v = meta[key];
      return v is num ? v.toDouble() : null;
    }

    double? sessionClose;
    if (lastSession && times.isNotEmpty) {
      // Days as the exchange counts them, not as the panel's clock does.
      final offset = Duration(seconds: (number('gmtoffset') ?? 0).toInt());
      int dayOf(DateTime t) {
        final local = t.toUtc().add(offset);
        return local.year * 10000 + local.month * 100 + local.day;
      }

      var start = times.length - 1;
      while (start > 0 && dayOf(times[start - 1]) == dayOf(times.last)) {
        start--;
      }
      // Two points make a line; with fewer, show the whole day before.
      if (times.length - start < 2 && start > 0) {
        final end = start;
        start = end - 1;
        while (start > 0 && dayOf(times[start - 1]) == dayOf(times[end - 1])) {
          start--;
        }
        final kept = history.sublist(start, end);
        final keptTimes = times.sublist(start, end);
        if (start > 0) sessionClose = history[start - 1];
        history
          ..clear()
          ..addAll(kept);
        times
          ..clear()
          ..addAll(keptTimes);
      } else {
        if (start > 0) sessionClose = history[start - 1];
        history.removeRange(0, start);
        times.removeRange(0, start);
      }
    }

    double? change;
    final given = meta['regularMarketChangePercent'];
    if (given is num) {
      change = given.toDouble();
    } else {
      // A day's chart starts at yesterday's close; a longer one doesn't, so
      // only a named previous close will do there.
      final prev = meta['previousClose'] ??
          (meta['range'] == '1d' ? meta['chartPreviousClose'] : null);
      if (prev is num && prev != 0) change = (price - prev) / prev * 100;
    }

    final symbol = '${meta['symbol'] ?? ''}';
    // Indices are best by their short name ("FTSE 100"), companies by their
    // long one ("VODAFONE GROUP PLC ORD USD0.20" is a listing, not a name).
    final long = '${meta['longName'] ?? ''}'.trim();
    final short = '${meta['shortName'] ?? ''}'.trim();
    final name = meta['instrumentType'] == 'EQUITY' && long.isNotEmpty
        ? _plainCompany(long)
        : (short.isNotEmpty ? short : (long.isNotEmpty ? long : symbol));

    return Quote(
      symbol: symbol,
      name: name,
      price: price.toDouble(),
      currency: '${meta['currency'] ?? ''}',
      changePercent: change,
      history: history,
      times: times,
      previousClose: number('previousClose') ??
          (meta['range'] == '1d' ? number('chartPreviousClose') : null) ??
          sessionClose,
      high: number('regularMarketDayHigh'),
      low: number('regularMarketDayLow'),
      yearHigh: number('fiftyTwoWeekHigh'),
      yearLow: number('fiftyTwoWeekLow'),
      // Indices report none.
      volume: (number('regularMarketVolume') ?? 0) > 0
          ? number('regularMarketVolume')
          : null,
      exchange: '${meta['exchangeName'] ?? ''}'.isEmpty
          ? null
          : '${meta['exchangeName']}',
    );
  }

  /// "Vodafone Group Public Limited Company" → "Vodafone Group".
  static String _plainCompany(String name) => name
      .replaceFirst(
        RegExp(
          r',?\s+(Inc\.?|Incorporated|Corporation|Corp\.?|plc|PLC|'
          r'Public Limited Company|Limited|Ltd\.?|N\.V\.|S\.A\.|SE|AG)$',
        ),
        '',
      )
      .trim();

  // ---------------------------------------------------------------- crypto

  static String _coinKey(String entry, String currency, String period) =>
      'coin|${entry.trim().toLowerCase()}|$currency|$period';

  Quote? coin(String entry, String currency, String period) =>
      _quotes[_coinKey(entry, currency, period)];

  String? coinError(String entry, String currency, String period) =>
      _errors[_coinKey(entry, currency, period)];

  /// Periods longer than the week `coins/markets` sketches, and how many
  /// days of history each asks `market_chart` for.
  static const _longPeriods = {'30d': 30, '90d': 90, '1y': 365};

  /// Those longer histories, by coin, currency and period. A month or a
  /// year's shape hardly changes between checks, and each is a request of
  /// its own, so they are kept for half an hour — well inside CoinGecko's
  /// free allowance.
  final Map<String, ({DateTime at, List<double> history, List<DateTime> times})>
  _histories = {};

  /// [coins] are CoinGecko ids ("bitcoin") or ticker symbols ("BTC");
  /// [currency] is `gbp`, `usd` or `eur`; [period] `24h`, `7d`, `30d`,
  /// `90d` or `1y`.
  Future<void> ensureCoins(
    List<String> coins, {
    required String currency,
    required String period,
    required Duration maxAge,
    bool force = false,
  }) async {
    final due = [
      for (final c in coins)
        if (c.trim().isNotEmpty && _due(_coinKey(c, currency, period), maxAge, force))
          c.trim().toLowerCase(),
    ];
    if (due.isEmpty) return;
    final keys = [for (final c in due) _coinKey(c, currency, period)];
    _busy.addAll(keys);
    try {
      Future<List<({String id, Quote quote})>> markets(
        String by,
        Iterable<String> values,
      ) async {
        final r = await _dio.get<List<dynamic>>(
          'https://api.coingecko.com/api/v3/coins/markets',
          queryParameters: {
            'vs_currency': currency,
            by: values.join(','),
            if (by == 'symbols') 'include_tokens': 'top',
            'sparkline': 'true',
            // It has no 90-day change; that one is worked out from the
            // history below.
            'price_change_percentage': period == '90d' ? '24h' : period,
          },
        );
        return parseMarkets(r.data ?? const [], currency, period);
      }

      // Ids and symbols can't be asked for together — CoinGecko answers
      // only the ids — so whatever isn't an id is tried as a symbol.
      final found = <String, ({String id, Quote quote})>{};
      for (final q in await markets('ids', due)) {
        found[q.id] = q;
      }
      final rest = due.where((c) => !found.containsKey(c)).toList();
      if (rest.isNotEmpty) {
        for (final q in await markets('symbols', rest)) {
          found.putIfAbsent(q.quote.symbol.toLowerCase(), () => q);
        }
      }

      final days = _longPeriods[period];
      if (days != null) {
        for (final entry in found.entries.toList()) {
          final h = await _history(entry.value.id, currency, period, days, force);
          if (h == null || h.history.length < 2) continue;
          final q = entry.value.quote;
          final first = h.history.first;
          found[entry.key] = (
            id: entry.value.id,
            quote: q.withHistory(
              h.history,
              h.times,
              changePercent: period == '90d' && first != 0
                  ? (q.price - first) / first * 100
                  : null,
            ),
          );
        }
      }
      for (final c in due) {
        final key = _coinKey(c, currency, period);
        final q = found[c]?.quote;
        if (q == null) {
          _errors[key] = tr('widget.markets.notFound', 'Not found');
        } else {
          _quotes[key] = q;
          _errors.remove(key);
        }
        _done(key, maxAge, ok: true);
      }
    } catch (e) {
      for (final key in keys) {
        _errors[key] = tr('widget.markets.unreachable', 'Unreachable');
        _done(key, maxAge, ok: false);
      }
      debugPrint('Markets: coins: $e');
    } finally {
      _busy.removeAll(keys);
      _changed();
    }
  }

  /// A coin's history over [days], from the half-hour cache when it can be.
  /// Null if it couldn't be fetched: the tile then keeps the week's sketch
  /// rather than showing nothing.
  Future<({List<double> history, List<DateTime> times})?> _history(
    String id,
    String currency,
    String period,
    int days,
    bool force,
  ) async {
    final key = '$id|$currency|$period';
    final kept = _histories[key];
    if (kept != null &&
        !force &&
        DateTime.now().difference(kept.at) < const Duration(minutes: 30)) {
      return (history: kept.history, times: kept.times);
    }
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://api.coingecko.com/api/v3/coins/'
        '${Uri.encodeComponent(id)}/market_chart',
        queryParameters: {
          'vs_currency': currency,
          'days': days,
          // Hourly for a year is thousands of points; a day each is plenty.
          if (days > 90) 'interval': 'daily',
        },
      );
      final h = parseHistory(r.data ?? const {});
      _histories[key] = (at: DateTime.now(), history: h.history, times: h.times);
      return h;
    } catch (e) {
      debugPrint('Markets: $id history: $e');
      return kept == null ? null : (history: kept.history, times: kept.times);
    }
  }

  /// A CoinGecko `market_chart` response, thinned to at most [points] —
  /// enough for any tile, where 90 days hourly is over two thousand — and
  /// always keeping the latest.
  @visibleForTesting
  static ({List<double> history, List<DateTime> times}) parseHistory(
    Map<String, dynamic> json, {
    int points = 240,
  }) {
    final raw = [
      for (final p in (json['prices'] as List? ?? const []).whereType<List>())
        if (p.length >= 2 && p[0] is num && p[1] is num)
          (
            at: DateTime.fromMillisecondsSinceEpoch((p[0] as num).toInt()),
            price: (p[1] as num).toDouble(),
          ),
    ];
    final step = raw.length <= points ? 1 : (raw.length / points).ceil();
    final kept = [
      for (var i = 0; i < raw.length; i += step) raw[i],
      if (raw.isNotEmpty && (raw.length - 1) % step != 0) raw.last,
    ];
    return (
      history: [for (final p in kept) p.price],
      times: [for (final p in kept) p.at],
    );
  }

  /// A CoinGecko `coins/markets` response, each with the id it answers to.
  @visibleForTesting
  static List<({String id, Quote quote})> parseMarkets(
    List<dynamic> json,
    String currency,
    String period,
  ) {
    final out = <({String id, Quote quote})>[];
    for (final c in json.whereType<Map>()) {
      final price = c['current_price'];
      if (price is! num) continue;
      final change = c['price_change_percentage_${period}_in_currency'] ??
          c['price_change_percentage_$period'];
      final image = c['image'];
      double? number(String key) {
        final v = c[key];
        return v is num ? v.toDouble() : null;
      }

      final history = _sparkline(
        c['sparkline_in_7d'],
        period,
        price: price.toDouble(),
      );
      // Hourly, ending when the price was last updated.
      final end = DateTime.tryParse('${c['last_updated']}')?.toLocal();
      out.add((
        id: '${c['id']}',
        quote: Quote(
          symbol: '${c['symbol'] ?? ''}'.toUpperCase(),
          name: '${c['name'] ?? c['id']}',
          price: price.toDouble(),
          currency: currency.toUpperCase(),
          changePercent: change is num ? change.toDouble() : null,
          history: history,
          times: end == null
              ? const []
              : [
                  for (var i = 0; i < history.length; i++)
                    end.subtract(Duration(hours: history.length - 1 - i)),
                ],
          image: image is String ? image : null,
          high: number('high_24h'),
          low: number('low_24h'),
          allTimeHigh: number('ath'),
          volume: number('total_volume'),
          marketCap: number('market_cap'),
          rank: (c['market_cap_rank'] as num?)?.toInt(),
        ),
      ));
    }
    return out;
  }

  /// A week of hourly prices, cut to the last day when that is the period.
  ///
  /// CoinGecko gives these in US dollars whatever currency was asked for,
  /// so they are scaled to end at [price] — the same shape, in the right
  /// money, to within the week's movement in the exchange rate.
  static List<double> _sparkline(
    Object? spark,
    String period, {
    required double price,
  }) {
    var prices = [
      if (spark is Map && spark['price'] is List)
        for (final p in spark['price'] as List)
          if (p is num) p.toDouble(),
    ];
    if (period == '24h' && prices.length > 24) {
      prices = prices.sublist(prices.length - 24);
    }
    if (prices.isEmpty || prices.last == 0) return prices;
    final scale = price / prices.last;
    return [for (final p in prices) p * scale];
  }
}

/// "£62,844", "125.80p", "$0.5123", "1,234.50 CHF".
String formatPrice(double v, String currency) {
  if (currency == 'GBp' || currency == 'GBX') return '${_number(v)}p';
  final code = currency.toUpperCase();
  final sign = const {'USD': r'$', 'GBP': '£', 'EUR': '€', 'JPY': '¥'}[code];
  return sign != null ? '$sign${_number(v)}' : '${_number(v)} $code';
}

/// "52.5M", "1.26T", "940" — for volumes and market caps, where the last
/// few digits are noise.
String formatCompact(double v) {
  const units = [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'K')];
  for (final (size, unit) in units) {
    if (v.abs() >= size) {
      final n = v / size;
      return '${n.toStringAsFixed(n.abs() >= 100 ? 0 : n.abs() >= 10 ? 1 : 2)}$unit';
    }
  }
  return v.toStringAsFixed(0);
}

/// A price in [currency] made compact: "£1.26T", "\$21.7B".
String formatCompactPrice(double v, String currency) {
  final sign = const {
    'USD': r'$',
    'GBP': '£',
    'EUR': '€',
    'JPY': '¥',
  }[currency.toUpperCase()];
  return sign != null
      ? '$sign${formatCompact(v)}'
      : '${formatCompact(v)} ${currency.toUpperCase()}';
}

/// The price someone typed as what they paid, in the units [currency] is
/// quoted in — or null if there is none.
///
/// London shares are quoted in pence, which is easy to forget: "650p" and
/// "£6.50" both mean 650 pence there. A bare number could be either — a
/// share price is as often thought of as "£5.98" as "598p" — so it is taken
/// as whichever is nearer the share's price [now], when that is known.
/// Commas are ignored, so "£62,000" for a coin priced in pounds is 62000.
double? parsePaid(String typed, String currency, {double? now}) {
  final s = typed.trim().toLowerCase();
  if (s.isEmpty) return null;
  final n = double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (n == null || n <= 0) return null;
  final pounds = s.contains('£');
  final pence = s.endsWith('p');
  if (currency == 'GBp' || currency == 'GBX') {
    if (pence) return n;
    if (pounds) return n * 100;
    if (now == null || now <= 0) return n;
    // Nearer as a ratio: 598 is nearer 709 than 5.98 is, by a long way.
    double apart(double v) => v > now ? v / now : now / v;
    return apart(n * 100) < apart(n) ? n * 100 : n;
  }
  if (currency == 'GBP' && pence && !pounds) return n / 100;
  return n;
}

/// What someone holds of a stock or coin, and how it has done.
///
/// Money is in the currency's main unit: a London share is priced in pence,
/// but twelve of them are worth pounds.
@immutable
class Holding {
  const Holding({
    required this.quantity,
    required this.value,
    required this.currency,
    this.cost,
    this.bought,
  });

  final double quantity;

  /// What it is worth at today's price.
  final double value;

  /// What it cost: the price paid for each, times how many, plus fees.
  /// Null when no price paid was given.
  final double? cost;

  /// "GBP", never "GBp".
  final String currency;
  final DateTime? bought;

  double? get gain => cost == null ? null : value - cost!;
  double? get percent =>
      cost == null || cost == 0 ? null : (value - cost!) / cost! * 100;

  /// Works one out from a row's settings, or null without a quantity.
  static Holding? of(
    Quote q, {
    required String quantity,
    required String paid,
    String fees = '',
    String bought = '',
  }) {
    final n = _amount(quantity);
    if (n == null) return null;
    final pence = q.currency == 'GBp' || q.currency == 'GBX';
    double main(double v) => pence ? v / 100 : v;
    final each = parsePaid(paid, q.currency, now: q.price);
    // Fees are what was actually paid out, so already in pounds.
    final extra = _amount(fees) ?? 0;
    return Holding(
      quantity: n,
      value: main(q.price * n),
      cost: each == null ? null : main(each * n) + extra,
      currency: pence ? 'GBP' : q.currency.toUpperCase(),
      bought: parseDay(bought),
    );
  }

  static double? _amount(String typed) {
    final n = double.tryParse(typed.replaceAll(RegExp(r'[^0-9.]'), ''));
    return n == null || n <= 0 ? null : n;
  }
}

/// A day as the editor's date picker stores it (2025-03-12), or as someone
/// might type it: 12/03/2025 (day first, this being a British panel) or
/// 12 Mar 2025.
DateTime? parseDay(String typed) {
  final s = typed.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _day(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final dmy = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$').firstMatch(s);
  if (dmy != null) {
    final y = int.parse(dmy[3]!);
    return _day(y < 100 ? 2000 + y : y, int.parse(dmy[2]!), int.parse(dmy[1]!));
  }
  final named = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{4})$')
      .firstMatch(s);
  if (named != null) {
    const months = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    final m = months.indexOf(named[2]!.toLowerCase()) + 1;
    if (m > 0) return _day(int.parse(named[3]!), m, int.parse(named[1]!));
  }
  return null;
}

DateTime? _day(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final t = DateTime(y, m, d);
  // 31/02 rolls over into March; that is a typing slip, not a date.
  return t.month == m ? t : null;
}

/// "2 years 3 months", "5 months", "12 days", "today".
String heldFor(DateTime since, DateTime now) {
  var months = (now.year - since.year) * 12 + now.month - since.month;
  if (now.day < since.day) months--;
  if (months <= 0) {
    final days = now.difference(since).inDays;
    return days <= 0 ? 'today' : '$days day${days == 1 ? '' : 's'}';
  }
  final years = months ~/ 12, rest = months % 12;
  String unit(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
  return [
    if (years > 0) unit(years, 'year'),
    if (rest > 0) unit(rest, 'month'),
  ].join(' ');
}

/// "+£1,214.50", "−£96.20" — a gain or loss in money.
String formatGain(double v, String currency) =>
    '${v < 0 ? '−' : '+'}${formatPrice(v.abs(), currency)}';

/// "+0.40%", "−1.46%".
String formatChange(double percent) =>
    '${percent < 0 ? '−' : '+'}${percent.abs().toStringAsFixed(2)}%';

/// Whole numbers past a thousand, cents below, and enough places for a coin
/// worth a fraction of a penny to show more than zeros.
String _number(double v) {
  final a = v.abs();
  final int places;
  if (a == 0) {
    places = 2;
  } else if (a >= 1000) {
    places = 0;
  } else if (a >= 1) {
    places = 2;
  } else if (a >= 0.01) {
    places = 4;
  } else {
    places = 6;
  }
  final fixed = a.toStringAsFixed(places);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot);
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${v < 0 ? '-' : ''}$grouped$frac';
}
