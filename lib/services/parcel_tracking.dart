import 'package:dio/dio.dart';

import '../map_text.dart';
import 'http_client.dart';
import 'parcel_carriers.dart';

/// Where a parcel has got to, in the few steps that matter at home.
enum ParcelStage {
  /// Not looked up yet, or the carrier has nothing on it so far.
  waiting,

  /// The sender has made the label; the carrier does not have it yet.
  ordered,
  transit,
  out,

  /// At a shop, a locker or the depot, to be collected.
  pickup,

  /// They came and could not deliver it.
  failed,
  delivered,

  /// Held at customs, being sent back, lost: something to look into.
  problem;

  static ParcelStage byName(String? name) =>
      values.where((s) => s.name == name).firstOrNull ?? waiting;

  /// How far along the way: 0 to 3, delivered at the end.
  int get step => switch (this) {
    waiting => 0,
    ordered => 0,
    transit => 1,
    out || pickup || failed => 2,
    delivered => 3,
    problem => 1,
  };
}

/// One line of a parcel's story: "Out for delivery", at a time, somewhere.
class ParcelEvent {
  const ParcelEvent({required this.text, this.at, this.location});

  final String text;
  final DateTime? at;
  final String? location;

  Map<String, dynamic> toJson() => {
    'text': text,
    if (at != null) 'at': at!.toIso8601String(),
    if (location != null) 'location': location,
  };

  static ParcelEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = j.text('text');
    if (text.isEmpty) return null;
    final location = j.text('location');
    return ParcelEvent(
      text: text,
      at: DateTime.tryParse(j.text('at')),
      location: location.isEmpty ? null : location,
    );
  }
}

/// What a tracking service said about a parcel.
class ParcelUpdate {
  const ParcelUpdate({
    required this.stage,
    this.events = const [],
    this.expected,
    this.expectedTo,
    this.carrier,
    this.ready = true,
  });

  final ParcelStage stage;

  /// Newest first.
  final List<ParcelEvent> events;

  /// When it should arrive: a day, or the start of a window that ends at
  /// [expectedTo].
  final DateTime? expected;
  final DateTime? expectedTo;

  /// Who the service found is carrying it, where it says.
  final Carrier? carrier;

  /// False while the service is still fetching it for the first time: look
  /// again in a few minutes rather than in half an hour.
  final bool ready;
}

/// Why a parcel could not be looked up.
class TrackingError implements Exception {
  const TrackingError(this.message, {this.keyRefused = false});

  final String message;

  /// The service turned the key down: no parcel will be looked up until it
  /// is changed, so there is no point asking about the others.
  final bool keyRefused;

  @override
  String toString() => message;
}

/// Between checks, what a service needs remembering about a parcel: 17TRACK
/// whether it has been registered, Ship24 the tracker made for it.
typedef TrackerMemo = Map<String, dynamic>;

/// A tracking service that knows every carrier, asked with the household's
/// own key. The panel never scrapes a carrier's site: their tracking pages
/// are for people, and change under anyone reading them by machine.
abstract class ParcelTracker {
  /// Its id in a tile's settings.
  String get id;

  /// What it has on [number]. [memo] is this service's note about the
  /// parcel, changed in place for next time.
  Future<ParcelUpdate> check(
    String number, {
    required TrackerMemo memo,
    String? postcode,
  });

  /// The tracker for [service], or null for none.
  static ParcelTracker? forService(String service, String key, {Dio? dio}) {
    final k = key.trim();
    if (k.isEmpty) return null;
    return switch (service) {
      SeventeenTrack.serviceId => SeventeenTrack(k, dio: dio),
      Ship24.serviceId => Ship24(k, dio: dio),
      _ => null,
    };
  }
}

/// [17TRACK](https://api.17track.net)'s tracking API. A number is registered
/// once — that is what its quota counts — and then asked about for nothing.
class SeventeenTrack implements ParcelTracker {
  SeventeenTrack(this.key, {Dio? dio})
    : _dio =
          dio ??
          httpClient(
            baseUrl: base,
            receive: const Duration(seconds: 30),
            validateStatus: (_) => true,
          );

  static const serviceId = '17track';
  static const base = 'https://api.17track.net/track/v2.4';

  /// 17TRACK's own: already registered, and not registered.
  static const alreadyRegistered = -18019901;
  static const notRegistered = -18019902;

  final String key;
  final Dio _dio;

  @override
  String get id => serviceId;

  Future<Map> _post(String path, Object body) async {
    final r = await _dio.post<Object>(
      path.startsWith('http') ? path : '$base$path',
      data: body,
      options: Options(
        headers: {'17token': key, 'Content-Type': 'application/json'},
        validateStatus: (_) => true,
      ),
    );
    final status = r.statusCode ?? 0;
    final data = r.data;
    if (status == 401 || status == 403) {
      throw const TrackingError('17TRACK refused the key', keyRefused: true);
    }
    if (status == 429) {
      throw const TrackingError('17TRACK is busy; trying again soon');
    }
    if (data is! Map) {
      throw TrackingError('17TRACK answered $status');
    }
    final code = data['code'];
    if (code is num && code != 0) {
      final message = _firstError(data) ?? '17TRACK error $code';
      // Its codes for a key it does not know, or one switched off.
      final refused = RegExp(
        'token|key|auth',
        caseSensitive: false,
      ).hasMatch(message);
      throw TrackingError(message, keyRefused: refused);
    }
    final payload = data['data'];
    return payload is Map ? payload : const {};
  }

