import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A container on a machine, and whether it is running.
@immutable
class ContainerState {
  const ContainerState(this.name, this.running);
  final String name;
  final bool running;
}

/// One machine's vital signs, as the Servers widget shows them.
@immutable
class MachineStats {
  const MachineStats({
    required this.name,
    this.cpu,
    this.memory,
    this.disk,
    this.temperature,
    this.uptime,
    this.containers,
    this.error,
  });

  final String name;

  /// Percentages, 0–100.
  final double? cpu;
  final double? memory;
  final double? disk;

  /// Degrees Celsius.
  final double? temperature;
  final Duration? uptime;

  /// Null when the machine's containers could not be read — not the same as
  /// having none.
  final List<ContainerState>? containers;

  /// Why nothing could be read, when nothing could.
  final String? error;

  bool get reachable => error == null;
  int get stopped => containers?.where((c) => !c.running).length ?? 0;
  int get running => containers?.where((c) => c.running).length ?? 0;
}

/// "11 d", "5 h", "40 min".
String shortUptime(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} d';
  if (d.inHours >= 1) return '${d.inHours} h';
  return '${d.inMinutes} min';
}

/// Reads the machine the kiosk runs on, straight from the kernel.
///
/// CPU use is the change between two readings of /proc/stat, so the first
/// call after construction reports none; the widget polls, and from the
/// second poll on it is the use over the interval between them.
class LocalStats {
  LocalStats({this.root = '/'});

  /// Where /proc and /sys are, so tests can point it at a fixture.
  final String root;

  (int, int)? _lastCpu;

  Future<MachineStats> read(String name) async {
    return MachineStats(
      name: name,
      cpu: await _cpu(),
      memory: await _memory(),
      disk: await _disk(),
      temperature: await _temperature(),
      uptime: await _uptime(),
      containers: await dockerContainers(),
    );
  }

