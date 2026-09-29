import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/markets_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';
import '../../l10n/dates.dart';
import '../../l10n/l10n.dart';

/// One row a tile was asked for: what to look up, what to call it, and —
/// as typed — what was paid for it, how many are held, when they were
/// bought and what the fees were.
typedef _Pick = ({
  String entry,
  String label,
  String paid,
  String quantity,
  String bought,
  String fees,
});

/// What [pick] holds, worked out at [q]'s price, or null without a quantity.
Holding? _holdingOf(_Pick pick, Quote? q) => q == null
    ? null
    : Holding.of(
        q,
        quantity: pick.quantity,
        paid: pick.paid,
        fees: pick.fees,
        bought: pick.bought,
      );

/// "12 shares", "0.05 coins".
String _howMany(double n, bool coins) {
  final shown = n == n.roundToDouble()
      ? n.toStringAsFixed(0)
      : n.toStringAsFixed(n >= 1 ? 2 : 6).replaceFirst(RegExp(r'0+$'), '');
  final what = coins ? 'coin' : 'share';
  return '$shown $what${n == 1 ? '' : 's'}';
}

/// How far [q] is above or below what [pick] was bought at, or null if no
/// price was given.
({double paid, double percent})? _sincePaid(_Pick pick, Quote? q) {
  if (q == null) return null;
  final paid = parsePaid(pick.paid, q.currency, now: q.price);
  if (paid == null) return null;
  return (paid: paid, percent: (q.price - paid) / paid * 100);
}

/// The rows of list option [key], or its declared default until it has been
/// saved — the same rows the editor shows.
List<_Pick> _picks(
  DashboardWidgetContext w,
  String key,
  String field,
  List<Map<String, String>> defaults,
) {
  final rows = w.config.options.containsKey(key) ? w.rows(key) : defaults;
  return [
    for (final r in rows)
      if ('${r[field] ?? ''}'.trim().isNotEmpty)
        (
          entry: '${r[field]}'.trim(),
          label: '${r['name'] ?? ''}'.trim(),
          paid: '${r['paid'] ?? ''}'.trim(),
          quantity: '${r['quantity'] ?? ''}'.trim(),
          bought: '${r['bought'] ?? ''}'.trim(),
          fees: '${r['fees'] ?? ''}'.trim(),
        ),
  ];
}

int _refreshMinutes(DashboardWidgetContext w) =>
    (int.tryParse('${w.config.options['refreshMinutes'] ?? 5}') ?? 5)
        .clamp(1, 1440);

/// A list of prices that keeps itself fresh while it is on screen, scrolls
/// when there are more than fit, and fetches again when pulled down.
class _MarketsTile extends StatefulWidget {
  const _MarketsTile({
    required this.w,
    required this.picks,
    required this.fetch,
    required this.lookup,
    required this.empty,
    required this.span,
    required this.coins,
  });

  /// How far back the chart goes — `day`, `week`, `month`, `quarter` or
  /// `year` — for labelling its time axis.
  final String span;

  /// Coins, whose volume is money rather than a count of shares.
  final bool coins;

  final DashboardWidgetContext w;
  final List<_Pick> picks;
  final Future<void> Function(MarketsService s, {bool force}) fetch;
  final ({Quote? quote, String? error}) Function(MarketsService s, String entry)
  lookup;

  /// What to say when nothing has been chosen.
  final String empty;

  @override
  State<_MarketsTile> createState() => _MarketsTileState();
}

