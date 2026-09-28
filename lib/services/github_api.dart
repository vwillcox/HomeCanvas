import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// What a GitHub tile wants fetched besides the repository itself — each is
/// a request of its own against a 60-an-hour allowance without a token, so
/// only what is shown is asked for.
@immutable
class GithubWanted {
  const GithubWanted({
    this.pulls = true,
    this.contributors = true,
    this.release = false,
    this.commits = true,
    this.clones = true,
    this.views = true,
    this.referrers = true,
  });

  final bool pulls;
  final bool contributors;
  final bool release;
  final bool commits;
  final bool clones;
  final bool views;
  final bool referrers;

  bool get traffic => clones || views || referrers;
}

/// Everything fetched for one repository at one time.
@immutable
class GithubSnapshot {
  const GithubSnapshot({
    required this.repo,
    this.pulls,
    this.contributors,
    this.release,
    this.weeklyCommits = const [],
    this.clones,
    this.views,
    this.referrers = const [],
    this.trafficDenied = false,
  });

  /// GitHub's own description of the repository.
  final Map<String, dynamic> repo;

  /// Open pull requests, or null if they couldn't be counted.
  final int? pulls;
  final int? contributors;
  final Map<String, dynamic>? release;

  /// Commits a week, oldest first — up to a year of them.
  final List<int> weeklyCommits;

  /// Traffic over the last 14 days: {count, uniques}. Owner-only, and only
  /// with a token that has Administration read access.
  final Map<String, dynamic>? clones;
  final Map<String, dynamic>? views;
  final List<Map<String, dynamic>> referrers;

  /// A token was given, but GitHub refused it the traffic figures.
  final bool trafficDenied;
}

/// Why a repository couldn't be fetched, in terms the tile can explain.
enum GithubFailure {
  /// No such repository — or a private one, which GitHub reports the same.
  notFound,

  /// The token is wrong or has expired.
  badToken,

  /// Out of requests for the hour.
  rateLimited,

  /// The token works but may not see this repository.
  forbidden,

  /// Nothing answered.
  unreachable,

  /// Something else.
  unexpected,
}

class GithubException implements Exception {
  const GithubException(this.failure);
  final GithubFailure failure;

  @override
  String toString() => 'GithubException($failure)';
}

/// "owner/name" from what someone typed or pasted — `owner/name`, a
/// repository's address with or without https:// or www., a clone address
/// ending .git, or a link to somewhere inside it — or null when it isn't one.
///
/// Held to GitHub's own rules for names (letters, digits and hyphens for an
/// owner; those and . and _ for a repository), which also keeps what goes
/// into the request's path to exactly one owner and one repository.
String? parseRepository(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^git@github\.com:', caseSensitive: false), '');
  s = s.replaceFirst(
    RegExp(r'^(?:https?://)?(?:www\.)?github\.com/', caseSensitive: false),
    '',
  );
  s = s.split(RegExp(r'[?#]')).first;
  final parts = s.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return null;
  final owner = parts[0];
  var name = parts[1];
  if (name.toLowerCase().endsWith('.git')) {
    name = name.substring(0, name.length - 4);
  }
  if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$').hasMatch(owner)) {
    return null;
  }
  if (!RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(name) ||
      name == '.' ||
      name == '..') {
    return null;
  }
  return '$owner/$name';
}

/// How many items a paged list holds, from a one-per-page request: the
/// last page's number in its Link header, or the page's own length when
/// there is only one page.
int countFromLink(String? link, Object? data) {
  final last = RegExp(
    r'<[^>]*[?&]page=(\d+)[^>]*>;\s*rel="last"',
  ).firstMatch(link ?? '');
  if (last != null) return int.tryParse(last.group(1)!) ?? 0;
  return data is List ? data.length : 0;
}

/// What a failed request means. A 403 is only a rate limit when GitHub says
/// no requests remain; otherwise it is a token that may not see the repo.
GithubFailure classify(DioException e) {
  final r = e.response;
  if (r == null) return GithubFailure.unreachable;
  final remaining = r.headers.value('x-ratelimit-remaining');
  return switch (r.statusCode) {
    404 => GithubFailure.notFound,
    401 => GithubFailure.badToken,
    429 => GithubFailure.rateLimited,
    403 when remaining == '0' => GithubFailure.rateLimited,
    403 => GithubFailure.forbidden,
    _ => GithubFailure.unexpected,
  };
}

