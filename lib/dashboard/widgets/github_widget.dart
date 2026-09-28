import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../dashboard_theme.dart';
import '../widget_registry.dart';

/// Repository overview fetched from GitHub's public REST API.
class GithubWidget extends StatelessWidget {
  const GithubWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  List<({String repository, String label})> get _repositories {
    final unique = <String, ({String repository, String label})>{};
    void add(String value, {String label = ''}) {
      final repository = _normaliseRepository(value.trim());
      if (repository.isEmpty) return;
      final key = repository.toLowerCase();
      final previous = unique[key];
      unique[key] = (
        repository: repository,
        label: label.trim().isNotEmpty ? label.trim() : previous?.label ?? '',
      );
    }

    // Read the original single-repository setting for existing dashboards;
    // new entries are managed together in the repeatable list below.
    add(w.option('repository', ''));
    for (final row in w.rows('repositories')) {
      add('${row['repository'] ?? ''}', label: '${row['name'] ?? ''}');
    }
    return unique.isEmpty
        ? [(repository: '', label: '')]
        : unique.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final repositories = _repositories;
    if (repositories.length <= 1) {
      return _GithubRepositoryTile(
        key: ValueKey(repositories.first.repository),
        w: w,
        repository: repositories.first.repository,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final theme = w.theme;
        final tabSize = (c.maxHeight * .045).clamp(13.0, 20.0);
        return DefaultTabController(
          length: repositories.length,
          child: Column(
            children: [
              Expanded(
                child: TabBarView(
                  children: [
                    for (final entry in repositories)
                      _GithubRepositoryTile(
                        key: ValueKey(entry.repository),
                        w: w,
                        repository: entry.repository,
                      ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerHeight: 0,
                labelColor: theme.accent,
                unselectedLabelColor: theme.textSecondary,
                indicatorColor: theme.accent,
                labelStyle: TextStyle(
                  fontSize: tabSize,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  for (final entry in repositories)
                    Tab(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth * .55),
                        child: Text(
                          entry.label.isEmpty ? entry.repository : entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String _normaliseRepository(String value) => value
    .replaceAll(RegExp(r'^https?://github\.com/'), '')
    .replaceAll(RegExp(r'/$'), '');

class _GithubRepositoryTile extends StatefulWidget {
  const _GithubRepositoryTile({
    super.key,
    required this.w,
    required this.repository,
  });
  final DashboardWidgetContext w;
  final String repository;

  @override
  State<_GithubRepositoryTile> createState() => _GithubRepositoryTileState();
}

class _GithubRepositoryTileState extends State<_GithubRepositoryTile> {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {'Accept': 'application/vnd.github+json'},
    ),
  );
  Map<String, dynamic>? _repo;
  int? _pulls;
  int? _contributors;
  Map<String, dynamic>? _release;
  List<int> _weeklyCommits = const [];
  Map<String, dynamic>? _cloneTraffic;
  Map<String, dynamic>? _viewTraffic;
  List<Map<String, dynamic>> _referrers = const [];
  bool _trafficDenied = false;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  String get _repository => widget.repository;
  String get _token => widget.w.option('token', '').trim();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _GithubRepositoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_repository != oldWidget.repository ||
        _token != oldWidget.w.option('token', '').trim()) {
      _repo = null;
      unawaited(_load());
    }
    if (widget.w.config.options['refreshMinutes'] !=
        oldWidget.w.config.options['refreshMinutes']) {
      _schedule();
    }
    for (final option in [
      'showPulls',
      'showIssues',
      'showContributors',
      'showRelease',
      'showCommitChart',
      'showClones',
      'showVisitors',
      'showReferrers',
    ]) {
      if (widget.w.config.options[option] !=
          oldWidget.w.config.options[option]) {
        unawaited(_load());
        break;
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    final minutes =
        (int.tryParse('${widget.w.config.options['refreshMinutes'] ?? 30}') ??
                30)
            .clamp(5, 240);
    _timer = Timer.periodic(
      Duration(minutes: minutes),
      (_) => unawaited(_load()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repository;
    if (_busy) {
      return;
    }
    if (!RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(repo)) {
      if (mounted) {
        setState(
          () => _error = repo.isEmpty
              ? 'Set a repository as owner/name in widget settings.'
              : 'Enter a repository as owner/name.',
        );
      }
      return;
    }
    _busy = true;
    try {
      final headers = <String, dynamic>{
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repo',
        options: Options(headers: headers),
      );
      final raw = response.data!;
      int? pulls, contributors;
      Map<String, dynamic>? release;
      List<int> weeklyCommits = const [];
      Map<String, dynamic>? cloneTraffic;
      Map<String, dynamic>? viewTraffic;
      List<Map<String, dynamic>> referrers = const [];
      var trafficDenied = false;
      final extras = <Future<void>>[];
      if (widget.w.option('showPulls', true) ||
          widget.w.option('showIssues', true)) {
        extras.add(
          _dio
              .get(
                'https://api.github.com/repos/$repo/pulls',
                queryParameters: {'state': 'open', 'per_page': 1},
                options: Options(headers: headers),
              )
              .then((r) {
                pulls = _countFromResponse(r);
              })
              .catchError((_) {}),
        );
      }
      if (widget.w.option('showContributors', true)) {
        extras.add(
          _dio
              .get(
                'https://api.github.com/repos/$repo/contributors',
                queryParameters: {'per_page': 1},
                options: Options(headers: headers),
              )
              .then((r) {
                contributors = _countFromResponse(r);
              })
              .catchError((_) {}),
        );
      }
      if (widget.w.option('showRelease', false)) {
        extras.add(
          _dio
              .get<Map<String, dynamic>>(
                'https://api.github.com/repos/$repo/releases/latest',
                options: Options(headers: headers),
              )
              .then((r) {
                release = r.data;
              })
              .catchError((_) {}),
        );
      }
      if (widget.w.option('showCommitChart', true)) {
        extras.add(
          _dio
              .get<List<dynamic>>(
                'https://api.github.com/repos/$repo/stats/commit_activity',
                options: Options(headers: headers),
              )
              .then((r) {
                weeklyCommits = (r.data ?? const [])
                    .whereType<Map>()
                    .map((week) => (week['total'] as num?)?.toInt() ?? 0)
                    .toList();
              })
              .catchError((_) {}),
        );
      }
      if (widget.w.option('showClones', true)) {
        extras.add(
          _dio
              .get<Map<String, dynamic>>(
                'https://api.github.com/repos/$repo/traffic/clones',
                options: Options(headers: headers),
              )
              .then((r) {
                cloneTraffic = r.data;
              })
              .catchError((e) {
                if (e is DioException && e.response?.statusCode == 403) {
                  trafficDenied = true;
                }
              }),
        );
      }
      if (widget.w.option('showVisitors', true)) {
        extras.add(
          _dio
              .get<Map<String, dynamic>>(
                'https://api.github.com/repos/$repo/traffic/views',
                options: Options(headers: headers),
              )
              .then((r) {
                viewTraffic = r.data;
              })
              .catchError((e) {
                if (e is DioException && e.response?.statusCode == 403) {
                  trafficDenied = true;
                }
              }),
        );
      }
      if (widget.w.option('showReferrers', true)) {
        extras.add(
          _dio
              .get<List<dynamic>>(
                'https://api.github.com/repos/$repo/traffic/popular/referrers',
                options: Options(headers: headers),
              )
              .then((r) {
                referrers = (r.data ?? const [])
                    .whereType<Map>()
                    .map((item) => item.cast<String, dynamic>())
                    .toList();
              })
              .catchError((e) {
                if (e is DioException && e.response?.statusCode == 403) {
                  trafficDenied = true;
                }
              }),
        );
      }
      await Future.wait(extras);
      if (mounted) {
        setState(() {
          _repo = raw;
          _pulls = pulls;
          _contributors = contributors;
          _release = release;
          _weeklyCommits = weeklyCommits;
          _cloneTraffic = cloneTraffic;
          _viewTraffic = viewTraffic;
          _referrers = referrers;
          _trafficDenied = trafficDenied;
          _error = null;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.response?.statusCode == 404
              ? 'Repository not found or private.'
              : e.response?.statusCode == 403
              ? 'GitHub rate limit reached. Add a token in settings.'
              : 'Could not reach GitHub. ${e.message ?? ''}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load repository: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.w.theme;
    final repo = _repo;
    if (repo == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _error ?? 'Loading GitHub…',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.textSecondary),
          ),
        ),
      );
    }
    final metrics = <({String key, String label, String value, IconData icon})>[
      if (widget.w.option('showStars', true))
        (
          key: 'stars',
          label: 'Stars',
          value: _number(repo['stargazers_count']),
          icon: Icons.star_outline,
        ),
      if (widget.w.option('showForks', true))
        (
          key: 'forks',
          label: 'Forks',
          value: _number(repo['forks_count']),
          icon: Icons.fork_right,
        ),
      if (widget.w.option('showWatchers', true))
        (
          key: 'watchers',
          label: 'Watchers',
          value: _number(repo['subscribers_count'] ?? repo['watchers_count']),
          icon: Icons.visibility_outlined,
        ),
      if (widget.w.option('showIssues', true))
        (
          key: 'issues',
          label: 'Open issues',
          value: _number(
            (((repo['open_issues_count'] as num?)?.toInt() ?? 0) -
                    (_pulls ?? 0))
                .clamp(0, 0x7fffffff),
          ),
          icon: Icons.error_outline,
        ),
      if (widget.w.option('showPulls', true) && _pulls != null)
        (
          key: 'pulls',
          label: 'Open PRs',
          value: _number(_pulls),
          icon: Icons.merge_type,
        ),
      if (widget.w.option('showContributors', true) && _contributors != null)
        (
          key: 'contributors',
          label: 'Contributors',
          value: _number(_contributors),
          icon: Icons.people_outline,
        ),
      if (widget.w.option('showLanguage', true) && repo['language'] != null)
        (
          key: 'language',
          label: 'Language',
          value: '${repo['language']}',
          icon: Icons.code,
        ),
      if (widget.w.option('showRelease', false) && _release != null)
        (
          key: 'release',
          label: 'Latest release',
          value: '${_release!['tag_name'] ?? '—'}',
          icon: Icons.new_releases_outlined,
        ),
      if (widget.w.option('showUpdated', true))
        (
          key: 'updated',
          label: 'Last push',
          value: _relative(repo['pushed_at']),
          icon: Icons.update,
        ),
      if (widget.w.option('showLicense', false) &&
          repo['license']?['spdx_id'] != null)
        (
          key: 'license',
          label: 'Licence',
          value: '${repo['license']['spdx_id']}',
          icon: Icons.policy_outlined,
        ),
      if (widget.w.option('showSize', false))
        (
          key: 'size',
          label: 'Size',
          value:
              '${((repo['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} MB',
          icon: Icons.storage_outlined,
        ),
      if (widget.w.option('showBranch', false))
        (
          key: 'branch',
          label: 'Default branch',
          value: '${repo['default_branch'] ?? '—'}',
          icon: Icons.account_tree_outlined,
        ),
      if (widget.w.option('showClones', true) && _cloneTraffic != null) ...[
        (
          key: 'clones',
          label: 'Clones · 14d',
          value: _number(_cloneTraffic!['count']),
          icon: Icons.download_outlined,
        ),
        (
          key: 'unique-clones',
          label: 'Unique clones',
          value: _number(_cloneTraffic!['uniques']),
          icon: Icons.person_outline,
        ),
      ],
      if (widget.w.option('showVisitors', true) && _viewTraffic != null) ...[
        (
          key: 'views',
          label: 'Views · 14d',
          value: _number(_viewTraffic!['count']),
          icon: Icons.visibility_outlined,
        ),
        (
          key: 'unique-visitors',
          label: 'Unique visitors',
          value: _number(_viewTraffic!['uniques']),
          icon: Icons.person_outline,
        ),
      ],
      if (widget.w.option('showReferrers', true))
        for (var i = 0; i < _referrers.take(3).length; i++)
          (
            key: 'referrer-$i',
            label: 'Referrer · ${_referrers[i]['referrer'] ?? 'Unknown'}',
            value:
                '${_number(_referrers[i]['count'])} / ${_number(_referrers[i]['uniques'])} unique',
            icon: Icons.open_in_new,
          ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final tiny = c.maxWidth < 100 || c.maxHeight < 100;
        final cols = c.maxWidth < 150
            ? 1
            : c.maxWidth < 280
            ? 2
            : c.maxWidth < 500
            ? 3
            : 4;
        final title = '${repo['full_name'] ?? _repository}';
        final showChart =
            widget.w.option('showCommitChart', true) &&
            _weeklyCommits.isNotEmpty &&
            c.maxWidth >= 220 &&
            c.maxHeight >= 190;
        final description = repo['description'] != null && c.maxHeight > 170;
        final chart = _CommitChart(weeks: _weeklyCommits, theme: theme);
        final stats = LayoutBuilder(
          builder: (context, grid) {
            final rows = (metrics.length / cols).ceil().clamp(1, 99);
            final cellWidth = grid.maxWidth / cols;
            final cellHeight = grid.maxHeight / rows;
            return GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: cellWidth / cellHeight,
                crossAxisSpacing: 5,
                mainAxisSpacing: 4,
              ),
              itemCount: metrics.length,
              itemBuilder: (context, i) =>
                  _Metric(metric: metrics[i], theme: theme),
            );
          },
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.code, color: theme.accent, size: tiny ? 16 : 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: tiny
                          ? 11
                          : (c.maxHeight * .05).clamp(13.0, 26.0),
                    ),
                  ),
                ),
                if (_busy)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.accent,
                    ),
                  ),
              ],
            ),
            if (tiny)
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${metrics.isEmpty ? '—' : metrics.first.value} ${metrics.isEmpty ? '' : metrics.first.label}',
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              )
            else ...[
              if (description)
                Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 4),
                  child: Text(
                    '${repo['description']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: (c.maxHeight * .028).clamp(12.0, 18.0),
                    ),
                  ),
                ),
              if (_trafficDenied &&
                  (widget.w.option('showClones', true) ||
                      widget.w.option('showVisitors', true) ||
                      widget.w.option('showReferrers', true)))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Traffic needs a token with repository Administration read access.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textSecondary, fontSize: 9),
                  ),
                ),
              if (!showChart)
                Expanded(child: stats)
              else if (c.maxWidth > c.maxHeight * 1.45)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: stats),
                      const SizedBox(width: 10),
                      Expanded(flex: 6, child: chart),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      Expanded(flex: 3, child: stats),
                      const SizedBox(height: 6),
                      Expanded(flex: 2, child: chart),
                    ],
                  ),
                ),
              if (widget.w.option('showTopics', true) &&
                  (repo['topics'] as List? ?? const []).isNotEmpty &&
                  c.maxHeight > 220)
                Text(
                  (repo['topics'] as List).take(5).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textSecondary, fontSize: 11),
                ),
            ],
          ],
        );
      },
    );
  }

  static String _number(Object? n) {
    final value = (n as num?)?.toInt() ?? 0;
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}m';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }

  static int _countFromResponse(Response<dynamic> response) {
    final link = response.headers.value('link') ?? '';
    final last = RegExp(
      r'<[^>]*[?&]page=(\d+)[^>]*>;\s*rel="last"',
    ).firstMatch(link);
    if (last != null) return int.tryParse(last.group(1)!) ?? 0;
    return response.data is List ? (response.data as List).length : 0;
  }

  static String _relative(Object? raw) {
    final d = DateTime.tryParse('$raw')?.toLocal();
    if (d == null) return '—';
    final age = DateTime.now().difference(d);
    if (age.inDays > 365) return '${age.inDays ~/ 365}y ago';
    if (age.inDays > 30) return '${age.inDays ~/ 30}mo ago';
    if (age.inDays > 0) return '${age.inDays}d ago';
    if (age.inHours > 0) return '${age.inHours}h ago';
    return 'Today';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.metric, required this.theme});
  final ({String key, String label, String value, IconData icon}) metric;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Size each label and figure from the actual grid cell. The old fixed
      // 10/17 px sizes were then shrunk by FittedBox to fit the grid's overly
      // tall cells, making a large dashboard tile look like a small one.
      final labelSize = (c.maxHeight * .19).clamp(11.0, 18.0);
      final valueSize = (c.maxHeight * .40).clamp(18.0, 44.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: labelSize, color: theme.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: labelSize,
                  ),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              maxLines: 1,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: valueSize,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Recent weekly commit counts. GitHub's commit activity endpoint returns up
