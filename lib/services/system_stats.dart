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

/// What SMART says about a drive, boiled down to whether to worry.
enum DiskState { healthy, warning, failing }

/// A drive's health, from its SMART attributes.
@immutable
class DiskHealth {
  const DiskHealth({
    required this.device,
    required this.model,
    required this.state,
    this.temperature,
    this.powerOnHours,
    this.reallocated = 0,
    this.pending = 0,
    this.uncorrectable = 0,
  });

  /// "sda", matched against the filesystems to put health beside usage.
  final String device;
  final String model;
  final DiskState state;
  final double? temperature;
  final int? powerOnHours;
  final int reallocated;
  final int pending;
  final int uncorrectable;

  /// Why it is not healthy, in a few words; empty when it is.
  String get concern => [
    if (state == DiskState.failing) 'failing',
    if (reallocated > 0) '$reallocated reallocated',
    if (pending > 0) '$pending pending',
    if (uncorrectable > 0) '$uncorrectable unreadable',
  ].join(' · ');

  /// Glances' SMART plugin, one entry per drive: `DeviceName` ("sda ST8000…")
  /// and each attribute under its number, as smartctl reports it.
  ///
  /// SMART has no single verdict here, so one is worked out the way the
  /// disk tools do: failing when an attribute has crossed its threshold or
  /// has failed before; a warning when sectors have been remapped, are
  /// waiting to be, or could not be read — the early signs of a dying disk.
  static List<DiskHealth> fromGlances(Object? smart) {
    if (smart is! List) return const [];
    final out = <DiskHealth>[];
    for (final d in smart.whereType<Map>()) {
      final name = '${d['DeviceName'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final space = name.indexOf(' ');
      final device = baseDevice(space < 0 ? name : name.substring(0, space));
      final model = space < 0 ? '' : name.substring(space + 1).trim();
      final attrs = d.values.whereType<Map>().toList();

      Map? byName(List<String> names) {
        for (final a in attrs) {
          if (names.contains('${a['name']}')) return a;
        }
        return null;
      }

      int? raw(List<String> names) {
        final a = byName(names);
        if (a == null) return null;
        // "34 (Min/Max 20/45)", "12345h+06m" — the first number is the one.
        final m = RegExp(r'\d+').firstMatch('${a['raw']}');
        return m == null ? null : int.parse(m[0]!);
      }

      var failing = false;
      for (final a in attrs) {
        final failed = '${a['when_failed'] ?? ''}'.trim();
        final value = a['value'], threshold = a['threshold'];
        final v = value is num ? value : num.tryParse('$value');
        final t = threshold is num ? threshold : num.tryParse('$threshold');
        if ((failed.isNotEmpty && failed != '-' && failed != 'null') ||
            (v != null && t != null && t > 0 && v <= t)) {
          failing = true;
        }
      }
      final reallocated = raw(['Reallocated_Sector_Ct']) ?? 0;
      final pending = raw(['Current_Pending_Sector']) ?? 0;
      final uncorrectable = raw(['Offline_Uncorrectable']) ?? 0;
      out.add(
        DiskHealth(
          device: device,
          model: model,
          state: failing
              ? DiskState.failing
              : (reallocated + pending + uncorrectable > 0
                    ? DiskState.warning
                    : DiskState.healthy),
          temperature: raw([
            'Temperature_Celsius',
            'Airflow_Temperature_Cel',
          ])?.toDouble(),
          powerOnHours: raw(['Power_On_Hours']),
          reallocated: reallocated,
          pending: pending,
          uncorrectable: uncorrectable,
        ),
      );
    }
    return out;
  }
}

/// One filesystem worth showing: how full, how big, and the drive's health
/// when SMART is available for it.
@immutable
class DiskUse {
  const DiskUse({
    required this.label,
    required this.mount,
    required this.device,
    required this.percent,
    required this.size,
    required this.used,
    this.health,
  });

  /// "System" for the root, otherwise the mount's own name — "sata".
  final String label;
  final String mount;

  /// The drive it is on, "sda".
  final String device;
  final double percent;
  final int size;
  final int used;
  final DiskHealth? health;

  DiskUse withHealth(DiskHealth? h) => DiskUse(
    label: label,
    mount: mount,
    device: device,
    percent: percent,
    size: size,
    used: used,
    health: h,
  );

  static const _skipTypes = {
    'tmpfs',
    'devtmpfs',
    'squashfs',
    'overlay',
    'vfat',
    'efivarfs',
    'ramfs',
    'nsfs',
    'autofs',
  };
  static const _skipMounts = [
    '/boot',
    '/snap',
    '/run',
    '/var/lib/docker',
    '/dev',
    '/sys',
    '/proc',
  ];

  /// Whether a filesystem is somewhere data lives, rather than the system's
  /// plumbing — boot partitions, snaps, Docker's layers, memory disks — or
  /// too small to matter.
  static bool worthShowing(String type, String mount, int size) =>
      !_skipTypes.contains(type) &&
      !_skipMounts.any((m) => mount == m || mount.startsWith('$m/')) &&
      size >= 2 * 1000 * 1000 * 1000;

  static String labelFor(String mount) {
    if (mount == '/') return 'System';
    final parts = mount.split('/').where((p) => p.isNotEmpty);
    return parts.isEmpty ? mount : parts.last;
  }