  Future<String?> _read(String path) async {
    try {
      return await File('$root$path').readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<double?> _cpu() async {
    final text = await _read('proc/stat');
    final now = parseCpu(text);
    if (now == null) return null;
    final last = _lastCpu;
    _lastCpu = now;
    if (last == null) return null;
    final total = now.$1 - last.$1;
    final idle = now.$2 - last.$2;
    if (total <= 0) return null;
    return (100 * (total - idle) / total).clamp(0, 100).toDouble();
  }

  /// (total, idle) jiffies from the aggregate line of /proc/stat.
  static (int, int)? parseCpu(String? stat) {
    if (stat == null) return null;
    final line = stat
        .split('\n')
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return null;
    final n = line
        .split(RegExp(r'\s+'))
        .skip(1)
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (n.length < 5) return null;
    // idle + iowait: waiting on the disk is not the CPU being busy.
    return (n.reduce((a, b) => a + b), n[3] + n[4]);
  }

  Future<double?> _memory() async => parseMemory(await _read('proc/meminfo'));

  static double? parseMemory(String? meminfo) {
    if (meminfo == null) return null;
    int? field(String name) {
      final m = RegExp(
        '^$name:\\s+(\\d+)',
        multiLine: true,
      ).firstMatch(meminfo);
      return m == null ? null : int.parse(m[1]!);
    }

    final total = field('MemTotal');
    final available = field('MemAvailable');
    if (total == null || available == null || total == 0) return null;
    return 100 * (total - available) / total;
  }

  Future<double?> _temperature() async {
    final raw = await _read('sys/class/thermal/thermal_zone0/temp');
    final milli = int.tryParse(raw?.trim() ?? '');
    return milli == null ? null : milli / 1000;
  }

  Future<Duration?> _uptime() async {
    final raw = await _read('proc/uptime');
    final seconds = double.tryParse(raw?.split(' ').first ?? '');
    return seconds == null ? null : Duration(seconds: seconds.round());
  }

  Future<double?> _disk() async {
    try {
      final r = await Process.run('df', ['-P', '/']);
      return parseDf('${r.stdout}');
    } catch (_) {
      return null;
    }
  }

  static double? parseDf(String out) {
    final lines = out.trim().split('\n');
    if (lines.length < 2) return null;
    final m = RegExp(r'(\d+)%').firstMatch(lines.last);
    return m == null ? null : double.parse(m[1]!);
  }

  /// Every container Docker knows about here, running or not. Null when
  /// Docker is not installed or this user may not ask it.
  static Future<List<ContainerState>?> dockerContainers() async {
    try {
      final r = await Process.run('docker', [
        'ps',
        '-a',
        '--format',
        '{{.Names}}\t{{.State}}',
      ]);
      if (r.exitCode != 0) return null;
      return parseDocker('${r.stdout}');
    } catch (_) {
      return null;
    }
  }

  static List<ContainerState> parseDocker(String out) => [
    for (final line in const LineSplitter().convert(out))
      if (line.contains('\t'))
        ContainerState(
          line.split('\t').first.trim(),
          line.split('\t').last.trim() == 'running',
        ),
  ];
}

/// Reads another machine through Glances, the monitoring service.
///
/// Glances has a small web API and is one click to install from the CasaOS
/// app store, which is why it is the way in here rather than SSH or each
/// system's own API with its own login.
class GlancesClient {
  GlancesClient(this.baseUrl);

  final String baseUrl;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  String get _base {
    var b = baseUrl.trim();
    if (!b.startsWith('http')) b = 'http://$b';
    if (!RegExp(r':\d+$').hasMatch(Uri.parse(b).authority)) {
      b = '$b:61208'; // Glances' own port.
    }
    return b.replaceAll(RegExp(r'/+$'), '');
  }

  int? _version;

  Future<Object?> _get(String plugin) async {
    // Glances 4 answers on /api/4, older ones on /api/3. Learn which once.
    for (final v in _version == null ? [4, 3] : [_version!]) {
      try {
        final r = await _dio.get('$_base/api/$v/$plugin');
        _version = v;
        return r.data;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 && _version == null) continue;
        rethrow;
      }
    }
    return null;
  }

  /// Glances 4 calls them containers; Glances 3 — what apt installs on
  /// Debian and Ubuntu — calls the plugin docker and wraps the list.
  Future<Object?> _containers() async {
    try {
      if (_version == 3) {
        final d = await _get('docker');
        return d is Map ? d['containers'] : d;
      }
      return await _get('containers');
    } catch (_) {
      return null; // Glances not allowed to see Docker, or no Docker there.
    }
  }

  Future<MachineStats> read(String name) async {
    try {
      final quick = await _get('quicklook');
      final results = await Future.wait([
        _get('fs'),
        _get('sensors'),
        _get('uptime'),
        _containers(),
      ]);
      return fromGlances(
        name,
        quicklook: quick,
        fs: results[0],
        sensors: results[1],
        uptime: results[2],
        containers: results[3],
      );
    } catch (e) {
      return MachineStats(name: name, error: 'Not answering');
    }
  }

  @visibleForTesting
  static MachineStats fromGlances(
    String name, {
    Object? quicklook,
    Object? fs,
    Object? sensors,
    Object? uptime,
    Object? containers,
  }) {
    final q = quicklook is Map ? quicklook : const {};
    double? pct(Object? v) => v is num ? v.toDouble() : null;

    double? disk;
    if (fs is List) {
      // The root filesystem if there is one, otherwise the fullest.
      final entries = fs.whereType<Map>().toList();
      final root = entries.where((e) => e['mnt_point'] == '/');
      final pick = root.isNotEmpty
          ? root.first
          : (entries.isEmpty
                ? null
                : entries.reduce(
                    (a, b) =>
                        (pct(a['percent']) ?? 0) >= (pct(b['percent']) ?? 0)
                        ? a
                        : b,
                  ));
      disk = pick == null ? null : pct(pick['percent']);
    }

    double? temperature;
    if (sensors is List) {
      final temps = sensors
          .whereType<Map>()
          .where((s) => '${s['type']}'.startsWith('temperature'))
          .map((s) => pct(s['value']))
          .whereType<double>()
          .toList();
      if (temps.isNotEmpty) temperature = temps.reduce((a, b) => a > b ? a : b);
    }

    List<ContainerState>? list;
    if (containers is List) {
      list = [
        for (final c in containers.whereType<Map>())
          ContainerState(
            '${c['name'] ?? c['Names'] ?? ''}',
            '${c['status'] ?? c['Status'] ?? ''}'.toLowerCase().startsWith(
              RegExp('running|up|healthy'),
            ),
          ),
      ];
    }

    return MachineStats(
      name: name,
      cpu: pct(q['cpu']),
      memory: pct(q['mem']),
      disk: disk,
      temperature: temperature,
      uptime: uptime is String ? parseGlancesUptime(uptime) : null,
      containers: list,
    );
  }

  /// "10 days, 3:04:05" or "3:04:05".
  static Duration? parseGlancesUptime(String s) {
    final m = RegExp(r'(?:(\d+) days?,\s*)?(\d+):(\d+):(\d+)').firstMatch(s);
    if (m == null) return null;
    return Duration(
      days: int.parse(m[1] ?? '0'),
      hours: int.parse(m[2]!),
      minutes: int.parse(m[3]!),
      seconds: int.parse(m[4]!),
    );
  }
}