/// to 52 weeks; this chart keeps the last 12 so its labels remain readable.
class _CommitChart extends StatelessWidget {
  const _CommitChart({required this.weeks, required this.theme});

  final List<int> weeks;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final recent = weeks.length > 12 ? weeks.sublist(weeks.length - 12) : weeks;
    final total = recent.fold<int>(0, (sum, count) => sum + count);
    return LayoutBuilder(
      builder: (context, c) {
        final titleSize = (c.maxHeight * .10).clamp(12.0, 22.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly commits',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$total · 12w',
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: (titleSize * .72).clamp(10.0, 16.0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: CustomPaint(
                painter: _CommitChartPainter(values: recent, theme: theme),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CommitChartPainter extends CustomPainter {
  const _CommitChartPainter({required this.values, required this.theme});
  final List<int> values;
  final DashboardTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 35 || values.isEmpty) return;
    final fontSize = (size.shortestSide * .05).clamp(11.0, 17.0);
    final left = fontSize * 2.6;
    const top = 4.0;
    const bottom = 18.0;
    final chartWidth = size.width - left - 3;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    final ceiling = maxValue == 0 ? 1.0 : maxValue.toDouble();
    final gridPaint = Paint()
      ..color = theme.textSecondary.withValues(alpha: .22)
      ..strokeWidth = 1;
    final barPaint = Paint()
      ..color = theme.accent.withValues(alpha: .78)
      ..style = PaintingStyle.fill;
    final lastBarPaint = Paint()
      ..color = theme.accent
      ..style = PaintingStyle.fill;

    for (var tick = 0; tick <= 2; tick++) {
      final y = top + chartHeight * tick / 2;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final label = (ceiling * (1 - tick / 2)).round().toString();
      _drawLabel(
        canvas,
        label,
        Offset(0, y - fontSize / 2),
        fontSize,
        theme.textSecondary,
        maxWidth: left - 4,
      );
    }

    final slot = chartWidth / values.length;
    final barWidth = (slot * .64).clamp(2.0, 18.0);
    for (var i = 0; i < values.length; i++) {
      final barHeight = chartHeight * values[i] / ceiling;
      final x = left + slot * i + (slot - barWidth) / 2;
      final rect = Rect.fromLTWH(
        x,
        top + chartHeight - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        i == values.length - 1 ? lastBarPaint : barPaint,
      );
    }
    _drawLabel(
      canvas,
      '12w ago',
      Offset(left, size.height - bottom + 3),
      fontSize,
      theme.textSecondary,
    );
    _drawLabel(
      canvas,
      'Now',
      Offset(size.width - fontSize * 2.4, size.height - bottom + 3),
      fontSize,
      theme.textSecondary,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color, {
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CommitChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.theme != theme;
}

final githubWidgetType = DashboardWidgetType(
  type: 'github',
  category: WidgetCategory.homeLab,
  name: 'GitHub repository',
  description: 'Repository activity and stats from GitHub.',
  glyph: '🐙',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'repositories',
      label: 'Repositories',
      kind: OptionKind.list,
      addLabel: 'Add repository',
      help:
          'Add one row per repository tab. Every repository uses the same token and display settings.',
      fields: [
        WidgetOption(
          key: 'name',
          label: 'Tab name (optional)',
          defaultValue: '',
          help:
              'Shown along the bottom of the widget. Defaults to owner/repository.',
        ),
        WidgetOption(
          key: 'repository',
          label: 'Repository URL or owner/name',
          defaultValue: '',
        ),
      ],
    ),
    WidgetOption(
      key: 'repository',
      label: 'Older single-repository setting',
      defaultValue: '',
      help:
          'Kept for dashboards saved before repository tabs. It still appears as a tab; add all repositories in the list above.',
    ),
    WidgetOption(
      key: 'token',
      label: 'Personal access token',
      kind: OptionKind.secret,
      defaultValue: '',
      help:
          'Optional. Needed for private repositories. Traffic stats require repository Administration read access.',
    ),
    WidgetOption(
      key: 'refreshMinutes',
      label: 'Refresh interval',
      kind: OptionKind.choice,
      defaultValue: '30',
      choices: {
        '5': '5 minutes',
        '15': '15 minutes',
        '30': '30 minutes',
        '60': '1 hour',
        '240': '4 hours',
      },
    ),
    WidgetOption(
      key: 'showStars',
      label: 'Stars',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showForks',
      label: 'Forks',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showWatchers',
      label: 'Watchers',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showIssues',
      label: 'Open issues',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showPulls',
      label: 'Open pull requests',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showContributors',
      label: 'Contributors',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showLanguage',
      label: 'Primary language',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showUpdated',
      label: 'Last push',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showTopics',
      label: 'Topics',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'showCommitChart',
      label: 'Weekly commit chart',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Shows GitHub commit activity for the last 12 weeks when the tile is large enough.',
    ),
    WidgetOption(
      key: 'showClones',
      label: 'Clones and unique clones',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Git clones over the last 14 days. Requires repository Administration read access.',
    ),
    WidgetOption(
      key: 'showVisitors',
      label: 'Views and unique visitors',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Repository views over the last 14 days. Requires repository Administration read access.',
    ),
    WidgetOption(
      key: 'showReferrers',
      label: 'Referring sites',
      kind: OptionKind.boolean,
      defaultValue: true,
      help:
          'Top referring sites over the last 14 days. Requires repository Administration read access.',
    ),
    WidgetOption(
      key: 'showRelease',
      label: 'Latest release',
      kind: OptionKind.boolean,
      defaultValue: false,
    ),
    WidgetOption(
      key: 'showLicense',
      label: 'Licence',
      kind: OptionKind.boolean,
      defaultValue: false,
    ),
    WidgetOption(
      key: 'showSize',
      label: 'Repository size',
      kind: OptionKind.boolean,
      defaultValue: false,
    ),
    WidgetOption(
      key: 'showBranch',
      label: 'Default branch',
      kind: OptionKind.boolean,
      defaultValue: false,
    ),
  ],
  preview: const [
    PreviewLine('🐙 owner/repository', scale: .16, accent: true),
    PreviewLine('★ 1.2k ⑂ 84  Issues 12', scale: .12, muted: true),
  ],
  build: (context, w) => GithubWidget(w: w),
);