  static String? _firstError(Map data) {
    final errors = data['data'] is Map ? data['data']['errors'] : null;
    if (errors is List && errors.isNotEmpty && errors.first is Map) {
      return (errors.first as Map).text('message');
    }
    return null;
  }

  /// The error 17TRACK turned [number] away with, if it did.
  static ({int code, String message})? _rejected(Map data, String number) {
    final rejected = data['rejected'];
    if (rejected is! List) return null;
    for (final r in rejected) {
      if (r is! Map || r.text('number').toUpperCase() != number) continue;
      final e = r['error'];
      if (e is! Map) return (code: 0, message: '');
      return (
        code: (e['code'] as num?)?.toInt() ?? 0,
        message: e.text('message'),
      );
    }
    return null;
  }

  @override
  Future<ParcelUpdate> check(
    String number, {
    required TrackerMemo memo,
    String? postcode,
  }) async {
    if (memo['registered'] != true) {
      final reg = await _post('/register', [
        {'number': number},
      ]);
      final no = _rejected(reg, number);
      if (no != null && no.code != alreadyRegistered) {
        throw TrackingError(
          no.message.isEmpty ? '17TRACK would not take it' : no.message,
        );
      }
      memo['registered'] = true;
      // Fetched from the carrier in the next few minutes, not at once.
      if (no == null) {
        return const ParcelUpdate(stage: ParcelStage.waiting, ready: false);
      }
    }
    final info = await _post('/gettrackinfo', [
      {'number': number},
    ]);
    final no = _rejected(info, number);
    if (no != null) {
      if (no.code == notRegistered) {
        memo['registered'] = false;
        return const ParcelUpdate(stage: ParcelStage.waiting, ready: false);
      }
      throw TrackingError(
        no.message.isEmpty ? '17TRACK has nothing' : no.message,
      );
    }
    final accepted = info['accepted'];
    final item = accepted is List
        ? accepted
              .whereType<Map>()
              .where((a) => a.text('number').toUpperCase() == number)
              .firstOrNull
        : null;
    return parse(item);
  }

  /// One accepted entry of `gettrackinfo`.
  static ParcelUpdate parse(Map? item) {
    final info = item?['track_info'];
    if (info is! Map) {
      return const ParcelUpdate(stage: ParcelStage.waiting, ready: false);
    }
    final latest = info['latest_status'];
    final status = latest is Map ? latest.text('status') : '';
    final stage = switch (status) {
      'InfoReceived' => ParcelStage.ordered,
      'InTransit' => ParcelStage.transit,
      'OutForDelivery' => ParcelStage.out,
      'AvailableForPickup' => ParcelStage.pickup,
      'DeliveryFailure' => ParcelStage.failed,
      'Delivered' => ParcelStage.delivered,
      'Exception' || 'Expired' => ParcelStage.problem,
      _ => ParcelStage.waiting,
    };

    Carrier? carrier;
    final events = <ParcelEvent>[];
    final tracking = info['tracking'];
    final providers = tracking is Map ? tracking['providers'] : null;
    if (providers is List) {
      for (final p in providers.whereType<Map>()) {
        final provider = p['provider'];
        if (provider is Map) {
          carrier ??=
              Carrier.named(provider.text('name')) ??
              Carrier.named(provider.text('alias'));
        }
        final list = p['events'];
        if (list is! List) continue;
        for (final e in list.whereType<Map>()) {
          final event = _event(e);
          if (event != null) events.add(event);
        }
      }
    }
    if (events.isEmpty && info['latest_event'] is Map) {
      final event = _event(info['latest_event'] as Map);
      if (event != null) events.add(event);
    }
    _newestFirst(events);

    DateTime? from, to;
    final metrics = info['time_metrics'];
    final eta = metrics is Map ? metrics['estimated_delivery_date'] : null;
    if (eta is Map) {
      from = DateTime.tryParse(eta.text('from'))?.toLocal();
      to = DateTime.tryParse(eta.text('to'))?.toLocal();
    }
    return ParcelUpdate(
      stage: stage,
      events: events,
      expected: from ?? to,
      expectedTo: from == null ? null : to,
      carrier: carrier,
    );
  }

  static ParcelEvent? _event(Map e) {
    final text = e.text('description');
    if (text.isEmpty) return null;
    final at = DateTime.tryParse(
      e.text('time_iso').isEmpty ? e.text('time_utc') : e.text('time_iso'),
    )?.toLocal();
    final location = e['location'] is String ? e.text('location') : '';
    return ParcelEvent(
      text: text,
      at: at,
      location: location.isEmpty ? null : location,
    );
  }
}

