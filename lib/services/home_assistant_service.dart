import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config_service.dart';
import '../l10n/l10n.dart';
import '../map_text.dart';
import 'http_client.dart';

/// One Home Assistant entity, as the widget shows it.
@immutable
class HaEntity {
  const HaEntity({
    required this.id,
    required this.state,
    this.attributes = const {},
  });

  final String id;
  final String state;
  final Map<String, dynamic> attributes;

  String get domain => id.split('.').first;
  String get name => '${attributes['friendly_name'] ?? id}';
  bool get unavailable => state == 'unavailable' || state == 'unknown';

  /// Things a tap can switch. Locks, alarms and covers are left out on
  /// purpose: a wall panel anyone walks past should not open the front door.
  bool get switchable =>
      const {'light', 'switch', 'fan', 'input_boolean'}.contains(domain);

  bool get on => state == 'on';

  /// The reading, in words, as Home Assistant's own cards would put it.
  String get display {
    if (unavailable) {
      return tr('widget.home_assistant.unavailable', 'Unavailable');
    }
    final a = attributes;
    switch (domain) {
      case 'sensor':
        final unit = '${a['unit_of_measurement'] ?? ''}';
        final n = double.tryParse(state);
        final value = n == null
            ? _title(state)
            : (n == n.roundToDouble() || n.abs() >= 100
                  ? n.round().toString()
                  : n.toStringAsFixed(1));
        return unit.isEmpty
            ? value
            : (unit == '%' ? '$value%' : '$value $unit');
      case 'binary_sensor':
        final on = state == 'on';
        return switch ('${a['device_class'] ?? ''}') {
          'door' || 'window' || 'opening' || 'garage_door' =>
            on
                ? tr('widget.home_assistant.open', 'Open')
                : tr('widget.home_assistant.closed', 'Closed'),
          'motion' || 'occupancy' || 'presence' =>
            on
                ? tr('widget.home_assistant.detected', 'Detected')
                : tr('widget.home_assistant.clear', 'Clear'),
          'moisture' =>
            on
                ? tr('widget.home_assistant.wet', 'Wet')
                : tr('widget.home_assistant.dry', 'Dry'),
          'battery' =>
            on
                ? tr('widget.home_assistant.low', 'Low')
                : tr('widget.home_assistant.ok', 'OK'),
          'connectivity' =>
            on
                ? tr('widget.home_assistant.connected', 'Connected')
                : tr('widget.home_assistant.disconnected', 'Disconnected'),
          'problem' =>
            on
                ? tr('widget.home_assistant.problem', 'Problem')
                : tr('widget.home_assistant.ok', 'OK'),
          _ =>
            on
                ? tr('widget.home_assistant.on', 'On')
                : tr('widget.home_assistant.off', 'Off'),
        };
      case 'person' || 'device_tracker':
        return state == 'home'
            ? tr('widget.home_assistant.home', 'Home')
            : state == 'not_home'
            ? tr('widget.home_assistant.away', 'Away')
            : _title(state);
      case 'media_player':
        final title = a.text('media_title');
        return state == 'playing' && title.isNotEmpty ? title : _title(state);
      case 'climate':
        final t = a['current_temperature'];
        return t == null ? _title(state) : '$t°';
      case 'weather':
        final t = a['temperature'];
        return t == null
            ? _title(state)
            : '${_title(state.replaceAll('-', ' '))} · $t°';
      case 'light':
        final b = a['brightness'];
        return state == 'on' && b is num
            ? '${(b / 255 * 100).round()}%'
            : _title(state);
    }
    return _title(state);
  }

