import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One Socket.IO packet, as it is written inside an Engine.IO message:
/// the type, a namespace when it is not the root, the number an answer is
/// expected under, and JSON.
class SocketIoPacket {
  const SocketIoPacket(this.type, {this.namespace = '/', this.id, this.data});

  static const connect = 0;
  static const disconnect = 1;
  static const event = 2;
  static const ack = 3;
  static const error = 4;

  final int type;
  final String namespace;
  final int? id;
  final Object? data;

  String encode() =>
      '$type'
      '${namespace == '/' ? '' : '$namespace,'}'
      '${id ?? ''}'
      '${data == null ? '' : jsonEncode(data)}';

  /// Null for what this client has no use for: binary packets, and anything
  /// that is not a packet at all.
  static SocketIoPacket? parse(String s) {
    if (s.isEmpty) return null;
    final type = int.tryParse(s[0]);
    if (type == null || type > error) return null;
    var i = 1;
    var namespace = '/';
    if (i < s.length && s[i] == '/') {
      final comma = s.indexOf(',', i);
      final end = comma < 0 ? s.length : comma;
      // A namespace joined with a query is echoed with it.
      namespace = s.substring(i, end).split('?').first;
      i = comma < 0 ? s.length : comma + 1;
    }
    final digits = RegExp(r'\d+').matchAsPrefix(s, i);
    final id = digits == null ? null : int.parse(digits[0]!);
    i = digits?.end ?? i;
    Object? data;
    if (i < s.length) {
      try {
        data = jsonDecode(s.substring(i));
      } on FormatException {
        return null;
      }
    }
    return SocketIoPacket(type, namespace: namespace, id: id, data: data);
  }
}

/// Something the server said: an event's name, what came with it, and the
/// namespace it was said in.
class SocketIoEvent {
  const SocketIoEvent(this.namespace, this.name, this.args);

  final String namespace;
  final String name;
  final List<dynamic> args;
}

class SocketIoClosed implements Exception {
  const SocketIoClosed();

  @override
  String toString() => 'Socket.IO connection closed';
}

/// The WebSocket underneath, as little of it as the client needs — so a test
/// can stand in for the server without a network.
class SocketIoWire {
  const SocketIoWire({
    required this.incoming,
    required this.send,
    required this.close,
  });

  final Stream<String> incoming;
  final void Function(String) send;
  final void Function() close;
}

typedef SocketIoOpener = Future<SocketIoWire> Function(Uri uri);

Future<SocketIoWire> _webSocket(Uri uri) async {
  final ws = await WebSocket.connect('$uri');
  return SocketIoWire(
    incoming: ws.where((m) => m is String).cast<String>(),
    send: ws.add,
    close: () => unawaited(ws.close().catchError((_) {})),
  );
}

/// A Socket.IO client for servers of the 2.x line — Engine.IO 3, which is
/// what a Homey speaks — over a WebSocket and nothing else: no long-polling
/// to upgrade from, no binary, and no reconnecting, which is left to whoever
/// holds it.
///
/// Events can be sent with an answer awaited, namespaces joined, and what
/// the server says listened to. In Engine.IO 3 it is the client that pings.
class SocketIoClient {
  SocketIoClient._(this._wire);

  /// Connects to the Socket.IO server at [base] — `http://192.168.1.50` —
  /// and returns once it has said hello.
  static Future<SocketIoClient> connect(
    Uri base, {
    SocketIoOpener? open,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/socket.io/',
      queryParameters: const {'EIO': '3', 'transport': 'websocket'},
    );
    final wire = await (open ?? _webSocket)(uri).timeout(timeout);
    final client = SocketIoClient._(wire);
    client._listening = wire.incoming.listen(
      client._onMessage,
      onError: (_) => client.close(),
      onDone: client.close,
    );
    try {
      await client._opened.future.timeout(timeout);
    } catch (_) {
      client.close();
      rethrow;
    }
    return client;
  }

  final SocketIoWire _wire;
  StreamSubscription<String>? _listening;
  final _opened = Completer<void>();
  final _done = Completer<void>();
  final _events = StreamController<SocketIoEvent>.broadcast();
  final Map<int, Completer<List<dynamic>>> _acks = {};
  final Map<String, Completer<void>> _joining = {};
  Timer? _ping;
  Timer? _pongDue;
  int _nextAck = 0;
  bool _closed = false;

