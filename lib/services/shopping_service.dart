import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One thing to get.
@immutable
class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.text,
    required this.added,
    this.doneAt,
  });

  final String id;
  final String text;
  final DateTime added;

  /// When it was ticked off; null while it is still to get.
  final DateTime? doneAt;

  bool get done => doneAt != null;

  ShoppingItem ticked(DateTime? at) =>
      ShoppingItem(id: id, text: text, added: added, doneAt: at);

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'added': added.toUtc().toIso8601String(),
    if (doneAt != null) 'doneAt': doneAt!.toUtc().toIso8601String(),
  };

  static ShoppingItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}'.trim();
    final added = DateTime.tryParse('${j['added'] ?? ''}');
    if (text.isEmpty || added == null) return null;
    return ShoppingItem(
      id: '${j['id'] ?? added.microsecondsSinceEpoch}',
      text: text,
      added: added.toLocal(),
      doneAt: DateTime.tryParse('${j['doneAt'] ?? ''}')?.toLocal(),
    );
  }
}

/// The household shopping list: added to from a phone, ticked off on the
/// panel (or the phone), and ticked items cleared away after a while so the
/// list does not fill up with last week's milk.
class ShoppingService extends ChangeNotifier {
  ShoppingService({
    String? file,
    DateTime Function()? clock,
    this.persist = true,
  }) : _file = File(file ?? defaultFile()),
       _clock = clock ?? DateTime.now;

  static String defaultFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'immich_kiosk_pi', 'shopping.json');
  }

  /// A ticked item stays, faded, for this long — long enough to untick a
  /// mis-tap, short enough that it is gone by the next shop.
  static const keepTicked = Duration(hours: 12);
  static const maxItems = 100;
  static const maxLength = 80;

  /// Off keeps the list in memory only, for tests.
  final bool persist;
  final File _file;
  final DateTime Function() _clock;
  List<ShoppingItem> _items = [];
  int _seq = 0;
  Timer? _sweep;

  /// Still to get first, in the order they were added; then the ticked.
  List<ShoppingItem> get items {
    final todo = _items.where((i) => !i.done).toList()
      ..sort((a, b) => a.added.compareTo(b.added));
    final done = _items.where((i) => i.done).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return List.unmodifiable([...todo, ...done]);
  }

  int get toGet => _items.where((i) => !i.done).length;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final data = jsonDecode(await _file.readAsString());
        if (data is List) {
          _items = [for (final j in data) ?ShoppingItem.fromJson(j)];
        }
      }
    } catch (e) {
      debugPrint('Shopping: could not read ${_file.path}: $e');
    }
    _prune();
    notifyListeners();
    // Ticked items age out while nobody is touching the list, too.
    _sweep ??= Timer.periodic(const Duration(minutes: 10), (_) {
      if (_prune()) {
        notifyListeners();
        unawaited(_save());
      }
    });
  }

  /// Adds [text], or — if it is already on the list — brings it back rather
  /// than listing milk twice.
  ShoppingItem? add(String text) {
    var clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return null;
    if (clean.length > maxLength) clean = clean.substring(0, maxLength);
    final existing = _items.indexWhere(
      (i) => i.text.toLowerCase() == clean.toLowerCase(),
    );
    if (existing >= 0) {
      _items[existing] = _items[existing].ticked(null);
    } else {
      _items.add(
        ShoppingItem(
          id: '${_clock().microsecondsSinceEpoch}-${++_seq}',
          text: clean,
          added: _clock(),
        ),
      );
    }
    _prune();
    notifyListeners();
    unawaited(_save());
    return existing >= 0 ? _items[existing] : _items.last;
  }

  void toggle(String id) {
    final i = _items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _items[i] = _items[i].ticked(_items[i].done ? null : _clock());
    notifyListeners();
    unawaited(_save());
  }

  bool remove(String id) {
    final before = _items.length;
    _items.removeWhere((x) => x.id == id);
    if (_items.length == before) return false;
    notifyListeners();
    unawaited(_save());
    return true;
  }

  bool _prune() {
    final before = _items.length;
    final cutoff = _clock().subtract(keepTicked);
    _items.removeWhere((i) => i.done && i.doneAt!.isBefore(cutoff));
    if (_items.length > maxItems) {
      _items = _items.sublist(_items.length - maxItems);
    }
    return _items.length != before;
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
      await tmp.writeAsString(jsonEncode([for (final i in _items) i.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Shopping: could not save: $e');
    }
  }

  @override
  void dispose() {
    _sweep?.cancel();
    super.dispose();
  }
}
