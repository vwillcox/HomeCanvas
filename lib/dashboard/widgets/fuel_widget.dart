import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../services/fuel_service.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'fit_canvas.dart';
import 'tile_bits.dart';

/// What each fuel is called on the forecourt.
String _fuelName(String code) => switch (code) {
  'E5' => tr('widget.fuel.e5', 'Super unleaded (E5)'),
  'B7' => tr('widget.fuel.b7', 'Diesel (B7)'),
  'SDV' => tr('widget.fuel.sdv', 'Premium diesel'),
  _ => tr('widget.fuel.e10', 'Unleaded (E10)'),
};

/// The cheapest (or nearest) fuel near home, from the retailers' own
/// published prices.
class FuelWidget extends StatefulWidget {
  const FuelWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  @override
  State<FuelWidget> createState() => _FuelWidgetState();
}

class _FuelWidgetState extends State<FuelWidget>
    with PauseWhenHidden, ShownTimers {
  Timer? _timer;

  List<String> get _feeds => [
    ...kFuelFeeds,
    for (final r in widget.w.rows('extraFeeds'))
      if ('${r['url'] ?? ''}'.trim().isNotEmpty) '${r['url']}'.trim(),
  ];

  String get _postcode => widget.w.option('postcode', '').trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // The service only fetches a feed once it is an hour old.
    _timer = everyWhileShown(const Duration(minutes: 10), _refresh);
  }

  @override
  void didUpdateWidget(covariant FuelWidget old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(
      context.read<FuelService>().ensure(_feeds, postcode: _postcode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    final service = context.watch<FuelService>();
    final postcode = _postcode;
    final at = postcode.isNotEmpty ? service.place(postcode) : service.home;
    if (at == null) {
      return TileMessage(
        postcode.isNotEmpty
            ? (service.placeUnknown(postcode)
                  ? tr('widget.fuel.unknownPostcode',
                      '“{postcode}” isn’t a UK postcode', {'postcode': postcode})
                  : tr('widget.fuel.findingPostcode', 'Finding {postcode}…',
                      {'postcode': postcode}))
            : tr(
                'widget.fuel.needsPlace',
                'Set a place in Settings → Weather, or a postcode in the widget settings.',
              ),
        theme: t,
      );
    }
    final all = service.stations(_feeds);
    if (all == null) {
      return TileMessage(
        service.error ?? tr('widget.fuel.fetching', 'Fetching fuel prices…'),
        theme: t,
      );
    }

    final fuel = widget.w.option('fuel', 'E10');
    final radius = double.tryParse(widget.w.option('radius', '5')) ?? 5;
    final near = [
      for (final s in all)
        if (s.prices[fuel] != null)
          (station: s, miles: s.milesFrom(at.lat, at.lon), price: s.prices[fuel]!),
    ].where((e) => e.miles <= radius).toList();
    final byPrice = widget.w.option('sort', 'cheapest') == 'cheapest';
    near.sort(
      (a, b) => byPrice
          ? a.price.compareTo(b.price) != 0
                ? a.price.compareTo(b.price)
                : a.miles.compareTo(b.miles)
          : a.miles.compareTo(b.miles),
    );
    final cheapest = near.isEmpty
        ? null
        : near.map((e) => e.price).reduce((a, b) => a < b ? a : b);
    final max = widget.w.option('rows', 5).clamp(1, 12);
    final status = StatusColours.of(t);

    return LayoutBuilder(
      builder: (context, c) {
        final fit = ((c.maxHeight - 30) / 48).floor().clamp(1, max);
        final rows = near.take(fit).toList();
        return FitCanvas(
          designHeight: 26.0 + 42 * (rows.isEmpty ? 1 : rows.length),
          maxScale: (c.maxWidth / 300).clamp(1.0, 3.0),
          builder: (context, size) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileLabel(
                icon: Icons.local_gas_station_outlined,
                text: tr('widget.fuel.heading', '{fuel} · within {miles} miles', {
                  'fuel': _fuelName(fuel),
                  'miles': radius.round(),
                }),
                theme: t,
                size: 11,
              ),
              const SizedBox(height: 4),
              if (rows.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      tr('widget.fuel.noneNear',
                          'No stations publishing prices that close — try a wider distance.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                for (final e in rows)
                  Expanded(
                    child: _StationRow(
                      station: e.station,
                      miles: e.miles,
                      price: e.price,
                      best: e.price == cheapest,
                      theme: t,
                      status: status,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.miles,
    required this.price,
    required this.best,
    required this.theme,
    required this.status,
  });

  final FuelStation station;
  final double miles;
  final double price;

  /// The cheapest within the distance — shown in green.
  final bool best;
  final DashboardTheme theme;
  final StatusColours status;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return LayoutBuilder(
      builder: (context, c) {
        // The narrowest keeps who and how much.
        final narrow = c.maxWidth < 220;
        return Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.brand.isEmpty
                        ? station.postcode
                        : _titleCase(station.brand),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!narrow)
                    Text(
                      [
                        tr('widget.fuel.milesAway', '{miles} mi', {
                          'miles': miles < 10
                              ? miles.toStringAsFixed(1)
                              : miles.round(),
                        }),
                        station.address.isNotEmpty
                            ? station.address
                            : station.postcode,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textSecondary, fontSize: 10),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${price.toStringAsFixed(1)}p',
              style: TextStyle(
                color: best ? status.good : t.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Asda", "Esso" — some feeds write brands in capitals.
  static String _titleCase(String s) => s == s.toUpperCase() && s.length > 3
      ? s
            .toLowerCase()
            .split(' ')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ')
      : s;
}

final fuelWidgetType = DashboardWidgetType(
  type: 'fuel',
  category: WidgetCategory.gettingOut,
  name: 'Fuel prices',
  description:
      'The cheapest petrol or diesel near home, from the prices Asda, Shell, '
      'JET, Applegreen, Morrisons, Moto, MFG, Rontec and SGN publish under the '
      'UK’s open fuel price scheme — no key needed.',
  glyph: '⛽',
  defaultWidth: 3,
  defaultHeight: 3,
  minWidth: 2,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'fuel',
      label: 'Fuel',
      kind: OptionKind.choice,
      defaultValue: 'E10',
      choices: {
        'E10': 'Unleaded (E10)',
        'E5': 'Super unleaded (E5)',
        'B7': 'Diesel (B7)',
        'SDV': 'Premium diesel',
      },
    ),
    WidgetOption(
      key: 'radius',
      label: 'Within',
      kind: OptionKind.choice,
      defaultValue: '5',
      choices: {
        '2': '2 miles',
        '5': '5 miles',
        '10': '10 miles',
        '20': '20 miles',
      },
    ),
    WidgetOption(
      key: 'sort',
      label: 'Order',
      kind: OptionKind.choice,
      defaultValue: 'cheapest',
      choices: {'cheapest': 'Cheapest first', 'nearest': 'Nearest first'},
    ),
    WidgetOption(
      key: 'postcode',
      label: 'Near',
      defaultValue: '',
      help: 'Optional — a postcode, or just its first half (ME16). The place '
          'in Settings → Weather is used otherwise.',
    ),
    WidgetOption(
      key: 'rows',
      label: 'Stations to show',
      kind: OptionKind.number,
      defaultValue: 5,
    ),
    WidgetOption(
      key: 'extraFeeds',
      label: 'Extra price feeds',
      kind: OptionKind.list,
      addLabel: 'Add a feed',
      help: 'Optional. The address of a retailer’s fuel price JSON file, if '
          'one is missing or has moved. BP and Tesco turn automated requests '
          'away, so they can’t be shown.',
      fields: [
        WidgetOption(key: 'name', label: 'Retailer', defaultValue: ''),
        WidgetOption(key: 'url', label: 'Address', defaultValue: ''),
      ],
    ),
  ],
  preview: const [
    PreviewLine('Asda               138.9p', scale: .12, px: 15),
    PreviewLine('Jet                141.7p', scale: .12, px: 15),
    PreviewLine('Shell              145.9p', scale: .12, px: 15),
  ],
  build: (context, w) => FuelWidget(w: w),
);
