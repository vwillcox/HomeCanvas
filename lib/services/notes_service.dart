import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One note on the household board.
@immutable
class HouseNote {
  const HouseNote({
    required this.id,
    required this.text,
    required this.from,
    required this.at,
  });

  final String id;
  final String text;
  final String from;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'from': from,
    'at': at.toUtc().toIso8601String(),
  };

  static HouseNote? fromJson(Object? j) {
    if (j is! Map) return null;
    final text = '${j['text'] ?? ''}'.trim();
    final at = DateTime.tryParse('${j['at'] ?? ''}');
    if (text.isEmpty || at == null) return null;
    return HouseNote(
      id: '${j['id'] ?? at.microsecondsSinceEpoch}',
      text: text,
      from: '${j['from'] ?? ''}'.trim(),
      at: at.toLocal(),
    );
  }
}

/// Sticky notes for the household, shown by the dashboard's Notes widget.
///
/// Notes arrive two ways: text shared from the companion app (the Share
/// inbox already carries it, end-to-end encrypted), and a small page on the
/// kiosk's own editor server that any phone on the home network can post to.
/// Kept in a file beside the config, so a restart does not lose them.
class NotesService extends ChangeNotifier {
  NotesService({String? file, DateTime Function()? clock, this.persist = true})
    : _file = File(file ?? defaultFile()),
      _clock = clock ?? DateTime.now;

  /// Off keeps the notes in memory only — for tests, which cannot wait on
  /// the disk inside their simulated time.
  final bool persist;

  static String defaultFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return p.join(home, '.config', 'immich_kiosk_pi', 'notes.json');
  }

  /// A note older than this is taken down, so the board clears itself of
  /// things nobody got round to dismissing.
  static const keepFor = Duration(days: 14);

  /// And never more than this many — the oldest go first.
  static const maxNotes = 30;

  /// Long enough for a message, short enough to fit on a sticky note.
  static const maxLength = 280;

  final File _file;
  final DateTime Function() _clock;
  List<HouseNote> _notes = [];
  int _seq = 0;

  /// Newest first.
  List<HouseNote> get notes => List.unmodifiable(_notes);

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final data = jsonDecode(await _file.readAsString());
      if (data is! List) return;
      _notes = [for (final j in data) ?HouseNote.fromJson(j)];
      _prune();
      notifyListeners();
    } catch (e) {
      debugPrint('Notes: could not read ${_file.path}: $e');
    }
  }

  HouseNote? add(String text, {String from = ''}) {
    final clean = text.trim().replaceAll(RegExp(r'\s+\n'), '\n');
    if (clean.isEmpty) return null;
    final now = _clock();
    final note = HouseNote(
      id: '${now.microsecondsSinceEpoch}-${++_seq}',
      text: clean.length > maxLength
          ? '${clean.substring(0, maxLength - 1)}…'
          : clean,
      from: from.trim(),
      at: now,
    );
    _notes.insert(0, note);
    _prune();
    notifyListeners();
    unawaited(_save());
    return note;
  }

  bool remove(String id) {
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length == before) return false;
    notifyListeners();
    unawaited(_save());
    return true;
  }

  void _prune() {
    final cutoff = _clock().subtract(keepFor);
    _notes = _notes.where((n) => n.at.isAfter(cutoff)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (_notes.length > maxNotes) _notes = _notes.sublist(0, maxNotes);
  }

  /// Saves take turns: two notes in quick succession would otherwise race
  /// each other through the same temporary file.
  Future<void> _saving = Future.value();

  /// Resolves once everything asked for so far is on disk.
  Future<void> get saved => _saving;

  Future<void> _save() =>
      persist ? _saving = _saving.then((_) => _write()) : _saving;

  Future<void> _write() async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final n in _notes) n.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Notes: could not save: $e');
    }
  }
}