  static String _title(String s) {
    final words = s.replaceAll('_', ' ');
    return words.isEmpty
        ? words
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static HaEntity? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['entity_id'] ?? ''}';
    if (!id.contains('.')) return null;
    return HaEntity(
      id: id,
      state: '${j['state'] ?? ''}',
      attributes:
          (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// One of Home Assistant's areas — a room, mostly — and what is in it.
@immutable
class HaArea {
  const HaArea({required this.id, required this.name, required this.entities});

  final String id;
  final String name;
  final List<String> entities;
}

/// Reads and switches Home Assistant entities for the dashboard, using the
/// connection set up in Settings for the indoor temperature.
class HomeAssistantService extends ChangeNotifier {
  HomeAssistantService(this._config, {Dio? dio})
    : _dio =
          dio ??
          httpClient(
            connect: const Duration(seconds: 5),
            receive: const Duration(seconds: 10),
          );

  final ConfigService _config;
  final Dio _dio;
  Map<String, HaEntity> _states = {};
  String? _error;
  DateTime? _fetched;
  Future<void>? _inFlight;

  String get _base => trimAddress(_config.config.homeAssistant.baseUrl);
  String get _token => _config.config.homeAssistant.token;
  bool get configured => _base.isNotEmpty && _token.isNotEmpty;

  HaEntity? entity(String id) => _states[id];
  String? get error => _error;
  Iterable<HaEntity> get all => _states.values;

  Options get _auth => Options(headers: {'Authorization': 'Bearer $_token'});

  /// Everything's state, in one request. Shared by every widget that asks
  /// within a few seconds of another.
  Future<void> refresh() {
    if (!configured) {
      _error = tr(
        'widget.home_assistant.setUpHomeAssistantIn',
        'Set up Home Assistant in Settings first',
      );
      notifyListeners();
      return Future.value();
    }
    if (_fetched != null &&
        DateTime.now().difference(_fetched!) < const Duration(seconds: 5)) {
      return Future.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    try {
      final r = await _dio.get('$_base/api/states', options: _auth);
      _states = {
        for (final e in (r.data as List? ?? const []))
          if (HaEntity.fromJson(e) case final HaEntity h) h.id: h,
      };
      _fetched = DateTime.now();
      _error = null;
    } on DioException catch (e) {
      _error = e.response?.statusCode == 401
          ? tr(
              'widget.home_assistant.homeAssistantDidNotAccept',
              'Home Assistant did not accept the token',
            )
          : tr(
              'widget.home_assistant.couldNotReachHomeAssistant',
              'Could not reach Home Assistant',
            );
    } catch (e) {
      _error = tr(
        'widget.home_assistant.unexpectedAnswerFromHomeAssistant',
        'Unexpected answer from Home Assistant',
      );
    }
    notifyListeners();
  }

  /// Switches [e], showing the change at once and putting it back if Home
  /// Assistant says no.
  Future<void> toggle(HaEntity e) async {
    if (!e.switchable) return;
    final flipped = HaEntity(
      id: e.id,
      state: e.on ? 'off' : 'on',
      attributes: e.attributes,
    );
    _states[e.id] = flipped;
    notifyListeners();
    try {
      await _dio.post(
        '$_base/api/services/${e.domain}/toggle',
        data: {'entity_id': e.id},
        options: _auth,
      );
      _fetched = null; // the next refresh reads the real state
    } catch (_) {
      _states[e.id] = e;
      _error = tr(
        'widget.home_assistant.homeAssistantDidNotTake',
        'Home Assistant did not take the change',
      );
      notifyListeners();
    }
  }

  /// Home Assistant's areas, each with the entities in it, as of the last
  /// [refreshAreas]. Entities hidden in Home Assistant are left out, so
  /// what it keeps off its own dashboards stays off this one too.
  List<HaArea> get areas => _areas;
  List<HaArea> _areas = const [];
  DateTime? _areasFetched;

  /// The areas are asked for with a template: the REST API has no other
  /// way to them. Changed rarely, so asked at most every five minutes.
  static const _areasTemplate =
      '{% set ns = namespace(out=[]) %}'
      '{% for a in areas() %}'
      '{% set ns.out = ns.out + [{"id": a, "name": area_name(a), '
      '"entities": area_entities(a) | reject("is_hidden_entity") | list}] %}'
      '{% endfor %}'
      '{{ ns.out | to_json }}';

  Future<void> refreshAreas() async {
    if (!configured) return;
    if (_areasFetched != null &&
        DateTime.now().difference(_areasFetched!) <
            const Duration(minutes: 5)) {
      return;
    }
    _areasFetched = DateTime.now();
    try {
      final r = await _dio.post(
        '$_base/api/template',
        data: {'template': _areasTemplate},
        options: _auth,
      );
      final list = r.data is String ? jsonDecode(r.data as String) : r.data;
      _areas = [
        for (final a in (list as List? ?? const []))
          if (a is Map)
            HaArea(
              id: '${a['id']}',
              name: '${a['name']}',
              entities: [
                for (final e in (a['entities'] as List? ?? const [])) '$e',
              ],
            ),
      ];
      notifyListeners();
    } catch (e) {
      _areasFetched = null; // asked again on the next refresh
      debugPrint('Home Assistant: areas: $e');
    }
  }

  /// The numeric states of [entityIds] since [start], oldest first, by
  /// entity — what Home Assistant's history graph is drawn from. Readings
  /// that are not numbers, "unavailable" among them, are left out. Empty
  /// when it could not be asked.
  Future<Map<String, List<(DateTime, double)>>> history(
    List<String> entityIds,
    DateTime start,
  ) async {
    if (!configured || entityIds.isEmpty) return const {};
    try {
      final r = await _dio.get(
        '$_base/api/history/period/${start.toUtc().toIso8601String()}',
        queryParameters: {
          'filter_entity_id': entityIds.join(','),
          // Without it, a day from [start] and no more.
          'end_time': DateTime.now().toUtc().toIso8601String(),
          'minimal_response': '',
          'no_attributes': '',
        },
        options: _auth,
      );
      final out = <String, List<(DateTime, double)>>{};
      for (final series in (r.data as List? ?? const [])) {
        if (series is! List || series.isEmpty) continue;
        final id = '${(series.first as Map)['entity_id']}';
        out[id] = [
          for (final s in series)
            if (s is Map)
              if (double.tryParse('${s['state']}') case final double v)
                if (DateTime.tryParse('${s['last_changed']}')
                    case final DateTime at)
                  (at.toLocal(), v),
        ];
      }
      return out;
    } catch (e) {
      debugPrint('Home Assistant: history: $e');
      return const {};
    }
  }

  /// Calls [domain].[service] on [entityIds] — "light.turn_off" on a room's
  /// lights — and reads the states again soon after.
  Future<void> callService(
    String domain,
    String service,
    List<String> entityIds,
  ) async {
    if (!configured || entityIds.isEmpty) return;
    try {
      await _dio.post(
        '$_base/api/services/$domain/$service',
        data: {'entity_id': entityIds},
        options: _auth,
      );
      _fetched = null;
      await refresh();
    } catch (_) {
      _error = tr(
        'widget.home_assistant.homeAssistantDidNotTake',
        'Home Assistant did not take the change',
      );
      notifyListeners();
    }
  }

  /// Calls [domain].[service] with [data] as it is — targets, a brightness,
  /// a colour — and says whether Home Assistant took it.
  Future<bool> service(
    String domain,
    String service,
    Map<String, Object?> data,
  ) async {
    if (!configured) return false;
    try {
      await _dio.post(
        '$_base/api/services/$domain/$service',
        data: data,
        options: _auth,
      );
      _fetched = null;
      unawaited(refresh());
      return true;
    } catch (e) {
      debugPrint('Home Assistant: $domain.$service: $e');
      return false;
    }
  }

  /// The lights that are on, but for [keep] — entity ids, and whole areas as
  /// "area:" and the area's id. Hidden ones are left out: they are parts of
  /// another light (a lamp's segments), or not lights to anyone (a network
  /// switch's LED). Null when it could not be asked.
  Future<List<String>?> lightsOnBesides(List<String> keep) async {
    if (!configured) return null;
    try {
      final r = await _dio.post(
        '$_base/api/template',
        data: {
          'template': _lightsOnBesides,
          'variables': {'keep': keep},
        },
        options: _auth,
      );
      final list = r.data is String ? jsonDecode(r.data as String) : r.data;
      return [for (final e in (list as List? ?? const [])) '$e'];
    } catch (e) {
      debugPrint('Home Assistant: lights on: $e');
      return null;
    }
  }

  static const _lightsOnBesides =
      '{% set ns = namespace(ids=[]) %}'
      '{% for t in keep %}'
      '{% if t.startswith("area:") %}'
      '{% set ns.ids = ns.ids + area_entities(t[5:]) %}'
      '{% else %}{% set ns.ids = ns.ids + [t] %}{% endif %}'
      '{% endfor %}'
      '{{ states.light | selectattr("state", "eq", "on") '
      '| map(attribute="entity_id") | reject("is_hidden_entity") '
      '| reject("in", ns.ids) | list | to_json }}';

  /// Everything in [domains] that is not hidden, by name, with its room —
  /// for choosing in Settings. Empty when it could not be asked.
  Future<List<HaChoice>> entityChoices(Set<String> domains) async {
    if (!configured) return const [];
    try {
      final r = await _dio.post(
        '$_base/api/template',
        data: {
          'template': _choicesTemplate,
          'variables': {'domains': domains.toList()},
        },
        options: _auth,
      );
      final list = r.data is String ? jsonDecode(r.data as String) : r.data;
      return [
        for (final c in (list as List? ?? const []))
          if (c is List && c.length >= 3)
            HaChoice(
              id: '${c[0]}',
              name: '${c[1]}',
              area: c[2] == null ? '' : '${c[2]}',
            ),
      ]..sort((a, b) {
        final byArea = a.area.compareTo(b.area);
        return byArea != 0 ? byArea : a.name.compareTo(b.name);
      });
    } catch (e) {
      debugPrint('Home Assistant: choices: $e');
      return const [];
    }
  }

  static const _choicesTemplate =
      '{% set ns = namespace(out=[]) %}'
      '{% for s in states if s.domain in domains '
      'and not is_hidden_entity(s.entity_id) %}'
      '{% set ns.out = ns.out + [[s.entity_id, s.name, '
      'area_name(s.entity_id)]] %}'
      '{% endfor %}'
      '{{ ns.out | to_json }}';

  /// Asks Home Assistant's Assist to do or answer [text] — "turn off the
  /// lamp", "what's the indoor temperature" — and gives back what it said.
  ///
  /// Null when it understood none of it, or could not be asked: the panel
  /// then says it did not understand, as it would have anyway. Anything
  /// else it says, "no weather is exposed" included, is an answer and shown
  /// as one: it is how you find out what Assist cannot yet reach.
  ///
  /// Assist runs in Home Assistant on the same Pi, so nothing said leaves
  /// it unless Home Assistant has been set up to send it somewhere.
  Future<String?> converse(String text, {String language = 'en'}) async =>
      (await ask(text, language: language))?.speech;

  /// [converse], saying besides whether Assist did what was asked — see
  /// [AssistReply.done]. "Not aware of any device called you one" is an
  /// answer, but not a doing: a hearing of the same words that names the
  /// light properly is worth asking before that is shown.
  Future<AssistReply?> ask(String text, {String language = 'en'}) async {
    if (!configured || text.trim().isEmpty) return null;
    try {
      final r = await _dio.post(
        '$_base/api/conversation/process',
        data: {'text': text, 'language': language},
        options: _auth,
      );
      final reply = (r.data as Map?)?['response'];
      if (reply is! Map) return null;
      final data = reply['data'];
      final failed = reply['response_type'] == 'error';
      if (failed && data is Map && data['code'] == 'no_intent_match') {
        return null;
      }
      // Something may have been switched: the next refresh reads it.
      _fetched = null;
      final speech = '${reply['speech']?['plain']?['speech'] ?? ''}'.trim();
      return AssistReply(
        speech.isEmpty ? tr('voice.done', 'Done') : speech,
        done: !failed,
      );
    } catch (e) {
      debugPrint('Home Assistant: Assist: $e');
      return null;
    }
  }

  /// The kinds of thing that are switched by name, out loud.
  static const _switchedByName = {
    'light', 'switch', 'fan', 'cover', 'media_player', 'climate', 'lock', //
    'scene', 'script', 'input_boolean', 'vacuum', 'humidifier',
  };

  /// What the devices that can be switched are called: for putting right
  /// a name misheard — see `SpokenNames`. As of the last [refresh]; the
  /// areas, the other names said, are [areas].
  List<String> get spokenNames => [
    for (final e in _states.values)
      if (_switchedByName.contains(e.domain)) e.name,
  ];

  /// For the editor's entity picker: id → "Friendly name (id)", grouped by
  /// kind, the plumbing left out.
  Future<Map<String, String>> choices() async {
    _fetched = null;
    await refresh();
    const skip = {
      'update',
      'button',
      'conversation',
      'stt',
      'tts',
      'event',
      'zone',
      'automation',
    };
    final list = _states.values.where((e) => !skip.contains(e.domain)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return {for (final e in list) e.id: '${e.name} (${e.id})'};
  }

  @visibleForTesting
  void debugSetAreas(List<HaArea> areas) {
    _areas = areas;
    _areasFetched = DateTime.now();
    notifyListeners();
  }

  @visibleForTesting
  void debugSet(List<HaEntity> entities) {
    _states = {for (final e in entities) e.id: e};
    _fetched = DateTime.now();
    notifyListeners();
  }
}

/// What Assist said to a request, and whether it did it: [done] is false
/// for an answer that says why not — no such device, nothing exposed.
/// Something in Home Assistant to choose: its id, name and room.
class HaChoice {
  const HaChoice({required this.id, required this.name, this.area = ''});
  final String id;
  final String name;
  final String area;
}

class AssistReply {
  const AssistReply(this.speech, {required this.done});
  final String speech;
  final bool done;
}
