import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../map_text.dart';
import 'config_service.dart';
import 'parcel_carriers.dart';
import 'parcel_tracking.dart';
import 'parcel_when.dart';

export 'parcel_carriers.dart';
export 'parcel_tracking.dart' show ParcelStage, ParcelEvent;
export 'parcel_when.dart' show DeliveryWindow, findDeliveryWindow;

/// One parcel on its way to the house.
class Parcel {
  Parcel({
    required this.id,
    required this.carrier,
    required this.url,
    required this.added,
    this.number,
    this.label,
    this.from,
    this.stage = ParcelStage.waiting,
    this.events = const [],
    this.expected,
    this.expectedTo,
    this.dueSaid = false,
    this.toldDue,
    this.checkedAt,
    this.deliveredAt,
    this.error,
    this.trackedWith,
    TrackerMemo? memo,
  }) : memo = memo ?? {};

  final String id;
  Carrier carrier;
  final String? number;
  String url;
  final DateTime added;

  /// What it is, as the sender said: "Trainers".
  String? label;

  /// Who shared it.
  String? from;

  ParcelStage stage;

  /// Newest first.
  List<ParcelEvent> events;

  /// When it is due: the day, at the start of the window if there is one
  /// (midnight if not), and the window's end. See [DeliveryWindow].
  DateTime? expected;
  DateTime? expectedTo;

  /// Whether [expected] was said by a person — in what they shared, or on
  /// the panel — rather than found by a tracking service. Kept until the
  /// service knows a day of its own.
  bool dueSaid;

  /// The window last announced as opening, so it is announced once.
  String? toldDue;

  /// When a tracking service was last asked, and what it said was wrong.
  DateTime? checkedAt;
  String? error;

  /// When the panel learnt it had come, or was told so on it.
  DateTime? deliveredAt;

  /// The service [memo] is for; a change of service starts it afresh.
  String? trackedWith;
  TrackerMemo memo;

  String get key => number ?? url;
  bool get delivered => stage == ParcelStage.delivered;

  /// The newest thing the carrier said.
  ParcelEvent? get latest => events.firstOrNull;

  /// The last few of its number, enough to tell two apart: "…7890".
  String get numberTail {
    final n = number;
    if (n == null) return '';
    return n.length <= 6 ? n : '…${n.substring(n.length - 4)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'carrier': carrier.id,
    if (number != null) 'number': number,
    'url': url,
    'added': added.toUtc().toIso8601String(),
    if (label != null) 'label': label,
    if (from != null) 'from': from,
    'stage': stage.name,
    if (events.isNotEmpty) 'events': [for (final e in events) e.toJson()],
    if (expected != null) 'expected': expected!.toIso8601String(),
    if (expectedTo != null) 'expectedTo': expectedTo!.toIso8601String(),
    if (dueSaid) 'dueSaid': true,
    if (toldDue != null) 'toldDue': toldDue,
    if (checkedAt != null) 'checkedAt': checkedAt!.toUtc().toIso8601String(),
    if (deliveredAt != null)
      'deliveredAt': deliveredAt!.toUtc().toIso8601String(),
    if (error != null) 'error': error,
    if (trackedWith != null) 'trackedWith': trackedWith,
    if (memo.isNotEmpty) 'memo': memo,
  };

  static Parcel? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = j.text('url');
    final added = DateTime.tryParse(j.text('added'));
    if (url.isEmpty || added == null) return null;
    String? opt(String k) => j.text(k).isEmpty ? null : j.text(k);
    DateTime? at(String k) => DateTime.tryParse(j.text(k))?.toLocal();
    final events = j['events'];
    final memo = j['memo'];
    return Parcel(
      id: opt('id') ?? '${added.microsecondsSinceEpoch}',
      carrier: Carrier.byId(opt('carrier')),
      number: opt('number'),
      url: url,
      added: added.toLocal(),
      label: opt('label'),
      from: opt('from'),
      stage: ParcelStage.byName(opt('stage')),
      events: events is List
          ? [for (final e in events) ?ParcelEvent.fromJson(e)]
          : const [],
      expected: at('expected'),
      expectedTo: at('expectedTo'),
      dueSaid: j['dueSaid'] == true,
      toldDue: opt('toldDue'),
      checkedAt: at('checkedAt'),
      deliveredAt: at('deliveredAt'),
      error: opt('error'),
      trackedWith: opt('trackedWith'),
      memo: memo is Map ? memo.cast<String, dynamic>() : null,
    );
  }
}