  /// The root first, then the rest largest first; one entry per device, so
  /// a bind mount is not shown twice.
  static List<DiskUse> tidy(List<DiskUse> all) {
    // The same device and size is the same filesystem mounted twice.
    final byDevice = <String, DiskUse>{};
    for (final d in all) {
      final key = '${d.device}:${d.size}';
      final seen = byDevice[key];
      if (seen == null || d.mount.length < seen.mount.length) {
        byDevice[key] = d;
      }
    }
    return byDevice.values.toList()..sort(
      (a, b) => a.mount == '/'
          ? -1
          : b.mount == '/'
          ? 1
          : b.size.compareTo(a.size),
    );
  }
}

/// "sda" from "/dev/sda2", "nvme0n1" from "/dev/nvme0n1p2", "mmcblk0" from
/// "/dev/mmcblk0p2".
String baseDevice(String path) {
  final name = path.split('/').last;
  final nvme = RegExp(r'^(nvme\d+n\d+|mmcblk\d+)(p\d+)?$').firstMatch(name);
  if (nvme != null) return nvme[1]!;
  return name.replaceFirst(RegExp(r'\d+$'), '');
}

/// "8 TB", "512 GB", in the drive makers' thousands.
String shortSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  // One decimal below ten, and none when it is .0: "6.6 TB", "8 TB".
  final n = v >= 10 ? '${v.round()}' : v.toStringAsFixed(1);
  return '${n.endsWith('.0') ? n.substring(0, n.length - 2) : n} ${units[i]}';
}

/// "6.6 of 8 TB" — the unit once when both share it, "420 GB of 1 TB" when
/// they do not.
String sizeOf(int used, int size) {
  final u = shortSize(used), s = shortSize(size);
  final uUnit = u.split(' ').last, sUnit = s.split(' ').last;
  return uUnit == sUnit ? '${u.split(' ').first} of $s' : '$u of $s';
}

/// One machine's vital signs, as the Servers widget shows them.
@immutable
class MachineStats {
  const MachineStats({
    required this.name,
    this.cpu,
    this.memory,
    this.disk,
    this.disks = const [],
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

  /// Every filesystem worth showing, the root first.
  final List<DiskUse> disks;

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

  /// The worst any drive's SMART says, if any say anything.
  DiskState? get worstDisk {
    DiskState? worst;
    for (final d in disks) {
      final s = d.health?.state;
      if (s != null && (worst == null || s.index > worst.index)) worst = s;
    }
    return worst;
  }
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
    final disks = await _disks();
    final root = disks.where((d) => d.mount == '/');
    return MachineStats(
      name: name,
      cpu: await _cpu(),
      memory: await _memory(),
      disk: root.isEmpty ? await _disk() : root.first.percent,
      disks: disks,
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

  Future<List<DiskUse>> _disks() async {
    try {
      final r = await Process.run('df', ['-P', '-T', '-B1']);
      return parseDfAll('${r.stdout}');
    } catch (_) {
      return const [];
    }
  }

  /// `df -P -T -B1`: device, type, size, used, available, use%, mount.
  static List<DiskUse> parseDfAll(String out) {
    final disks = <DiskUse>[];
    for (final line in const LineSplitter().convert(out).skip(1)) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 7) continue;
      final size = int.tryParse(f[2]) ?? 0;
      final used = int.tryParse(f[3]) ?? 0;
      final mount = f.sublist(6).join(' ');
      if (!DiskUse.worthShowing(f[1], mount, size)) continue;
      disks.add(
        DiskUse(
          label: DiskUse.labelFor(mount),
          mount: mount,
          device: baseDevice(f[0]),
          percent: double.tryParse(f[5].replaceAll('%', '')) ?? 0,
          size: size,
          used: used,
        ),
      );
    }
    return DiskUse.tidy(disks);
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

  /// SMART, when the machine offers it — Glances only loads the plugin
  /// with pySMART installed and when running as root.
  Future<Object?> _smart() async {
    try {
      return await _get('smart');
    } catch (_) {
      return null;
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
        _smart(),
      ]);
      return fromGlances(
        name,
        quicklook: quick,
        fs: results[0],
        sensors: results[1],
        uptime: results[2],
        containers: results[3],
        smart: results[4],
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
    Object? smart,
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

    final health = DiskHealth.fromGlances(smart);
    final disks =
        DiskUse.tidy([
          if (fs is List)
            for (final e in fs.whereType<Map>())
              if (DiskUse.worthShowing(
                '${e['fs_type'] ?? ''}',
                '${e['mnt_point'] ?? ''}',
                (e['size'] as num?)?.toInt() ?? 0,
              ))
                DiskUse(
                  label: DiskUse.labelFor('${e['mnt_point']}'),
                  mount: '${e['mnt_point']}',
                  device: baseDevice('${e['device_name'] ?? ''}'),
                  percent: pct(e['percent']) ?? 0,
                  size: (e['size'] as num?)?.toInt() ?? 0,
                  used: (e['used'] as num?)?.toInt() ?? 0,
                ),
        ]).map((d) {
          final h = health.where((h) => h.device == d.device);
          return d.withHealth(h.isEmpty ? null : h.first);
        }).toList();

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
      disks: disks,
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