/// [Ship24](https://docs.ship24.com)'s tracking API. A tracker is made for
/// a number once — that is what its plans count — and its results asked for
/// as often as is wanted.
class Ship24 implements ParcelTracker {
  Ship24(this.key, {Dio? dio})
    : _dio =
          dio ??
          httpClient(
            // Making a tracker waits for the carrier's first answer, which
            // can take most of a minute.
            receive: const Duration(seconds: 70),
            validateStatus: (_) => true,
          );

  static const serviceId = 'ship24';
  static const base = 'https://api.ship24.com/public/v1';

  final String key;
  final Dio _dio;

  @override
  String get id => serviceId;

  @override
  Future<ParcelUpdate> check(
    String number, {
    required TrackerMemo memo,
    String? postcode,
  }) async {
    final options = Options(
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json; charset=utf-8',
      },
      validateStatus: (_) => true,
    );
    final tracker = memo['tracker'];
    final Response<Object> r;
    if (tracker is String && tracker.isNotEmpty) {
      r = await _dio.get<Object>(
        '$base/trackers/${Uri.encodeComponent(tracker)}/results',
        options: options,
      );
    } else {
      final code = (postcode ?? '').replaceAll(' ', '').toUpperCase();
      r = await _dio.post<Object>(
        '$base/trackers/track',
        data: {
          'trackingNumber': number,
          if (code.isNotEmpty) 'destinationPostCode': code,
        },
        options: options,
      );
    }
    final status = r.statusCode ?? 0;
    final data = r.data;
    if (status == 401 || status == 403) {
      throw TrackingError(
        _message(data) ?? 'Ship24 refused the key',
        keyRefused: status == 401,
      );
    }
    if (status == 404 && tracker != null) {
      // Gone from the account: made again next time.
      memo.remove('tracker');
      return const ParcelUpdate(stage: ParcelStage.waiting, ready: false);
    }
    if (status == 429) {
      throw const TrackingError('Ship24 is busy; trying again soon');
    }
    if (status >= 400 || data is! Map) {
      throw TrackingError(_message(data) ?? 'Ship24 answered $status');
    }
    final payload = data['data'];
    final trackings = payload is Map ? payload['trackings'] : null;
    final first = trackings is List
        ? trackings.whereType<Map>().firstOrNull
        : null;
    final made = first?['tracker'];
    if (made is Map && made.text('trackerId').isNotEmpty) {
      memo['tracker'] = made.text('trackerId');
    }
    return parse(first);
  }

  static String? _message(Object? data) {
    if (data is! Map) return null;
    final errors = data['errors'];
    if (errors is List && errors.isNotEmpty && errors.first is Map) {
      final m = (errors.first as Map).text('message');
      if (m.isNotEmpty) return m;
    }
    return null;
  }

  /// One entry of `data.trackings`.
  static ParcelUpdate parse(Map? tracking) {
    if (tracking == null) {
      return const ParcelUpdate(stage: ParcelStage.waiting, ready: false);
    }
    final shipment = tracking['shipment'];
    final milestone = shipment is Map ? shipment.text('statusMilestone') : '';
    final stage = switch (milestone) {
      'info_received' => ParcelStage.ordered,
      'in_transit' => ParcelStage.transit,
      'out_for_delivery' => ParcelStage.out,
      'available_for_pickup' => ParcelStage.pickup,
      'failed_attempt' => ParcelStage.failed,
      'delivered' => ParcelStage.delivered,
      'exception' => ParcelStage.problem,
      _ => ParcelStage.waiting,
    };

    Carrier? carrier;
    final events = <ParcelEvent>[];
    final list = tracking['events'];
    if (list is List) {
      for (final e in list.whereType<Map>()) {
        final text = e.text('status');
        if (text.isEmpty) continue;
        carrier ??= Carrier.named(e.text('courierCode'));
        final location = e['location'] is String ? e.text('location') : '';
        events.add(
          ParcelEvent(
            text: text,
            // The carrier's local time, as Ship24 passes it on: here, that
            // is the panel's.
            at: DateTime.tryParse(e.text('occurrenceDatetime'))?.toLocal(),
            location: location.isEmpty ? null : location,
          ),
        );
      }
    }
    _newestFirst(events);
    if (carrier == null && tracking['tracker'] is Map) {
      final codes = (tracking['tracker'] as Map)['courierCode'];
      if (codes is List && codes.isNotEmpty) {
        carrier = Carrier.named('${codes.first}');
      }
    }

    final delivery = shipment is Map ? shipment['delivery'] : null;
    final eta = delivery is Map
        ? DateTime.tryParse(delivery.text('estimatedDeliveryDate'))?.toLocal()
        : null;
    return ParcelUpdate(
      stage: stage,
      events: events,
      expected: eta,
      carrier: carrier,
      ready:
          (milestone.isNotEmpty && milestone != 'pending') || events.isNotEmpty,
    );
  }
}

/// [events] newest first, when every one has a time to go by; otherwise in
/// the order the service gave, which is its own newest first.
void _newestFirst(List<ParcelEvent> events) {
  if (events.any((e) => e.at == null)) return;
  events.sort((a, b) => b.at!.compareTo(a.at!));
}