/// How the Parcels tile has been set up in the editor.
class ParcelSettings {
  const ParcelSettings({
    this.service = 'none',
    this.key = '',
    this.postcode = '',
    this.keep = const Duration(days: 2),
    this.tell = true,
  });

  /// `none`, `17track` or `ship24`.
  final String service;
  final String key;
  final String postcode;

  /// How long a delivered parcel stays on the tile.
  final Duration keep;

  /// Whether a parcel out for delivery, delivered, or needing collecting
  /// pops up as a card.
  final bool tell;

  static ParcelSettings fromOptions(Map<String, dynamic> o) => ParcelSettings(
    service: o.text('service').isEmpty ? 'none' : o.text('service'),
    key: o.text('apiKey'),
    postcode: o.text('postcode'),
    keep: Duration(days: int.tryParse(o.text('keepDays')) ?? 2),
    tell: o['tell'] is bool ? o['tell'] as bool : true,
  );
}

/// The parcels the household is waiting for: shared from a phone — a
/// tracking link, or a number — kept across restarts, and looked up now and
/// then with the tracking service the Parcels tile is set to.
///
/// Without one, each is still a name, a carrier and the carrier's own
/// tracking page, a touch away on the panel.
class ParcelsService extends ChangeNotifier {
  ParcelsService(
    this._config, {
    String? file,
    DateTime Function()? clock,
    this.persist = true,
    ParcelTracker? Function(ParcelSettings settings)? tracker,
  }) : _file = File(file ?? defaultFile()),
       _clock = clock ?? DateTime.now,
       _trackerFor =
           tracker ?? ((s) => ParcelTracker.forService(s.service, s.key));

