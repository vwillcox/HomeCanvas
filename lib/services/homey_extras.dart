import '../l10n/l10n.dart';
import 'homey_service.dart';

/// What the rest of a Homey's API answers with, read into what the tiles
/// show. Each takes the JSON as it came — a map by id, mostly — and makes
/// nothing of what it cannot read.

Iterable<Map<dynamic, dynamic>> _items(Object? json) => switch (json) {
  final Map m => m.values.whereType<Map<dynamic, dynamic>>(),
  final List l => l.whereType<Map<dynamic, dynamic>>(),
  _ => const [],
};

/// Something wanting attention: a door open, a battery low, a device gone.
class HomeyAlert {
  const HomeyAlert(this.device, this.capability, this.text);

  final HomeyDevice device;

  /// What raised it, for the icon — empty for a device that is off line.
  final String capability;
  final String text;
}

/// Every alarm that is going, battery at or under [battery] per cent, and —
/// with [offline] — device Homey cannot reach. The worst first: alarms,
/// then what is off line, then batteries.
List<HomeyAlert> homeyAlerts(
  Iterable<HomeyDevice> devices, {
  int battery = 20,
  bool offline = true,
}) {
  final alarms = <HomeyAlert>[];
  final gone = <HomeyAlert>[];
  final low = <HomeyAlert>[];
  for (final d in devices) {
    if (!d.available) {
      if (offline) {
        gone.add(
          HomeyAlert(d, '', tr('widget.homey_alerts.offline', 'Off line')),
        );
      }
      continue;
    }
    for (final c in d.capabilities.values) {
      final what = c.id.split('.').first;
      if (what == 'measure_battery') {
        final v = c.value;
        if (v is num && v <= battery) {
          low.add(
            HomeyAlert(
              d,
              c.id,
              tr('widget.homey_alerts.battery', 'Battery {percent}%', {
                'percent': v.round(),
              }),
            ),
          );
        }
      } else if (what.startsWith('alarm_') && c.value == true) {
        // Its own word for it where it has one: "Open", "Detected", "Wet".
        (what == 'alarm_battery' ? low : alarms).add(
          HomeyAlert(
            d,
            c.id,
            what == 'alarm_battery'
                ? tr('widget.homey_alerts.batteryLow', 'Battery low')
                : switch (what) {
                    'alarm_smoke' => tr('widget.homey_alerts.smoke', 'Smoke'),
                    'alarm_co' => tr(
                      'widget.homey_alerts.co',
                      'Carbon monoxide',
                    ),
                    'alarm_heat' => tr('widget.homey_alerts.heat', 'Heat'),
                    'alarm_tamper' => tr(
                      'widget.homey_alerts.tamper',
                      'Tampered with',
                    ),
                    'alarm_connectivity' || 'alarm_online' => tr(
                      'widget.homey_alerts.offline',
                      'Off line',
                    ),
                    'alarm_motion' => tr(
                      'widget.homey_alerts.motion',
                      'Motion',
                    ),
                    _ => d.display(c.id),
                  },
          ),
        );
      }
    }
  }
  int byName(HomeyAlert a, HomeyAlert b) =>
      a.device.name.compareTo(b.device.name);
  return [...alarms..sort(byName), ...gone..sort(byName), ...low..sort(byName)];
}

/// Someone who lives here, as Homey knows them.
class HomeyPerson {
  const HomeyPerson({
    required this.name,
    required this.present,
    required this.asleep,
  });

  final String name;
  final bool present;
  final bool asleep;

  String get state => !present
      ? tr('widget.homey_presence.away', 'Away')
      : asleep
      ? tr('widget.homey_presence.asleep', 'Asleep')
      : tr('widget.homey_presence.home', 'Home');
}

/// From `users/user`: everyone whose account is switched on, by name.
List<HomeyPerson> homeyPeople(Object? json) => [
  for (final u in _items(json))
    if (u['enabled'] != false && u['name'] is String)
      HomeyPerson(
        // "Vincent Willcox" is Vincent, on a wall at home.
        name: (u['name'] as String).trim().split(' ').first,
        present: u['present'] == true,
        asleep: u['asleep'] == true,
      ),
]..sort((a, b) => a.name.compareTo(b.name));

/// One line of Homey's timeline.
class HomeyNote {
  const HomeyNote({required this.text, required this.from, this.at});

  final String text;
  final String from;
  final DateTime? at;
}

/// From `notifications/notification`: the newest first, the asterisks Homey
/// marks names with taken out.
List<HomeyNote> homeyTimeline(Object? json) => [
  for (final n in _items(json))
    if (n['excerpt'] is String)
      HomeyNote(
        text: (n['excerpt'] as String).replaceAll('**', '').trim(),
        from: '${n['ownerName'] ?? ''}',
        at: DateTime.tryParse('${n['dateCreated'] ?? ''}')?.toLocal(),
      ),
]..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));

/// From a log's `entry`: its readings in order, a switch's on and off as
/// one and nought, and the gaps where nothing was recorded left out.
List<({DateTime at, double value})> homeyEntries(Object? json) => [
  if (json is Map)
    for (final e in _items(json['values']))
      if (DateTime.tryParse('${e['t'] ?? ''}') case final DateTime at)
        if (switch (e['v']) {
              final num n => n.toDouble(),
              true => 1.0,
              false => 0.0,
              _ => null,
            }
            case final double value)
          (at: at.toLocal(), value: value),
];

/// Where the readings of the log [id] are asked for. A log's id is its
/// owner's — `homey:device:abc` — and then its own name.
String homeyLogPath(String id, String resolution) {
  final cut = id.lastIndexOf(':');
  final owner = cut < 0 ? id : id.substring(0, cut);
  return 'insights/log/${Uri.encodeComponent(owner)}/'
      '${Uri.encodeComponent(id)}/entry'
      '?resolution=${Uri.encodeQueryComponent(resolution)}';
}

/// "3 d 4 h", "5 h 12 min", "8 min".
String homeyUptime(num seconds) {
  final m = seconds ~/ 60;
  final d = m ~/ 1440, h = (m % 1440) ~/ 60, min = m % 60;
  return d > 0
      ? tr('widget.homey_system.daysHours', '{days} d {hours} h', {
          'days': d,
          'hours': h,
        })
      : h > 0
      ? tr('widget.homey_system.hoursMinutes', '{hours} h {minutes} min', {
          'hours': h,
          'minutes': min,
        })
      : tr('widget.homey_system.minutes', '{minutes} min', {'minutes': min});
}

/// How much of [total] is not [free], as "62%" — or a dash if unknown.
String homeyUsed(Object? total, Object? free) =>
    total is num && free is num && total > 0
    ? '${((total - free) / total * 100).round()}%'
    : '—';

/// A power reading: "850 W", "2.4 kW".
String homeyWatts(num w) =>
    w.abs() >= 1000 ? '${(w / 1000).toStringAsFixed(1)} kW' : '${w.round()} W';