class _MarketsTileState extends State<_MarketsTile>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Checks each minute; the service only fetches what is older than the
    // tile's refresh setting.
    _timer = everyWhileShown(const Duration(minutes: 1), _refresh);
  }

  @override
  void didUpdateWidget(covariant _MarketsTile old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted || widget.picks.isEmpty) return;
    unawaited(widget.fetch(context.read<MarketsService>()));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    if (widget.picks.isEmpty) return TileMessage(widget.empty, theme: t);
    final service = context.watch<MarketsService>();
    final status = StatusColours.of(t);
    final showChart = widget.w.option('showChart', true);

    // Everything held, added up, above the list — when anything is.
    final holdings = [
      for (final pick in widget.picks)
        ?_holdingOf(pick, widget.lookup(service, pick.entry).quote),
    ];
    Widget withTotal(Widget list) => holdings.isEmpty
        ? list
        : LayoutBuilder(
            builder: (context, c) {
              // A strip of a tile has no room to spare for it.
              if (c.maxHeight < 150) return list;
              // Grows with the tile, like the cards under it.
              final wide = c.maxWidth / 440, tall = c.maxHeight / 400;
              final k = (wide < tall ? wide : tall).clamp(1.0, 2.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Total(holdings: holdings, theme: t, status: status, k: k),
                  const SizedBox(height: 8),
                  Expanded(child: list),
                ],
              );
            },
          );

    final view = widget.w.option('view', 'list');
    if (view == 'cards' || view == 'single') {
      return withTotal(LayoutBuilder(
        builder: (context, c) {
          // Half the tile each, two at once — or the whole tile for one —
          // but never so short the chart has no room.
          final height = view == 'single' || c.maxHeight < 200
              ? c.maxHeight
              : (c.maxHeight / 2).clamp(200.0, c.maxHeight);
          return RefreshIndicator(
            onRefresh: () => widget.fetch(service, force: true),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              itemExtent: height,
              itemCount: widget.picks.length,
              itemBuilder: (context, i) {
                final pick = widget.picks[i];
                final found = widget.lookup(service, pick.entry);
                return Padding(
                  // The gap between cards, but none under the last.
                  padding: EdgeInsets.only(
                    bottom: i == widget.picks.length - 1 ? 0 : 10,
                  ),
                  child: _Card(
                    pick: pick,
                    quote: found.quote,
                    error: found.error,
                    theme: t,
                    status: status,
                    span: widget.span,
                    coins: widget.coins,
                  ),
                );
              },
            ),
          );
        },
      ));
    }

    return withTotal(LayoutBuilder(
      builder: (context, c) {
        // A sparkline squeezed under 60px says nothing; the price matters more.
        final chart = showChart && c.maxWidth >= 300;
        return RefreshIndicator(
          onRefresh: () => widget.fetch(service, force: true),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: widget.picks.length,
            separatorBuilder: (_, _) => Divider(
              height: 12,
              thickness: 1,
              color: t.textSecondary.withValues(alpha: 0.15),
            ),
            itemBuilder: (context, i) {
              final pick = widget.picks[i];
              final found = widget.lookup(service, pick.entry);
              return _Row(
                pick: pick,
                quote: found.quote,
                error: found.error,
                chart: chart,
                theme: t,
                status: status,
              );
            },
          ),
        );
      },
    ));
  }
}

/// What everything held on the tile is worth, and what it has made or lost.
/// A line for each currency, since pounds and dollars don't add up.
class _Total extends StatelessWidget {
  const _Total({
    required this.holdings,
    required this.theme,
    required this.status,
    required this.k,
  });

  final List<Holding> holdings;
  final DashboardTheme theme;
  final StatusColours status;

