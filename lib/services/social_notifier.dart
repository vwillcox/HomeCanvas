import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dashboard/dashboard_model.dart';
import '../l10n/l10n.dart';
import 'bluesky_api.dart';
import 'config_service.dart';
import 'mastodon_api.dart';
import 'social.dart';

/// The account a Mastodon tile signs in as, or null while its settings lack
/// a server or a token. Shared with the tile, so the two read the settings
/// alike.
MastodonAccount? mastodonAccountOf(Map<String, dynamic> options) {
  final server = serverAddress('${options['server'] ?? ''}');
  final token = '${options['token'] ?? ''}'.trim();
  if (server == null || token.isEmpty) return null;
  return MastodonAccount(server: server, token: token);
}

/// The account a Bluesky tile signs in as, or null while its settings lack
/// a handle or a password.
BlueskyAccount? blueskyAccountOf(Map<String, dynamic> options) {
  final handle = blueskyIdentifier('${options['handle'] ?? ''}');
  final password = '${options['appPassword'] ?? ''}'.trim();
  if (handle.isEmpty || password.isEmpty) return null;
  final typed = '${options['service'] ?? ''}'.trim();
  final service = typed.isEmpty
      ? BlueskyAccount.defaultService
      : serverAddress(typed) ?? BlueskyAccount.defaultService;
  return BlueskyAccount(
    identifier: handle,
    password: password,
    service: service,
  );
}

/// What the panel has seen of one account's notifications.
class _Seen {
  /// The newest seen: an id on Mastodon, a time on Bluesky.
  String? newestId;
  DateTime? newestAt;
}

/// Pops up a card on the panel — the one a share from the phone gets, with
/// its chime — when a Mastodon or Bluesky account has a new notification.
///
/// Which accounts, and for which notifications, is set on their tiles:
/// a tile's "Notify on the panel" setting. The tile need not be on the page
/// showing, nor the dashboard on screen. Two tiles signed in as the same
/// account give one card, not two.
///
/// Whatever is waiting when the panel starts is taken as seen: a restart
/// is not news.
class SocialNotifier {
  SocialNotifier(
    this._config, {
    required this.onNotices,
    MastodonApi? mastodon,
    BlueskyApi? bluesky,
  }) : _mastodon = mastodon ?? MastodonApi(),
       _bluesky = bluesky ?? BlueskyApi();

  final ConfigService _config;
  final MastodonApi _mastodon;
  final BlueskyApi _bluesky;

  /// Puts up the card: [from] is the network, [title] the line on the card,
  /// and [text] what opening it shows.
  final void Function({
    required String from,
    required String title,
    required String text,
  })
  onNotices;

  static const every = Duration(minutes: 1);

  /// Notifications on one card's text before the rest are only counted.
  static const shownOnCard = 6;

  final Map<String, _Seen> _seen = {};
  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(check()));
    unawaited(check());
  }

  void dispose() => _timer?.cancel();

  /// Each account's newest notifications, and a card for any not seen
  /// before.
  @visibleForTesting
  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      final watched = _watched();
      // An account no longer watched starts afresh if it is again.
      _seen.removeWhere((key, _) => !watched.containsKey(key));
      for (final (:account, :all) in watched.values) {
        try {
          switch (account) {
            case MastodonAccount a:
              await _checkMastodon(a, all: all);
            case BlueskyAccount a:
              await _checkBluesky(a, all: all);
          }
        } catch (e) {
          // Tried again in a minute; the tile says what is wrong.
          debugPrint('Social notifications: $e');
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// Every account a tile asks to be told about, by its key, and whether
  /// for all its notifications or only those talking to it.
  Map<String, ({Object account, bool all})> _watched() {
    final settings = _config.config.dashboard;
    final out = <String, ({Object account, bool all})>{};
    if (!settings.enabled) return out;
    for (final DashboardWidgetConfig w in settings.widgets) {
      final notify = '${w.options['notify'] ?? 'off'}';
      if (notify != 'mentions' && notify != 'all') continue;
      final Object? account = switch (w.type) {
        'mastodon' => mastodonAccountOf(w.options),
        'bluesky' => blueskyAccountOf(w.options),
        _ => null,
      };
      final key = switch (account) {
        MastodonAccount a => 'mastodon ${a.key}',
        BlueskyAccount a => 'bluesky ${a.key}',
        _ => null,
      };
      if (account == null || key == null) continue;
      // Of two tiles for one account, the one that wants more has its way.
      final all = notify == 'all' || (out[key]?.all ?? false);
      out[key] = (account: account, all: all);
    }
    return out;
  }

  Future<void> _checkMastodon(MastodonAccount a, {required bool all}) async {
    final key = 'mastodon ${a.key}';
    final seen = _seen[key];
    final notices = await _mastodon.notices(a, sinceId: seen?.newestId);
    final newest = notices
        .map((n) => n.id)
        .fold<String?>(
          seen?.newestId,
          (best, id) =>
              best == null || compareMastodonIds(id, best) > 0 ? id : best,
        );
    _seen[key] = _Seen()..newestId = newest;
    if (seen == null) return;
    _tell(SocialNetwork.mastodon, [
      for (final n in notices)
        if (seen.newestId == null ||
            compareMastodonIds(n.id, seen.newestId!) > 0)
          n,
    ], all: all);
  }

  Future<void> _checkBluesky(BlueskyAccount a, {required bool all}) async {
    final key = 'bluesky ${a.key}';
    final seen = _seen[key];
    final notices = await _bluesky.notices(a);
    DateTime? newest = seen?.newestAt;
    for (final n in notices) {
      final at = n.at;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    _seen[key] = _Seen()..newestAt = newest;
    if (seen == null) return;
    final since = seen.newestAt;
    _tell(SocialNetwork.bluesky, [
      for (final n in notices)
        if (n.at != null && (since == null || n.at!.isAfter(since))) n,
    ], all: all);
  }

  /// One card for whatever of [fresh] is wanted, oldest first.
  void _tell(
    SocialNetwork network,
    List<SocialNotice> fresh, {
    required bool all,
  }) {
    final wanted = [
      for (final n in fresh.reversed)
        if (all || n.direct) n,
    ];
    if (wanted.isEmpty) return;
    onNotices(
      from: network.title,
      title: wanted.length == 1
          ? noticeLine(wanted.single, network)
          : tr('widget.social.newNotifications', '{count} new notifications', {
              'count': wanted.length,
            }),
      text: cardText(wanted, network),
    );
  }

  /// What opening the card shows: each notification on a line of its own,
  /// with what was said where there is something.
  @visibleForTesting
  static String cardText(List<SocialNotice> notices, SocialNetwork network) {
    final lines = [
      for (final n in notices.take(shownOnCard))
        switch (_excerpt(n.post?.text ?? '')) {
          '' => noticeLine(n, network),
          final said => '${noticeLine(n, network)}: “$said”',
        },
      if (notices.length > shownOnCard)
        tr('widget.social.andMore', 'and {count} more', {
          'count': notices.length - shownOnCard,
        }),
    ];
    return lines.join('\n\n');
  }

  /// [text] on one line, cut short where it is long.
  static String _excerpt(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length <= 140 ? line : '${line.substring(0, 139).trim()}…';
  }
}
