import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../app_paths.dart';
import '../dashboard/custom_widget_spec.dart';
import '../dashboard/widget_registry.dart';
import '../dashboard/widgets/custom_widget.dart';
import '../l10n/l10n.dart';

/// What a custom widget's source last answered, or why it did not.
class CustomAnswer {
  const CustomAnswer({required this.at, this.data, this.error});

  final DateTime at;
  final Object? data;
  final String? error;
}

/// Widgets installed from a file rather than built in: kept in a folder
/// beside the settings, registered as they are installed, and fetched for.
///
/// Installing one needs no restart. It joins the registry the dashboard and
/// the editor already draw from, and everything on screen is asked to build
/// again — so a tile that said "Unknown widget" a moment ago is the widget.
class CustomWidgets extends ChangeNotifier {
  CustomWidgets({String? dir, Dio? dio, this.onChanged})
    : dir = dir ?? p.join(AppPaths.config, 'widgets'),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                'User-Agent': 'HomeCanvas/1.0 (home dashboard panel)',
              },
            ),
          );

  final String dir;
  final Dio _dio;

  /// Called when one is installed or removed, to draw the panel again.
  final VoidCallback? onChanged;

  final Map<String, CustomWidgetSpec> _specs = {};
  final Map<String, CustomAnswer> _answers = {};
  final Map<String, Future<void>> _asking = {};
  bool _disposed = false;

  /// As many as anyone will install, and not so many that a mistake fills
  /// the palette.
  static const most = 50;

  List<CustomWidgetSpec> get all =>
      _specs.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  CustomWidgetSpec? spec(String id) => _specs[id];

  @override
  void dispose() {
    _disposed = true;
    _dio.close();
    super.dispose();
  }

  File _file(String id) => File(p.join(dir, '$id.json'));

  void _register(CustomWidgetSpec spec) {
    _specs[spec.id] = spec;
    WidgetRegistry.register(customWidgetType(spec));
  }

  /// Registers everything in the folder. A file that cannot be read is
  /// left where it is and said so in the log; the rest still load.
  Future<void> load() async {
    try {
      final folder = Directory(dir);
      if (!await folder.exists()) return;
      await for (final f in folder.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          _register(CustomWidgetSpec.parse(await f.readAsString()));
        } catch (e) {
          debugPrint('Custom widget ${p.basename(f.path)}: $e');
        }
      }
    } catch (e) {
      debugPrint('Custom widgets: $e');
    }
  }

  /// Installs the file [source], in place of one of the same name if there
  /// is one. Throws a [FormatException] saying what is wrong with it.
  Future<CustomWidgetSpec> install(String source) async {
    final spec = CustomWidgetSpec.parse(source);
    if (!_specs.containsKey(spec.id) && _specs.length >= most) {
      throw const FormatException('That is the most custom widgets there can be.');
    }
    await Directory(dir).create(recursive: true);
    // Beside it and then over it, so a power cut leaves the old one whole.
    final part = File('${_file(spec.id).path}.part');
    await part.writeAsString(source, flush: true);
    await part.rename(_file(spec.id).path);
    _register(spec);
    _answers.clear();
    _changed();
    return spec;
  }

  /// Removes one. A tile of it then says "Unknown widget", and keeps its
  /// settings for if it is installed again.
  Future<bool> remove(String id) async {
    final spec = _specs.remove(id);
    if (spec == null) return false;
    WidgetRegistry.unregister(spec.type);
    try {
      await _file(id).delete();
    } catch (_) {}
    _changed();
    return true;
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    onChanged?.call();
  }

  /// What [url] last answered, if it has been asked.
  CustomAnswer? answer(String url) => _answers[url];

  /// Fetches [url] unless it was fetched within [every]. Shared between
  /// tiles asking for the same address at once; a failure keeps the last
  /// answer on screen and is not tried again until [every] has passed.
  Future<void> ensure(
    String url, {
    Map<String, String> headers = const {},
    Duration every = const Duration(minutes: 5),
  }) {
    final had = _answers[url];
    if (had != null && DateTime.now().difference(had.at) < every) {
      return Future.value();
    }
    return _asking[url] ??= _fetch(
      url,
      headers,
      had,
    ).whenComplete(() {
      // Not returned: what is removed is this very future, and waiting on
      // it here would wait for ever.
      _asking.remove(url);
    });
  }

  static const _maxBytes = 2 * 1024 * 1024;

  Future<void> _fetch(
    String url,
    Map<String, String> headers,
    CustomAnswer? had,
  ) async {
    String? error;
    Object? data = had?.data;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      error = tr('widget.custom.badAddress', 'Its address is not one to fetch.');
    } else {
      try {
        final r = await _dio.getUri<ResponseBody>(
          uri,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
          ),
        );
        // Counted as it arrives: a source that never stops sending is
        // hung up on, not held in memory until it does.
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in r.data?.stream ?? const Stream.empty()) {
          bytes.add(chunk);
          if (bytes.length > _maxBytes) break;
        }
        if (bytes.length > _maxBytes) {
          error = tr('widget.custom.tooBig', 'Its source sent too much.');
        } else {
          data = _decode(bytes.takeBytes());
        }
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        error = status == null
            ? tr('widget.custom.unreachable', 'Could not reach its source.')
            : tr('widget.custom.refused', 'Its source answered {status}.', {
                'status': status,
              });
      } catch (_) {
        error = tr('widget.custom.notJson', 'Its source did not send JSON.');
      }
    }
    if (_disposed) return;
    _answers[url] = CustomAnswer(at: DateTime.now(), data: data, error: error);
    notifyListeners();
  }

  @visibleForTesting
  void debugAnswer(String url, Object? data) {
    _answers[url] = CustomAnswer(
      at: DateTime.now().add(const Duration(days: 1)),
      data: data,
    );
    notifyListeners();
  }
}

Object? _decode(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true)
        .fuse(const JsonDecoder())
        .convert(bytes);