  /// How much bigger than its smallest it is drawn.
  final double k;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final byCurrency = <String, List<Holding>>{};
    for (final h in holdings) {
      byCurrency.putIfAbsent(h.currency, () => []).add(h);
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 8 * k),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12 * k),
      ),
      child: Column(
        children: [
          for (final MapEntry(key: currency, value: group)
              in byCurrency.entries)
            _line(currency, group, k),
        ],
      ),
    );
  }

  Widget _line(String currency, List<Holding> group, double k) {
    final t = theme;
    final value = group.fold<double>(0, (a, h) => a + h.value);
    // Gains only from the holdings with a price paid; a holding without one
    // adds to the value but can't say what it made.
    final known = group.where((h) => h.cost != null).toList();
    final cost = known.fold<double>(0, (a, h) => a + h.cost!);
    final gain = known.fold<double>(0, (a, h) => a + h.value) - cost;
    final colour = gain < 0 ? status.bad : status.good;
    return Row(
      children: [
        Flexible(
          child: Text(
            tr('widget.markets.holdings', 'Holdings'),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(color: t.textSecondary, fontSize: 12 * k),
          ),
        ),
        SizedBox(width: 10 * k),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatPrice(value, currency),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17 * k,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (known.isNotEmpty && cost > 0)
                    TextSpan(
                      text: '   ${formatGain(gain, currency)}'
                          '  ${formatChange(gain / cost * 100)}',
                      style: TextStyle(
                        color: colour,
                        fontSize: 14 * k,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.pick,
    required this.quote,
    required this.error,
    required this.chart,
    required this.theme,
    required this.status,
  });

  final _Pick pick;
  final Quote? quote;
  final String? error;
  final bool chart;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final q = quote;
    final change = q?.changePercent;
    final colour = change == null
        ? t.textSecondary
        : change < 0
        ? status.bad
        : status.good;
    final name = pick.label.isNotEmpty ? pick.label : (q?.name ?? pick.entry);
    final symbol = q?.symbol ?? pick.entry.toUpperCase();
    final since = _sincePaid(pick, q);
    final held = _holdingOf(pick, q);
    // What goes after the symbol: the holding's worth and what it has made,
    // or without a quantity, how the price compares with what was paid.
    final String? mine;
    final Color? mineColour;
    if (held != null) {
      final gain = held.gain, percent = held.percent;
      mine = [
        formatPrice(held.value, held.currency),
        if (gain != null && percent != null)
          '${formatGain(gain, held.currency)} (${formatChange(percent)})',
      ].join(' · ');
      mineColour = gain == null
          ? t.textPrimary
          : gain < 0
          ? status.bad
          : status.good;
    } else if (since != null) {
      mine = '${formatChange(since.percent)} on '
          '${formatPrice(since.paid, q!.currency)}';
      mineColour = since.percent < 0 ? status.bad : status.good;
    } else {
      mine = null;
      mineColour = null;
    }

    return SizedBox(
      height: 42,
      child: Row(
        children: [
          if (q?.image != null) ...[
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: q!.image!,
                width: 24,
                height: 24,
                errorWidget: (_, _, _) => const SizedBox(width: 24),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      // Only worth repeating when the name is something else.
                      if (name.toUpperCase() != symbol)
                        TextSpan(text: mine == null ? symbol : '$symbol · '),
                      if (mine != null)
                        TextSpan(
                          text: mine,
                          style: TextStyle(
                            color: mineColour,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (chart && q != null && q.history.length > 1) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              height: 28,
              child: CustomPaint(
                painter: _Sparkline(q.history, colour, paid: since?.paid),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                q == null
                    ? (error ?? '…')
                    : formatPrice(q.price, q.currency),
                style: TextStyle(
                  color: q == null ? t.textSecondary : t.textPrimary,
                  fontSize: q == null ? 13 : 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (change != null)
                Text(
                  formatChange(change),
                  style: TextStyle(
                    color: colour,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The recent path of a price, scaled to fill its box top to bottom.
class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.colour, {this.paid});

  final List<double> values;
  final Color colour;

  /// What was paid, drawn faintly across when it falls within the chart.
  final double? paid;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo == 0 ? 1 : hi - lo;
    final p = paid;
    if (p != null && p >= lo && p <= hi) {
      final y = size.height - (p - lo) / span * size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = colour.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final y = size.height - (values[i] - lo) / span * size.height;
      i == 0 ? path.moveTo(0, y) : path.lineTo(i * dx, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Sparkline old) =>
      old.values != values || old.colour != colour || old.paid != paid;
}

/// One stock or coin at length: a large chart and the figures around it.
class _Card extends StatelessWidget {
  const _Card({
    required this.pick,
    required this.quote,
    required this.error,
    required this.theme,
    required this.status,
    required this.span,
    required this.coins,
  });

  final _Pick pick;
  final Quote? quote;
  final String? error;
  final DashboardTheme theme;
  final StatusColours status;
  final String span;
  final bool coins;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final q = quote;
    final change = q?.changePercent;
    final colour = change == null
        ? t.accent
        : change < 0
        ? status.bad
        : status.good;
    final name = pick.label.isNotEmpty ? pick.label : (q?.name ?? pick.entry);
    final sub = [
      q?.symbol ?? pick.entry.toUpperCase(),
      if (q?.exchange != null) q!.exchange!,
      if (q?.rank != null) '#${q!.rank}',
    ].join(' · ');
    String money(double v) => formatPrice(v, q!.currency);
    final since = _sincePaid(pick, q);
    final held = _holdingOf(pick, q);
    final now = DateTime.now();

    // What the percentage is in money: the price now against the price it
    // was measured from.
    String? moved;
    if (q != null && change != null && change > -100 && change != 0) {
      final by = q.price - q.price / (1 + change / 100);
      moved = '${by < 0 ? '−' : '+'}${money(by.abs())}';
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Everything grows with the card, so a card half the screen is read
        // from across the room rather than being a small one with space
        // around it.
        final fit = c.maxWidth / 440 < c.maxHeight / 230
            ? c.maxWidth / 440
            : c.maxHeight / 230;
        final k = fit.clamp(1.0, 2.5);
        final facts = q == null || c.maxHeight < 190 * k
            ? const <(String, String, Color?)>[]
            : [
                // Yours first: what you hold, what it has made, and how long
                // you've had it — or, with no quantity, how the price
                // compares with what you paid.
                if (held != null) ...[
                  (
                    tr(
                      'widget.markets.your',
                      'Your {coins}',
                      {'coins': _howMany(held.quantity, coins)},
                    ),
                    formatPrice(held.value, held.currency),
                    null,
                  ),
                  if (held.gain != null)
                    (
                      '${held.gain! < 0 ? 'Loss' : 'Gain'} on '
                          '${money(since!.paid)} each',
                      '${formatGain(held.gain!, held.currency)} · '
                          '${formatChange(held.percent!)}',
                      held.gain! < 0 ? status.bad : status.good,
                    ),
                  if (held.bought != null)
                    (
                      tr('widget.markets.held', 'Held'),
                      heldFor(held.bought!, now),
                      null,
                    ),
                ] else if (since != null)
                  (
                    tr(
                      'widget.markets.sinceYouPaid',
                      'Since you paid {paid}',
                      {'paid': money(since.paid)},
                    ),
                    formatChange(since.percent),
                    since.percent < 0 ? status.bad : status.good,
                  ),
                ..._facts(q, money),
              ];
        return Container(
          padding: EdgeInsets.fromLTRB(14 * k, 12 * k, 14 * k, 12 * k),
          decoration: BoxDecoration(
            color: t.textPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14 * k),
            border: Border.all(color: t.textSecondary.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (q?.image != null) ...[
                    ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: q!.image!,
                        width: 32 * k,
                        height: 32 * k,
                        errorWidget: (_, _, _) => SizedBox(width: 32 * k),
                      ),
                    ),
                    SizedBox(width: 10 * k),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 19 * k,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 12 * k,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10 * k),
                  // Shrinks on a narrow tile rather than pushing off its edge.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth * 0.55),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            q == null ? (error ?? '…') : money(q.price),
                            style: TextStyle(
                              color: q == null
                                  ? t.textSecondary
                                  : t.textPrimary,
                              fontSize: (q == null ? 14 : 22) * k,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (change != null)
                            Text(
                              [formatChange(change), ?moved].join('  '),
                              style: TextStyle(
                                color: colour,
                                fontSize: 13 * k,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8 * k),
              Expanded(
                child: q != null && q.history.length > 1
                    ? CustomPaint(
                        painter: _Chart(
                          values: q.history,
                          times: q.times,
                          colour: colour,
                          theme: t,
                          // A day's chart is read against yesterday's close.
                          baseline: span == 'day' && !coins
                              ? q.previousClose
                              : null,
                          span: span,
                          label: money,
                          scale: k,
                          paid: since?.paid,
                          bought: held?.bought ?? parseDay(pick.bought),
                          paidColour: status.warn,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (facts.isNotEmpty) ...[
                SizedBox(height: 10 * k),
                LayoutBuilder(
                  builder: (context, row) {
                    // As many as fit side by side, the likeliest wanted first,
                    // and a second row on a card tall enough to spare it.
                    final n = (row.maxWidth / (140 * k))
                        .floor()
                        .clamp(1, facts.length);
                    final rows =
                        c.maxHeight >= 300 * k && facts.length > n ? 2 : 1;
                    final shown = facts.take(n * rows).toList();
                    return Column(
                      children: [
                        for (var r = 0; r * n < shown.length; r++)
                          Padding(
                            padding: EdgeInsets.only(top: r == 0 ? 0 : 8 * k),
                            child: Row(
                              children: [
                                for (var i = r * n; i < r * n + n; i++)
                                  if (i < shown.length)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shown[i].$1,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: t.textSecondary,
                                              fontSize: 11 * k,
                                            ),
                                          ),
                                          Text(
                                            shown[i].$2,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: shown[i].$3 ?? t.textPrimary,
                                              fontSize: 13 * k,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  // Keeps a short last row in step with the
                                  // one above it.
                                  else
                                    const Spacer(),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<(String, String, Color?)> _facts(
    Quote q,
    String Function(double) money,
  ) {
    String range(double? lo, double? hi) =>
        '${money(lo!)} – ${money(hi!)}';
    return [
      if (!coins && q.previousClose != null)
        (tr('widget.markets.previousClose', 'Previous close'), money(q.previousClose!), null),
      if (q.low != null && q.high != null)
        (coins ? tr('widget.markets.24hRange', '24h range') : tr('widget.markets.dayRange', 'Day range'), range(q.low, q.high), null),
      if (q.marketCap != null)
        (tr('widget.markets.marketCap', 'Market cap'), formatCompactPrice(q.marketCap!, q.currency), null),
      if (q.yearLow != null && q.yearHigh != null)
        (tr('widget.markets.52WeekRange', '52-week range'), range(q.yearLow, q.yearHigh), null),
      if (q.volume != null)
        (
          coins ? tr('widget.markets.volume24h', 'Volume (24h)') : tr('widget.markets.volume', 'Volume'),
          coins
              ? formatCompactPrice(q.volume!, q.currency)
              : formatCompact(q.volume!),
          null,
        ),
      if (q.allTimeHigh != null) (tr('widget.markets.allTimeHigh', 'All-time high'), money(q.allTimeHigh!), null),
    ];
  }
}

/// The card's chart: the price's path with its area shaded, the high and low
/// marked, times along the bottom, and yesterday's close as a dashed line.
class _Chart extends CustomPainter {
  _Chart({
    required this.values,
    required this.times,
    required this.colour,
    required this.theme,
    required this.baseline,
    required this.span,
    required this.label,
    this.scale = 1,
    this.paid,
    this.paidColour,
    this.bought,
  });

  /// The day it was bought, marked where it falls within the chart.
  final DateTime? bought;

  /// What was paid, drawn as a line across — or, when it is far outside
  /// the chart, as a note at the top or bottom edge, so a coin bought for a
  /// tenth of today's price doesn't flatten the chart to nothing.
  final double? paid;
  final Color? paidColour;

  /// How much bigger than its smallest the card is drawn.
  final double scale;

  final List<double> values;
  final List<DateTime> times;
  final Color colour;
  final DashboardTheme theme;
  final double? baseline;
  final String span;
  final String Function(double) label;

  String _when(DateTime t) => switch (span) {
    'day' =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    'week' => weekdayShort(t),
    // "Oct 25": a year's labels are months, and the year matters at its
    // start.
    'year' =>
      monthShortYear(t),
    _ => dayMonth(t),
  };

  TextPainter _text(String s, double size) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        color: theme.textSecondary,
        fontSize: size,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.reduce((a, b) => a > b ? a : b);
    final bottomValue = values.reduce((a, b) => a < b ? a : b);
    final hiText = _text(label(top), 10 * scale);
    final loText = _text(label(bottomValue), 10 * scale);
    // Widened to take in the baseline, so it is always on the chart.
    var lo = bottomValue, hi = top;
    final base = baseline;
    if (base != null) {
      if (base < lo) lo = base;
      if (base > hi) hi = base;
    }
    // Taken in when it is near enough not to squash the price's own path.
    final paid = this.paid;
    // Within a third of the price is near enough to be worth the squeeze —
    // it is the line people add a price paid to see — and so is anything
    // within most of the chart's own height of it.
    final now = values.last;
    final reach = (hi - lo == 0 ? hi.abs() * 0.02 : hi - lo) * 0.6;
    final paidOnChart =
        paid != null &&
        ((paid >= lo - reach && paid <= hi + reach) ||
            (paid - now).abs() <= now.abs() / 3);
    if (paidOnChart) {
      if (paid < lo) lo = paid;
      if (paid > hi) hi = paid;
    }
    final span = hi - lo == 0 ? 1.0 : hi - lo;

    // Room on the right for the high and low, and below for the times.
    final gutter =
        (hiText.width > loText.width ? hiText.width : loText.width) +
        8 * scale;
    final bottom = times.length == values.length ? 16.0 * scale : 0.0;
    final w = size.width - gutter;
    final h = size.height - bottom;
    if (w <= 10 || h <= 10) return;
    double y(double v) => h - (v - lo) / span * h;
    final dx = w / (values.length - 1);

    final grid = Paint()
      ..color = theme.textSecondary.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final v in [hi, lo]) {
      canvas.drawLine(Offset(0, y(v)), Offset(w, y(v)), grid);
    }

    if (base != null) {
      final dash = Paint()
        ..color = theme.textSecondary.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      for (var x = 0.0; x < w; x += 8) {
        canvas.drawLine(Offset(x, y(base)), Offset(x + 4, y(base)), dash);
      }
    }

    // Drawn last, over the price's line, so it can always be read.
    void Function()? paidNote;
    if (paid != null) {
      final c = paidColour ?? theme.accent;
      final chip = TextPainter(
        text: TextSpan(
          text: 'Paid ${label(paid)}'
              '${paidOnChart ? '' : (paid > hi ? ' · above the chart' : ' · below the chart')}',
          style: TextStyle(
            color: c,
            fontSize: 10 * scale,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double at;
      if (paidOnChart) {
        at = y(paid);
        canvas.drawLine(
          Offset(0, at),
          Offset(w, at),
          Paint()
            ..color = c
            ..strokeWidth = 1.5 * scale,
        );
      } else {
        at = paid > hi ? 0 : h;
      }
      // Above the line, or just inside the edge it is past.
      final pad = 3 * scale;
      final top = (at - chip.height - 2 * pad).clamp(
        0.0,
        h - chip.height - 2 * pad < 0 ? 0.0 : h - chip.height - 2 * pad,
      );
      paidNote = () {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              0,
              top,
              chip.width + 2 * pad + 2 * scale,
              chip.height + 2 * pad,
            ),
            Radius.circular(4 * scale),
          ),
          Paint()..color = theme.background.first.withValues(alpha: 0.85),
        );
        chip.paint(canvas, Offset(pad + scale, top + pad));
      };
    }

    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(i * dx, y(values[i]));
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colour.withValues(alpha: 0.28),
            colour.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..strokeJoin = StrokeJoin.round,
    );
    final last = Offset(w, y(values.last));
    canvas.drawCircle(last, 3.5 * scale, Paint()..color = colour);
    // When it was bought, if the chart goes back that far: a dashed upright
    // at the nearest point, with a note at its head — clear of the price
    // paid's, which sits at the left.
    final day = bought;
    if (day != null &&
        times.length == values.length &&
        !day.isBefore(times.first) &&
        !day.isAfter(times.last)) {
      var i = 0;
      while (i < times.length - 1 && times[i + 1].isBefore(day)) {
        i++;
      }
      final x = i * dx;
      final c = paidColour ?? theme.accent;
      final dash = Paint()
        ..color = c
        ..strokeWidth = 1.5 * scale;
      for (var y0 = 0.0; y0 < h; y0 += 8 * scale) {
        canvas.drawLine(Offset(x, y0), Offset(x, y0 + 4 * scale), dash);
      }
      final note = TextPainter(
        text: TextSpan(
          text: tr('widget.markets.bought', 'Bought'),
          style: TextStyle(
            color: c,
            fontSize: 10 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final pad = 3 * scale;
      final boxWidth = note.width + 2 * pad;
      // Centred on the upright, and kept inside the chart.
      final left = (x - boxWidth / 2).clamp(
        0.0,
        w - boxWidth < 0 ? 0.0 : w - boxWidth,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, boxWidth, note.height + 2 * pad),
          Radius.circular(4 * scale),
        ),
        Paint()..color = theme.background.first.withValues(alpha: 0.85),
      );
      note.paint(canvas, Offset(left + pad, pad));
    }

    // Last, so nothing is drawn across it.
    paidNote?.call();

    // Beside the price's own high and low, kept inside the chart.
    double labelY(double v, TextPainter p) =>
        (y(v) - p.height / 2).clamp(0.0, h - p.height < 0 ? 0.0 : h - p.height);
    final hiY = labelY(top, hiText), loY = labelY(bottomValue, loText);
    hiText.paint(canvas, Offset(w + 6 * scale, hiY));
    // Close together they would print over each other; the high will do.
    if (loY - hiY >= hiText.height) {
      loText.paint(canvas, Offset(w + 6 * scale, loY));
    }

    // Three times along the bottom, where there is room for three.
    if (bottom > 0 && w >= 150 * scale) {
      for (final i in {0, values.length ~/ 2, values.length - 1}) {
        final text = _text(_when(times[i]), 10 * scale);
        final x = (i * dx - text.width / 2).clamp(0.0, w - text.width);
        text.paint(canvas, Offset(x, h + 3 * scale));
      }
    }
  }

  @override
  bool shouldRepaint(_Chart old) =>
      old.values != values ||
      old.colour != colour ||
      old.baseline != baseline ||
      old.scale != scale ||
      old.paid != paid ||
      old.bought != bought ||
      old.theme != theme;
}

// ------------------------------------------------------------------ stocks

const _boughtField = WidgetOption(
  key: 'bought',
  label: 'Bought on',
  kind: OptionKind.date,
  defaultValue: '',
  help: 'Optional — marked on the chart when it goes back that far, and '
      'shown as how long you have held it.',
);

const _feesField = WidgetOption(
  key: 'fees',
  label: 'Fees paid',
  kind: OptionKind.number,
  defaultValue: '',
  help: 'Optional — dealing charges and the like, in pounds (or the tile’s '
      'currency), added to what it cost you.',
);

const _viewOption = WidgetOption(
  key: 'view',
  label: 'View',
  kind: OptionKind.choice,
  defaultValue: 'list',
  choices: {
    'list': 'A list — a line each',
    'cards': 'Cards — half the tile each, with a large chart and more figures',
    'single': 'One at a time — each card fills the tile',
  },
  help: 'Cards show two at a time, or one, and scroll for the rest; their '
      'text and charts grow with the tile, so a tile half the screen is '
      'readable across the room.',
);

const _defaultStocks = [
  {'symbol': '^FTSE', 'name': 'FTSE 100'},
  {'symbol': '^GSPC', 'name': 'S&P 500'},
  {'symbol': 'AAPL', 'name': ''},
];

class StocksWidget extends StatelessWidget {
  const StocksWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final picks = _picks(w, 'stocks', 'symbol', _defaultStocks);
    final range = w.option('chart', '1d');
    final maxAge = Duration(minutes: _refreshMinutes(w));
    return _MarketsTile(
      w: w,
      picks: picks,
      empty: tr('widget.markets.addTheSharesOrIndices', 'Add the shares or indices to follow in this widget’s settings.'),
      span: switch (range) {
        '5d' => 'week',
        '1mo' => 'month',
        '3mo' => 'quarter',
        '1y' => 'year',
        _ => 'day',
      },
      coins: false,
      fetch: (s, {force = false}) => s.ensureStocks(
        [for (final p in picks) p.entry],
        range: range,
        maxAge: maxAge,
        force: force,
      ),
      lookup: (s, entry) =>
          (quote: s.stock(entry, range), error: s.stockError(entry, range)),
    );
  }
}

final stocksWidgetType = DashboardWidgetType(
  type: 'stocks',
  category: WidgetCategory.reference,
  name: 'Stocks',
  description:
      'Share prices and indices, with today’s move and a small chart. From '
      'Yahoo Finance — no key needed. Prices can be 15 minutes behind.',
  glyph: '📈',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'stocks',
      label: 'Shares and indices',
      kind: OptionKind.list,
      addLabel: 'Add a share',
      help:
          'Yahoo Finance symbols: AAPL, MSFT; London shares end in .L '
          '(VOD.L, RPI.L); indices start with ^ (^FTSE, ^GSPC for the '
          'S&P 500, ^IXIC for the Nasdaq). A symbol without its exchange, '
          'or a company’s name, is looked up — the tile shows the symbol it '
          'found.',
      defaultValue: _defaultStocks,
      fields: [
        WidgetOption(key: 'symbol', label: 'Symbol', defaultValue: ''),
        WidgetOption(
          key: 'name',
          label: 'Name',
          defaultValue: '',
          help: 'Optional — the company’s own name is used otherwise.',
        ),
        WidgetOption(
          key: 'quantity',
          label: 'Shares owned',
          kind: OptionKind.number,
          defaultValue: '',
          help:
              'Optional — with it, the tile shows what your shares are worth '
              'and, given the price paid, what they have made or lost.',
        ),
        WidgetOption(
          key: 'paid',
          label: 'Price paid',
          defaultValue: '',
          help:
              'Optional — one share’s price when you bought it, drawn as a '
              'line on the chart. London shares are priced in pence; a plain '
              'number is read as pence or pounds, whichever is nearer '
              'today’s price, and 598p or £5.98 settles it.',
        ),
        _boughtField,
        _feesField,
      ],
    ),
    WidgetOption(
      key: 'chart',
      label: 'Chart covers',
      kind: OptionKind.choice,
      defaultValue: '1d',
      choices: {
        '1d': 'Daily — today',
        '5d': 'Weekly — the last five trading days',
        '1mo': 'Monthly — the last month',
        '3mo': 'Quarterly — the last three months',
        '1y': 'Yearly — the last twelve months',
      },
      help: 'The change beside each price is always today’s. Before the '
          'market opens, a daily chart shows the last day it was open.',
    ),
    _viewOption,
    WidgetOption(
      key: 'showChart',
      label: 'Show a small chart',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'In the list, on a tile wide enough to leave room for the '
          'price. Cards always have one.',
    ),
    WidgetOption(
      key: 'refreshMinutes',
      label: 'Check prices every',
      kind: OptionKind.choice,
      defaultValue: '5',
      choices: {
        '1': 'Minute',
        '5': '5 minutes',
        '15': '15 minutes',
        '60': 'Hour',
      },
    ),
  ],
  preview: const [
    PreviewLine('FTSE 100   10,695  +0.14%', scale: 0.12, px: 15),
    PreviewLine('S&P 500    6,512   −0.31%', scale: 0.12, px: 15),
    PreviewLine('Apple      \$241.20  +1.02%', scale: 0.12, px: 15),
  ],
  build: (context, w) => StocksWidget(w: w),
);

// ------------------------------------------------------------------ crypto

const _defaultCoins = [
  {'coin': 'bitcoin', 'name': ''},
  {'coin': 'ethereum', 'name': ''},
];

class CryptoWidget extends StatelessWidget {
  const CryptoWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final picks = _picks(w, 'coins', 'coin', _defaultCoins);
    final currency = w.option('currency', 'gbp');
    final period = w.option('period', '24h');
    // CoinGecko's free tier allows a few calls a minute; two a check is well
    // inside that even with a tile set to every minute.
    final maxAge = Duration(minutes: _refreshMinutes(w));
    return _MarketsTile(
      w: w,
      picks: picks,
      empty: tr('widget.markets.addTheCoinsToFollow', 'Add the coins to follow in this widget’s settings.'),
      span: switch (period) {
        '7d' => 'week',
        '30d' => 'month',
        '90d' => 'quarter',
        '1y' => 'year',
        _ => 'day',
      },
      coins: true,
      fetch: (s, {force = false}) => s.ensureCoins(
        [for (final p in picks) p.entry],
        currency: currency,
        period: period,
        maxAge: maxAge,
        force: force,
        apiKey: w.option<String>('apiKey', ''),
      ),
      lookup: (s, entry) => (
        quote: s.coin(entry, currency, period),
        error: s.coinError(entry, currency, period),
      ),
    );
  }
}

final cryptoWidgetType = DashboardWidgetType(
  type: 'crypto',
  category: WidgetCategory.reference,
  name: 'Crypto',
  description:
      'Coin prices with their move over the last day or week and a small '
      'chart. From CoinGecko — no key needed.',
  glyph: '🪙',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'coins',
      label: 'Coins',
      kind: OptionKind.list,
      addLabel: 'Add a coin',
      help:
          'A ticker symbol (BTC, ETH, SOL) or CoinGecko’s name for it — the '
          'last part of its coingecko.com address, such as bitcoin or '
          'ripple. The name is surer where two coins share a symbol.',
      defaultValue: _defaultCoins,
      fields: [
        WidgetOption(key: 'coin', label: 'Coin', defaultValue: ''),
        WidgetOption(
          key: 'name',
          label: 'Name',
          defaultValue: '',
          help: 'Optional — the coin’s own name is used otherwise.',
        ),
        WidgetOption(
          key: 'quantity',
          label: 'Coins owned',
          kind: OptionKind.number,
          defaultValue: '',
          help:
              'Optional — fractions are fine (0.05). With it, the tile shows '
              'what your coins are worth and, given the price paid, what '
              'they have made or lost.',
        ),
        WidgetOption(
          key: 'paid',
          label: 'Price paid',
          defaultValue: '',
          help:
              'Optional — one coin’s price when you bought it, in the '
              'currency the tile shows, drawn as a line on the chart with '
              'how far above or below it the price is now.',
        ),
        _boughtField,
        _feesField,
      ],
    ),
    WidgetOption(
      key: 'currency',
      label: 'Prices in',
      kind: OptionKind.choice,
      defaultValue: 'gbp',
      choices: {'gbp': 'Pounds (£)', 'usd': r'Dollars ($)', 'eur': 'Euros (€)'},
    ),
    WidgetOption(
      key: 'period',
      label: 'Change and chart over',
      kind: OptionKind.choice,
      defaultValue: '24h',
      choices: {
        '24h': 'Daily — the last 24 hours',
        '7d': 'Weekly — the last seven days',
        '30d': 'Monthly — the last 30 days',
        '90d': 'Quarterly — the last 90 days',
        '1y': 'Yearly — the last twelve months',
      },
      help: 'Monthly and longer charts are checked every half hour, '
          'whatever the setting below — they barely change between checks.',
    ),
    _viewOption,
    WidgetOption(
      key: 'showChart',
      label: 'Show a small chart',
      kind: OptionKind.boolean,
      defaultValue: true,
      help: 'In the list, on a tile wide enough to leave room for the '
          'price. Cards always have one.',
    ),
    WidgetOption(
      key: 'refreshMinutes',
      label: 'Check prices every',
      kind: OptionKind.choice,
      defaultValue: '5',
      choices: {
        '2': '2 minutes',
        '5': '5 minutes',
        '15': '15 minutes',
        '60': 'Hour',
      },
    ),
    WidgetOption(
      key: 'apiKey',
      label: 'CoinGecko API key',
      kind: OptionKind.secret,
      defaultValue: '',
      help: 'Optional, free, and recommended: without one, CoinGecko shares a '
          'small allowance between everyone at your address and often says '
          'it is busy. Sign up for a Demo key at coingecko.com/en/api.',
    ),
  ],
  preview: const [
    PreviewLine('Bitcoin    £62,844  −1.46%', scale: 0.12, px: 15),
    PreviewLine('Ethereum   £1,912   +0.52%', scale: 0.12, px: 15),
  ],
  build: (context, w) => CryptoWidget(w: w),
);