  static String defaultFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'homecanvas', 'parcels.json');
  }

  /// Null in tests, which give the settings themselves.
  final ConfigService? _config;
  final File _file;
  final DateTime Function() _clock;
  final ParcelTracker? Function(ParcelSettings) _trackerFor;

  /// Off keeps the parcels in memory only, for tests.
  final bool persist;

  /// Told when a parcel is out for delivery, delivered, waiting to be
  /// collected, or has a problem — once for each.
  void Function(Parcel parcel)? onNews;

  /// Told as a parcel's delivery window opens — or at eight, on a day with
  /// no window — so somebody knows to be in. Once for each window.
  void Function(Parcel parcel)? onDue;

  /// For tests: the settings, rather than those of the tile in [_config].
  @visibleForTesting
  ParcelSettings? settingsOverride;

  static const maxParcels = 40;

  /// How often an undelivered parcel is looked up. A tracking service
  /// gets news from the carrier every hour or two; asking more often finds
  /// nothing more.
  static const every = Duration(minutes: 30);

  /// How soon a parcel just registered is looked at again: the service
  /// fetches it from the carrier in the next minute or two.
  static const soon = Duration(minutes: 3);

  /// A parcel this old that never came is not looked up any more.
  static const giveUpAfter = Duration(days: 45);

  /// A parcel nothing has ever been heard of in this time — no tracking,
  /// no day still to come — is cleared away: a link that was never a
  /// parcel, or one nobody is following.
  static const forgetUnheardAfter = Duration(days: 14);

  List<Parcel> _parcels = [];
  int _seq = 0;
  Timer? _timer;
  int _ticks = 0;
  bool _checking = false;

  /// Asked for while a round was under way: another follows it, for
  /// [_wanted] — parcels asked about by name — and whatever else is due.
  bool _again = false;
  final Set<String> _wanted = {};
  bool _asked = false;

  /// What went wrong for every parcel at once: the key refused.
  String? serviceError;

  /// The key refused, and when: not offered again for a while unless it
  /// is changed, or a parcel is asked about on the panel.
  String? _refusedKey;
  DateTime? _refusedAt;
  static const _refusedWait = Duration(hours: 6);

  /// On its way first, soonest expected first; then those delivered.
  List<Parcel> get parcels {
    int rank(Parcel p) => switch (p.stage) {
      ParcelStage.out => 0,
      ParcelStage.pickup || ParcelStage.failed || ParcelStage.problem => 1,
      ParcelStage.delivered => 3,
      _ => 2,
    };
    final list = [..._parcels]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (a.delivered) {
          return (b.deliveredAt ?? b.added).compareTo(a.deliveredAt ?? a.added);
        }
        final x = a.expected, y = b.expected;
        if (x != null && y != null && x != y) return x.compareTo(y);
        if (x != null && y == null) return -1;
        if (x == null && y != null) return 1;
        return a.added.compareTo(b.added);
      });
    return List.unmodifiable(list);
  }

  /// Parcels still to come.
  int get coming => _parcels.where((p) => !p.delivered).length;

  Parcel? byId(String id) => _parcels.where((p) => p.id == id).firstOrNull;

  /// The parcel [ref] is, if it is on the list.
  Parcel? find(ParcelRef ref) =>
      _parcels.where((p) => p.key == ref.key).firstOrNull;

  ParcelSettings get settings {
    final given = settingsOverride;
    if (given != null) return given;
    final dashboard = _config?.config.dashboard;
    if (dashboard == null) return const ParcelSettings();
    final tile = dashboard.widgets
        .where((w) => w.type == 'parcels')
        .firstOrNull;
    return tile == null
        ? const ParcelSettings()
        : ParcelSettings.fromOptions(tile.options);
  }

  /// Whether parcels are being looked up at all.
  bool get tracking => _trackerFor(settings) != null;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final data = jsonDecode(await _file.readAsString());
        if (data is List) {
          _parcels = [for (final j in data) ?Parcel.fromJson(j)];
        }
      }
    } catch (e) {
      debugPrint('Parcels: could not read ${_file.path}: $e');
    }
    _prune();
    notifyListeners();
  }

  /// Looks parcels up every few minutes from now on, as each falls due.
  void start() {
    _timer?.cancel();
    // Every minute for a window opening; every five for the rest.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      announceDue();
      if (++_ticks % 5 != 0) return;
      if (_prune()) {
        notifyListeners();
        unawaited(_save());
      }
      unawaited(checkDue());
    });
    announceDue();
    unawaited(checkDue());
  }

  /// When [p]'s coming is worth saying: as its window opens, or at eight on
  /// a day with no time to it. Null without a day.
  static DateTime? dueFrom(Parcel p) {
    final from = p.expected;
    if (from == null) return null;
    final timed = from.hour != 0 || from.minute != 0;
    return timed ? from : DateTime(from.year, from.month, from.day, 8);
  }

  /// When there is no more point saying so: the window's end, or the day's.
  static DateTime? dueUntil(Parcel p) {
    final from = p.expected;
    if (from == null) return null;
    return p.expectedTo ?? DateTime(from.year, from.month, from.day + 1);
  }

  static String _dueKey(Parcel p) =>
      '${p.expected?.toIso8601String()}~${p.expectedTo?.toIso8601String()}';

  /// Says, once, that a parcel is due now, if its window has opened.
  @visibleForTesting
  void announceDue() {
    final now = _clock();
    var changed = false;
    for (final p in _parcels) {
      final from = dueFrom(p);
      if (p.delivered || from == null || now.isBefore(from)) continue;
      final key = _dueKey(p);
      if (p.toldDue == key) continue;
      p.toldDue = key;
      changed = true;
      if (now.isBefore(dueUntil(p)!)) onDue?.call(p);
    }
    if (changed) unawaited(_save());
  }

  /// Sets when [p] is due, as somebody said. A window already open as it
  /// is said needs no announcing: whoever said it knows.
  void _sayDue(Parcel p, DeliveryWindow? due) {
    p.expected = due?.from;
    p.expectedTo = due?.to;
    p.dueSaid = due != null;
    final from = dueFrom(p);
    p.toldDue = from != null && !_clock().isBefore(from) ? _dueKey(p) : null;
  }

  /// When parcel [id] is coming, as read off its carrier's page — or null,
  /// for not known.
  void setDue(String id, DeliveryWindow? due) {
    final parcel = byId(id);
    if (parcel == null) return;
    _sayDue(parcel, due);
    notifyListeners();
    unawaited(_save());
  }

  /// Puts [ref] on the list — or, already on it, brings it back to the top
  /// with [label] if one is given — and looks it up.
  Parcel add(
    ParcelRef ref, {
    String? label,
    String? from,
    DeliveryWindow? due,
  }) {
    final name = _tidy(label);
    var parcel = find(ref);
    if (parcel != null) {
      if (name != null) parcel.label = name;
      if (due != null) _sayDue(parcel, due);
      // The carrier's own link to it beats a search for its number: DPD's
      // carries a code its search would ask for.
      if (ref.linked && ref.carrier == parcel.carrier) parcel.url = ref.url;
    } else {
      parcel = Parcel(
        id: '${_clock().microsecondsSinceEpoch}-${++_seq}',
        carrier: ref.carrier,
        number: ref.number,
        url: ref.url,
        added: _clock(),
        label: name,
        from: _tidy(from),
      );
      if (due != null) _sayDue(parcel, due);
      _parcels.add(parcel);
    }
    _prune();
    notifyListeners();
    unawaited(_save());
    if (!parcel.delivered) unawaited(checkDue(only: parcel.id));
    return parcel;
  }

  static String? _tidy(String? s) {
    final t = (s ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return null;
    return t.length > 60 ? t.substring(0, 60) : t;
  }

  bool remove(String id) {
    final before = _parcels.length;
    _parcels.removeWhere((p) => p.id == id);
    if (_parcels.length == before) return false;
    notifyListeners();
    unawaited(_save());
    return true;
  }

  /// Said on the panel to have come — for a parcel nobody is tracking — or
  /// taken back.
  void setDelivered(String id, bool delivered) {
    final parcel = byId(id);
    if (parcel == null) return;
    if (delivered) {
      parcel.stage = ParcelStage.delivered;
      parcel.deliveredAt = _clock();
    } else {
      parcel.stage = ParcelStage.waiting;
      parcel.deliveredAt = null;
      parcel.checkedAt = null;
    }
    notifyListeners();
    unawaited(_save());
    if (!delivered) unawaited(checkDue(only: id));
  }

  /// Looks up every parcel due a look — or [only] the one, due or not.
  /// [asked] is someone on the panel wanting to know now.
  Future<void> checkDue({String? only, bool asked = false}) async {
    if (only != null) _wanted.add(only);
    if (asked) _asked = true;
    if (_checking) {
      // Looked up in a round straight after this one.
      _again = true;
      return;
    }
    final settings = this.settings;
    final tracker = _trackerFor(settings);
    if (tracker == null) {
      _wanted.clear();
      if (serviceError != null) {
        serviceError = null;
        notifyListeners();
      }
      return;
    }
    final wanted = {..._wanted};
    final askedNow = _asked;
    _wanted.clear();
    _asked = false;
    final refusedAt = _refusedAt;
    if (!askedNow &&
        refusedAt != null &&
        _refusedKey == settings.key &&
        _clock().difference(refusedAt) < _refusedWait) {
      return;
    }
    _checking = true;
    var changed = false;
    try {
      final now = _clock();
      final due = [
        for (final p in _parcels)
          if (p.number != null &&
              !p.delivered &&
              ((only == null && _isDue(p, now)) || wanted.contains(p.id)))
            p,
      ];
      for (final parcel in due) {
        if (!_parcels.contains(parcel)) continue;
        try {
          await _check(parcel, tracker, settings);
          serviceError = null;
          _refusedKey = _refusedAt = null;
        } on TrackingError catch (e) {
          parcel.error = e.message;
          parcel.checkedAt = _clock();
          if (e.keyRefused) {
            serviceError = e.message;
            _refusedKey = settings.key;
            _refusedAt = _clock();
            changed = true;
            break;
          }
        } on Exception catch (e) {
          // The network, most likely: tried again next round.
          debugPrint('Parcels: ${parcel.number}: $e');
          parcel.checkedAt = _clock();
        }
        changed = true;
        // 17TRACK takes three a second; a tracker is no hurry.
        if (due.length > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      _checking = false;
    }
    if (changed) {
      _prune();
      notifyListeners();
      unawaited(_save());
    }
    if (_again) {
      _again = false;
      await checkDue();
    }
  }

  bool _isDue(Parcel p, DateTime now) {
    if (now.difference(p.added) > giveUpAfter) return false;
    final last = p.checkedAt;
    if (last == null) return true;
    // Not yet fetched from the carrier, or just switched to a service.
    final wait = p.memo['ready'] == false ? soon : every;
    return now.difference(last) >= wait;
  }

  Future<void> _check(
    Parcel parcel,
    ParcelTracker tracker,
    ParcelSettings settings,
  ) async {
    if (parcel.trackedWith != tracker.id) {
      parcel.memo = {};
      parcel.trackedWith = tracker.id;
    }
    final before = parcel.stage;
    final seen = parcel.checkedAt != null && parcel.error == null;
    final update = await tracker.check(
      parcel.number!,
      memo: parcel.memo,
      postcode: settings.postcode,
    );
    parcel.checkedAt = _clock();
    parcel.error = null;
    parcel.memo['ready'] = update.ready;
    if (!update.ready && update.events.isEmpty) return;
    parcel.stage = update.stage;
    if (update.events.isNotEmpty) {
      parcel.events = update.events.take(30).toList();
    }
    // A day the service knows beats one somebody said; no day from it
    // leaves theirs be.
    if (update.expected != null || !parcel.dueSaid) {
      parcel.expected = update.expected;
      parcel.expectedTo = update.expectedTo;
      parcel.dueSaid = false;
    }
    final named = update.carrier;
    if (named != null && parcel.carrier == Carrier.unknown) {
      parcel.carrier = named;
    }
    if (parcel.delivered) {
      parcel.deliveredAt ??= parcel.latest?.at ?? _clock();
    }
    // News, once, of a change seen happening: a parcel shared after it
    // came is no surprise to whoever shared it.
    if (seen && parcel.stage != before && _newsworthy(parcel.stage)) {
      onNews?.call(parcel);
    }
  }

  static bool _newsworthy(ParcelStage s) =>
      s == ParcelStage.out ||
      s == ParcelStage.delivered ||
      s == ParcelStage.pickup ||
      s == ParcelStage.failed ||
      s == ParcelStage.problem;

  /// Clears delivered parcels away once they have been on show long enough,
  /// and those never heard of after [forgetUnheardAfter].
  bool _prune() {
    final before = _parcels.length;
    final keep = settings.keep;
    final now = _clock();
    _parcels.removeWhere(
      (p) => p.delivered && now.difference(p.deliveredAt ?? p.added) > keep,
    );
    _parcels.removeWhere((p) {
      if (p.stage != ParcelStage.waiting || p.events.isNotEmpty) return false;
      if (now.difference(p.added) <= forgetUnheardAfter) return false;
      final until = dueUntil(p);
      return until == null || until.isBefore(now);
    });
    if (_parcels.length > maxParcels) {
      // The oldest delivered go first, then the oldest of all.
      final byAge = [..._parcels]
        ..sort((a, b) {
          if (a.delivered != b.delivered) return a.delivered ? -1 : 1;
          return a.added.compareTo(b.added);
        });
      final drop = byAge.take(_parcels.length - maxParcels).toSet();
      _parcels.removeWhere(drop.contains);
    }
    return _parcels.length != before;
  }

  Future<void> _saving = Future.value();

  /// Resolves once everything asked for so far is on disk.
  Future<void> get saved => _saving;

  Future<void> _save() =>
      persist ? _saving = _saving.then((_) => _write()) : _saving;

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode([for (final p in _parcels) p.toJson()]),
      );
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Parcels: could not save: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