/// GitHub's REST API, for the dashboard's repository tiles.
class GithubApi {
  GithubApi({Dio? dio}) : _dio = dio ?? _shared;

  static final Dio _shared = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );

  final Dio _dio;

  /// Replaces every fetch — for tests, which have no network.
  @visibleForTesting
  static Future<GithubSnapshot> Function(
    String repo,
    String token,
    GithubWanted want,
  )? debugFetch;

  static const _base = 'https://api.github.com/repos';

  /// [repo] must have come through [parseRepository].
  Future<GithubSnapshot> fetch(
    String repo, {
    String token = '',
    GithubWanted want = const GithubWanted(),
  }) async {
    final fake = debugFetch;
    if (fake != null) return fake(repo, token, want);

    // Only ever sent to api.github.com.
    final options = Options(
      headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
    );
    final Map<String, dynamic> raw;
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$_base/$repo',
        options: options,
      );
      raw = r.data ?? const {};
    } on DioException catch (e) {
      throw GithubException(classify(e));
    }

    int? pulls, contributors;
    Map<String, dynamic>? release, clones, views;
    var weekly = const <int>[];
    var referrers = const <Map<String, dynamic>>[];
    var trafficDenied = false;

    Future<void> quietly(Future<void> Function() get) async {
      try {
        await get();
      } on DioException catch (e) {
        if (e.response?.statusCode == 403 || e.response?.statusCode == 401) {
          trafficDenied = true;
        }
      } catch (_) {
        // A missing extra leaves its figure out; the tile still shows.
      }
    }

    await Future.wait([
      if (want.pulls)
        quietly(() async {
          final r = await _dio.get<Object?>(
            '$_base/$repo/pulls',
            queryParameters: {'state': 'open', 'per_page': 1},
            options: options,
          );
          pulls = countFromLink(r.headers.value('link'), r.data);
        }),
      if (want.contributors)
        quietly(() async {
          final r = await _dio.get<Object?>(
            '$_base/$repo/contributors',
            queryParameters: {'per_page': 1},
            options: options,
          );
          contributors = countFromLink(r.headers.value('link'), r.data);
        }),
      if (want.release)
        quietly(() async {
          final r = await _dio.get<Map<String, dynamic>>(
            '$_base/$repo/releases/latest',
            options: options,
          );
          release = r.data;
        }),
      if (want.commits) quietly(() async => weekly = await _commits(repo, options)),
      // Traffic is owner-only: without a token it always fails, and each
      // try would spend an hour's allowance for nothing.
      if (token.isNotEmpty && want.clones)
        quietly(() async {
          final r = await _dio.get<Map<String, dynamic>>(
            '$_base/$repo/traffic/clones',
            options: options,
          );
          clones = r.data;
        }),
      if (token.isNotEmpty && want.views)
        quietly(() async {
          final r = await _dio.get<Map<String, dynamic>>(
            '$_base/$repo/traffic/views',
            options: options,
          );
          views = r.data;
        }),
      if (token.isNotEmpty && want.referrers)
        quietly(() async {
          final r = await _dio.get<List<dynamic>>(
            '$_base/$repo/traffic/popular/referrers',
            options: options,
          );
          referrers = (r.data ?? const [])
              .whereType<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
        }),
    ]);

    return GithubSnapshot(
      repo: raw,
      pulls: pulls,
      contributors: contributors,
      release: release,
      weeklyCommits: weekly,
      clones: clones,
      views: views,
      referrers: referrers,
      trafficDenied: trafficDenied,
    );
  }

  /// Weekly commit counts. GitHub works these out on demand and answers
  /// 202 with nothing while it does, so one more try follows a moment later
  /// rather than leaving the chart empty until the next refresh.
  Future<List<int>> _commits(String repo, Options options) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final r = await _dio.get<Object?>(
        '$_base/$repo/stats/commit_activity',
        options: options.copyWith(
          validateStatus: (s) => s != null && s < 300,
        ),
      );
      final data = r.data;
      if (r.statusCode == 200 && data is List) {
        return [
          for (final week in data.whereType<Map>())
            (week['total'] as num?)?.toInt() ?? 0,
        ];
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return const [];
  }
}