  /// What the server says, in every namespace joined.
  Stream<SocketIoEvent> get events => _events.stream;

  /// Completes when the connection has gone, whoever closed it.
  Future<void> get done => _done.future;

  bool get closed => _closed;

  /// Says [event] with [args], and returns what the server answers with.
  Future<List<dynamic>> emit(
    String event,
    List<Object?> args, {
    String namespace = '/',
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_closed) return Future.error(const SocketIoClosed());
    final id = _nextAck++;
    final answer = Completer<List<dynamic>>();
    _acks[id] = answer;
    _send(
      SocketIoPacket(
        SocketIoPacket.event,
        namespace: namespace,
        id: id,
        data: [event, ...args],
      ),
    );
    return answer.future.timeout(
      timeout,
      onTimeout: () {
        _acks.remove(id);
        throw TimeoutException('No answer to $event', timeout);
      },
    );
  }

  /// Joins [namespace], whose events then arrive on [events].
  Future<void> join(
    String namespace, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_closed) return Future.error(const SocketIoClosed());
    final joined = _joining[namespace] = Completer<void>();
    _send(SocketIoPacket(SocketIoPacket.connect, namespace: namespace));
    return joined.future.timeout(
      timeout,
      onTimeout: () {
        _joining.remove(namespace);
        throw TimeoutException('Could not join $namespace', timeout);
      },
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _ping?.cancel();
    _pongDue?.cancel();
    unawaited(_listening?.cancel());
    _wire.close();
    const gone = SocketIoClosed();
    if (!_opened.isCompleted) _opened.completeError(gone);
    for (final c in [..._acks.values, ..._joining.values]) {
      if (!c.isCompleted) c.completeError(gone);
    }
    _acks.clear();
    _joining.clear();
    unawaited(_events.close());
    _done.complete();
  }

  // Engine.IO's packet types: the first character of every message.
  static const _eOpen = '0';
  static const _eClose = '1';
  static const _ePing = '2';
  static const _ePong = '3';
  static const _eMessage = '4';

  void _send(SocketIoPacket p) => _wire.send('$_eMessage${p.encode()}');

  void _onMessage(String m) {
    if (m.isEmpty || _closed) return;
    final rest = m.substring(1);
    switch (m[0]) {
      case _eOpen:
        _start(rest);
      case _eClose:
        close();
      case _ePing:
        // Engine.IO 4 turned the ping round; answered, in case it is one.
        _wire.send('$_ePong$rest');
      case _ePong:
        _pongDue?.cancel();
      case _eMessage:
        final p = SocketIoPacket.parse(rest);
        if (p != null) _onPacket(p);
    }
  }

  void _start(String hello) {
    var every = const Duration(seconds: 25);
    var patience = const Duration(seconds: 20);
    try {
      final j = jsonDecode(hello);
      if (j is Map) {
        if (j['pingInterval'] case final num ms) {
          every = Duration(milliseconds: ms.toInt());
        }
        if (j['pingTimeout'] case final num ms) {
          patience = Duration(milliseconds: ms.toInt());
        }
      }
    } on FormatException {
      // The usual intervals will do.
    }
    // A server that says "every nought milliseconds" is not taken at its word.
    if (every < const Duration(seconds: 1)) every = const Duration(seconds: 1);
    _ping?.cancel();
    _ping = Timer.periodic(every, (_) {
      _wire.send(_ePing);
      _pongDue?.cancel();
      _pongDue = Timer(patience, close);
    });
    if (!_opened.isCompleted) _opened.complete();
  }

  void _onPacket(SocketIoPacket p) {
    switch (p.type) {
      case SocketIoPacket.connect:
        _joining.remove(p.namespace)?.complete();
      case SocketIoPacket.error:
        _joining
            .remove(p.namespace)
            ?.completeError(StateError('${p.namespace} refused: ${p.data}'));
      case SocketIoPacket.disconnect:
        if (p.namespace == '/') close();
      case SocketIoPacket.event:
        final data = p.data;
        if (data is List && data.isNotEmpty) {
          _events.add(
            SocketIoEvent(p.namespace, '${data.first}', data.sublist(1)),
          );
        }
      case SocketIoPacket.ack:
        final data = p.data;
        _acks.remove(p.id)?.complete(data is List ? data : const []);
    }
  }
}
