import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../l10n/l10n.dart';
import '../../services/github_api.dart';
import '../../widgets/pause_when_hidden.dart';
import '../../widgets/shown_timers.dart';
import '../dashboard_theme.dart';
import '../widget_registry.dart';
import 'tile_bits.dart';

/// One or more GitHub repositories: stars, issues, pull requests, releases,
/// a weekly commit chart and — with a token — who is visiting. Several
/// repositories get a tab each along the bottom.
class GithubWidget extends StatelessWidget {
  const GithubWidget({super.key, required this.w});
  final DashboardWidgetContext w;

  /// Each repository once, as `owner/name`, with its tab's name. What can't
  /// be read as a repository is kept as typed, so the tile can say so.
  List<({String repository, String label, bool valid})> get _repositories {
    final unique = <String, ({String repository, String label, bool valid})>{};
    void add(String value, {String label = ''}) {
      final typed = value.trim();
      if (typed.isEmpty) return;
      final parsed = parseRepository(typed);
      final repository = parsed ?? typed;
      final key = repository.toLowerCase();
      final previous = unique[key];
      unique[key] = (
        repository: repository,
        label: label.trim().isNotEmpty ? label.trim() : previous?.label ?? '',
        valid: parsed != null,
      );
    }

    // The original single-repository setting, for dashboards saved before
    // the list; new ones are managed in the list.
    add(w.option('repository', ''));
    for (final row in w.rows('repositories')) {
      add('${row['repository'] ?? ''}', label: '${row['name'] ?? ''}');
    }
    return unique.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final repositories = _repositories;
    if (repositories.isEmpty) {
      return TileMessage(
        tr(
          'widget.github.addRepository',
          'Add a repository in the widget settings — its address, or '
              'owner/name.',
        ),
        theme: w.theme,
      );
    }
    if (repositories.length == 1) {
      final only = repositories.first;
      return _GithubRepositoryTile(
        key: ValueKey(only.repository),
        w: w,
        repository: only.repository,
        valid: only.valid,
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
                  // Tabs change on a tap only: a swipe here belongs to the
                  // dashboard, which turns its pages that way.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final entry in repositories)
                      _GithubRepositoryTile(
                        key: ValueKey(entry.repository),
                        w: w,
                        repository: entry.repository,
                        valid: entry.valid,
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

typedef _Metric = ({String key, String label, String value, IconData icon});

class _GithubRepositoryTile extends StatefulWidget {
  const _GithubRepositoryTile({
    super.key,
    required this.w,
    required this.repository,
    required this.valid,
  });
  final DashboardWidgetContext w;
  final String repository;

  /// Whether [repository] could be read as owner/name at all.
  final bool valid;

  @override
  State<_GithubRepositoryTile> createState() => _GithubRepositoryTileState();
}

class _GithubRepositoryTileState extends State<_GithubRepositoryTile>
    with PauseWhenHidden, ShownTimers {
  static final _api = GithubApi();

  GithubSnapshot? _data;
  GithubFailure? _failure;
  bool _busy = false;
  Timer? _timer;

  /// Bumped whenever what is asked for changes, so an answer to an older
  /// question — another repository, another token — is thrown away when it
  /// lands rather than shown.
  int _generation = 0;

  String get _token => widget.w.option('token', '').trim();

  GithubWanted get _wanted {
    final w = widget.w;
    return GithubWanted(
      pulls: w.option('showPulls', true) || w.option('showIssues', true),
      contributors: w.option('showContributors', true),
      release: w.option('showRelease', false),
      commits: w.option('showCommitChart', true),
      clones: w.option('showClones', true),
      views: w.option('showVisitors', true),
      referrers: w.option('showReferrers', true),
    );
  }

  static const _fetchOptions = [
    'showPulls',
    'showIssues',
    'showContributors',
    'showRelease',
    'showCommitChart',
    'showClones',
    'showVisitors',
    'showReferrers',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _GithubRepositoryTile old) {
    super.didUpdateWidget(old);
    final asked = widget.repository != old.repository ||
        _token != old.w.option('token', '').trim();
    if (asked) {
      _data = null;
      _failure = null;
    }
    if (asked ||
        _fetchOptions.any(
          (o) => widget.w.config.options[o] != old.w.config.options[o],
        )) {
      _generation++;
      unawaited(_load(force: true));
    }
    if (widget.w.config.options['refreshMinutes'] !=
        old.w.config.options['refreshMinutes']) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final minutes =
        (int.tryParse('${widget.w.config.options['refreshMinutes'] ?? 30}') ??
                30)
            .clamp(5, 240);
    // Paused while the tile is off screen or the screen is dark, and caught
    // up once it's shown again.
    _timer = everyWhileShown(Duration(minutes: minutes), () {
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// With [force], runs even while another fetch is out — that one's answer
  /// will be to an older question and is dropped.
  Future<void> _load({bool force = false}) async {
    if (!widget.valid || (_busy && !force)) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final data = await _api.fetch(
        widget.repository,
        token: _token,
        want: _wanted,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _failure = null;
      });
    } on GithubException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _failure = e.failure);
    } catch (e) {
      debugPrint('GitHub ${widget.repository}: $e');
      if (!mounted || generation != _generation) return;
      setState(() => _failure = GithubFailure.unexpected);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  String _failureText(GithubFailure f) => switch (f) {
    GithubFailure.notFound => tr(
      'widget.github.notFound',
      'No repository {repository} — or it is private, and needs a token.',
      {'repository': widget.repository},
    ),
    GithubFailure.badToken => tr(
      'widget.github.badToken',
      'GitHub did not accept the token. Check it in the widget settings.',
    ),
    GithubFailure.rateLimited => tr(
      'widget.github.rateLimited',
      'GitHub’s hourly limit is used up. A token raises it — add one in '
          'the widget settings.',
    ),
    GithubFailure.forbidden => tr(
      'widget.github.forbidden',
      'The token can’t see {repository}.',
      {'repository': widget.repository},
    ),
    GithubFailure.unreachable => tr(
      'widget.github.unreachable',
      'Could not reach GitHub',
    ),
    GithubFailure.unexpected => tr(
      'widget.github.unexpected',
      'GitHub gave an answer the tile didn’t understand',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = widget.w.theme;
    if (!widget.valid) {
      return TileMessage(
        tr(
          'widget.github.notARepository',
          '“{typed}” isn’t a repository. Use its address, or owner/name.',
          {'typed': widget.repository},
        ),
        theme: theme,
      );
    }
    final data = _data;
    if (data == null) {
      return TileMessage(
        _failure != null
            ? _failureText(_failure!)
            : tr('widget.github.loading', 'Asking GitHub…'),
        theme: theme,
      );
    }
    final repo = data.repo;
    final metrics = _metrics(data);
    final status = StatusColours.of(theme);
    final badges = [
      if (repo['archived'] == true)
        (tr('widget.github.archived', 'Archived'), status.warn),
      if (repo['private'] == true)
        (tr('widget.github.private', 'Private'), theme.textSecondary),
      if (repo['fork'] == true)
        (tr('widget.github.fork', 'Fork'), theme.textSecondary),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final tiny = c.maxWidth < 100 || c.maxHeight < 100;
        final title = '${repo['full_name'] ?? widget.repository}';
        final headSize = tiny ? 11.0 : (c.maxHeight * .05).clamp(13.0, 26.0);
        final showChart =
            widget.w.option('showCommitChart', true) &&
            data.weeklyCommits.isNotEmpty &&
            c.maxWidth >= 220 &&
            c.maxHeight >= 190;
        final description =
            '${repo['description'] ?? ''}'.trim().isNotEmpty &&
            c.maxHeight > 170;
        final chart = _CommitChart(weeks: data.weeklyCommits, theme: theme);
        final stats = LayoutBuilder(
          builder: (context, grid) {
            // From the room the figures actually get — beside the chart
            // that is about half the tile — so labels aren't cut short.
            final cols = grid.maxWidth < 150
                ? 1
                : grid.maxWidth < 280
                ? 2
                : grid.maxWidth < 500
                ? 3
                : 4;
            // As many figures as can be read, in the order they are listed,
            // rather than all of them shrunk past reading.
            final fit = (grid.maxHeight / 44).floor().clamp(1, 99);
            final shown = metrics.take(cols * fit).toList();
            final rows = (shown.length / cols).ceil().clamp(1, 99);
            return GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio:
                    (grid.maxWidth / cols) / (grid.maxHeight / rows),
                crossAxisSpacing: 5,
                mainAxisSpacing: 4,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) =>
                  _MetricCell(metric: shown[i], theme: theme),
            );
          },
        );
        final wantsTraffic = widget.w.option('showClones', true) ||
            widget.w.option('showVisitors', true) ||
            widget.w.option('showReferrers', true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, color: theme.accent, size: headSize * 1.2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: headSize,
                    ),
                  ),
                ),
                // Beside the name only where there's room for both.
                if (!tiny && c.maxWidth >= 260)
                  for (final (text, colour) in badges) ...[
                    const SizedBox(width: 6),
                    StatusChip(text: text, colour: colour, size: headSize * .6),
                  ],
                // Older figures on show: the last refresh failed.
                if (_failure != null && !_busy) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: _failureText(_failure!),
                    child: Icon(
                      Icons.cloud_off_outlined,
                      size: headSize * .9,
                      color: status.warn,
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.accent,
                    ),
                  ),
                ],
              ],
            ),
            if (tiny)
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      metrics.isEmpty
                          ? '—'
                          : '${metrics.first.value} ${metrics.first.label}',
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
              if (data.trafficDenied && wantsTraffic)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    tr(
                      'widget.github.trafficNeedsAccess',
                      'Traffic needs a token with the repository’s '
                          'Administration read access.',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.textSecondary, fontSize: 11),
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

  List<_Metric> _metrics(GithubSnapshot data) {
    final w = widget.w;
    final repo = data.repo;
    // GitHub counts pull requests as issues. With the PR count known, the
    // issues shown are issues alone; without it, the figure says so.
    final openAll = (repo['open_issues_count'] as num?)?.toInt() ?? 0;
    final pulls = data.pulls;
    final license = '${(repo['license'] as Map?)?['spdx_id'] ?? ''}';
    return [
      if (w.option('showStars', true))
        (
          key: 'stars',
          label: tr('widget.github.stars', 'Stars'),
          value: _count(repo['stargazers_count']),
          icon: Icons.star_outline,
        ),
      if (w.option('showForks', true))
        (
          key: 'forks',
          label: tr('widget.github.forks', 'Forks'),
          value: _count(repo['forks_count']),
          icon: Icons.fork_right,
        ),
      if (w.option('showWatchers', true))
        (
          key: 'watchers',
          label: tr('widget.github.watchers', 'Watchers'),
          value: _count(repo['subscribers_count'] ?? repo['watchers_count']),
          icon: Icons.visibility_outlined,
        ),
      if (w.option('showIssues', true))
        pulls == null
            ? (
                key: 'issues',
                label: tr('widget.github.issuesAndPulls', 'Issues and PRs'),
                value: _count(openAll),
                icon: Icons.error_outline,
              )
            : (
                key: 'issues',
                label: tr('widget.github.openIssues', 'Open issues'),
                value: _count((openAll - pulls).clamp(0, openAll)),
                icon: Icons.error_outline,
              ),
      if (w.option('showPulls', true) && pulls != null)
        (
          key: 'pulls',
          label: tr('widget.github.openPulls', 'Open PRs'),
          value: _count(pulls),
          icon: Icons.merge_type,
        ),
      if (w.option('showContributors', true) && data.contributors != null)
        (
          key: 'contributors',
          label: tr('widget.github.contributors', 'Contributors'),
          value: _count(data.contributors),
          icon: Icons.people_outline,
        ),
      if (w.option('showLanguage', true) && repo['language'] != null)
        (
          key: 'language',
          label: tr('widget.github.language', 'Language'),
          value: '${repo['language']}',
          icon: Icons.code,
        ),
      if (w.option('showRelease', false) && data.release != null)
        (
          key: 'release',
          label: tr('widget.github.latestRelease', 'Latest release'),
          value: '${data.release!['tag_name'] ?? '—'}',
          icon: Icons.new_releases_outlined,
        ),
      if (w.option('showUpdated', true))
        (
          key: 'updated',
          label: tr('widget.github.lastPush', 'Last push'),
          value: _ago(repo['pushed_at']),
          icon: Icons.update,
        ),
      // "NOASSERTION" is GitHub's way of saying it couldn't tell.
      if (w.option('showLicense', false) &&
          license.isNotEmpty &&
          license != 'NOASSERTION')
        (
          key: 'license',
          label: tr('widget.github.licence', 'Licence'),
          value: license,
          icon: Icons.policy_outlined,
        ),
      if (w.option('showSize', false))
        (
          key: 'size',
          label: tr('widget.github.size', 'Size'),
          // GitHub gives it in kilobytes.
          value: tr('widget.github.megabytes', '{size} MB', {
            'size': ((repo['size'] as num? ?? 0) / 1024).toStringAsFixed(1),
          }),
          icon: Icons.storage_outlined,
        ),
      if (w.option('showBranch', false))
        (
          key: 'branch',
          label: tr('widget.github.defaultBranch', 'Default branch'),
          value: '${repo['default_branch'] ?? '—'}',
          icon: Icons.account_tree_outlined,
        ),
      if (w.option('showClones', true) && data.clones != null) ...[
        (
          key: 'clones',
          label: tr('widget.github.clones', 'Clones · 14 days'),
          value: _count(data.clones!['count']),
          icon: Icons.download_outlined,
        ),
        (
          key: 'unique-clones',
          label: tr('widget.github.uniqueClones', 'Unique cloners'),
          value: _count(data.clones!['uniques']),
          icon: Icons.person_outline,
        ),
      ],
      if (w.option('showVisitors', true) && data.views != null) ...[
        (
          key: 'views',
          label: tr('widget.github.views', 'Views · 14 days'),
          value: _count(data.views!['count']),
          icon: Icons.visibility_outlined,
        ),
        (
          key: 'unique-visitors',
          label: tr('widget.github.uniqueVisitors', 'Unique visitors'),
          value: _count(data.views!['uniques']),
          icon: Icons.person_outline,
        ),
      ],
      if (w.option('showReferrers', true))
        for (final (i, r) in data.referrers.take(3).indexed)
          (
            key: 'referrer-$i',
            label: tr('widget.github.referrer', 'From {site}', {
              'site': '${r['referrer'] ?? '?'}',
            }),
            value: tr('widget.github.referrerCounts', '{count} · {uniques} unique', {
              'count': _count(r['count']),
              'uniques': _count(r['uniques']),
            }),
            icon: Icons.open_in_new,
          ),
    ];
  }

  /// "1.2K", "34", "2.1M" — shortened in the panel's language's style.
  static String _count(Object? n) {
    final value = (n as num?) ?? 0;
    if (value < 1000) return '${value.toInt()}';
    try {
      return NumberFormat.compact(
        locale: L10n.instance.language.intlCode,
      ).format(value);
    } catch (_) {
      return NumberFormat.compact(locale: 'en_GB').format(value);
    }
  }

  /// "3y ago", "5mo ago", "2d ago", "4h ago", "Just now" — short enough for
  /// a cell.
  static String _ago(Object? raw) {
    final d = DateTime.tryParse('$raw')?.toLocal();
    if (d == null) return '—';
    final age = DateTime.now().difference(d);
    if (age.inDays >= 365) {
      return tr('widget.github.yearsAgo', '{n}y ago', {'n': age.inDays ~/ 365});
    }
    if (age.inDays >= 30) {
      return tr('widget.github.monthsAgo', '{n}mo ago', {'n': age.inDays ~/ 30});
    }
    if (age.inDays > 0) {
      return tr('widget.github.daysAgo', '{n}d ago', {'n': age.inDays});
    }
    if (age.inHours > 0) {
      return tr('widget.github.hoursAgo', '{n}h ago', {'n': age.inHours});
    }
    return tr('widget.github.justNow', 'Just now');
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, required this.theme});
  final _Metric metric;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Sized from the actual grid cell, so a large tile reads as large.
      final labelSize = (c.maxHeight * .19).clamp(11.0, 18.0);
      final valueSize = (c.maxHeight * .40).clamp(18.0, 44.0);
      // Shrinks whole in a cell too short for its smallest type.
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: c.maxWidth,
          child: Column(
        mainAxisSize: MainAxisSize.min,
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
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
          ),
        ),
      );
    },
  );
}

/// The last twelve weeks of commits. GitHub keeps a year; twelve bars stay
/// readable on a tile.
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
                    tr('widget.github.weeklyCommits', 'Weekly commits'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Gives way to the heading on a narrow chart.
                Flexible(
                  child: Text(
                    tr(
                      'widget.github.commitsTotal',
                      '{n, plural, one{# commit} other{# commits}} · 12 weeks',
                      {'n': total},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: (titleSize * .72).clamp(10.0, 16.0),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: CustomPaint(
                painter: _CommitChartPainter(
                  values: recent,
                  theme: theme,
                  start: tr('widget.github.twelveWeeksAgo', '12 weeks ago'),
                  end: tr('widget.github.thisWeek', 'This week'),
                ),
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
  const _CommitChartPainter({
    required this.values,
    required this.theme,
    required this.start,
    required this.end,
  });
  final List<int> values;
  final DashboardTheme theme;

  /// The labels under its first and last bars.
  final String start;
  final String end;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 35 || values.isEmpty) return;
    final fontSize = (size.shortestSide * .05).clamp(11.0, 17.0);
    final left = fontSize * 2.6;
    const top = 4.0;
    final bottom = fontSize + 6;
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
    // This week, still filling up, in full colour.
    final lastBarPaint = Paint()
      ..color = theme.accent
      ..style = PaintingStyle.fill;

    for (var tick = 0; tick <= 2; tick++) {
      final y = top + chartHeight * tick / 2;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      _label(
        canvas,
        (ceiling * (1 - tick / 2)).round().toString(),
        Offset(0, y - fontSize / 2),
        fontSize,
        maxWidth: left - 4,
      );
    }

    final slot = chartWidth / values.length;
    final barWidth = (slot * .64).clamp(2.0, 18.0);
    for (var i = 0; i < values.length; i++) {
      final barHeight = chartHeight * values[i] / ceiling;
      final x = left + slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + chartHeight - barHeight, barWidth, barHeight),
          const Radius.circular(2),
        ),
        i == values.length - 1 ? lastBarPaint : barPaint,
      );
    }
    final y = size.height - bottom + 3;
    final startWidth = _label(canvas, start, Offset(left, y), fontSize);
    // Right-aligned, and only where it clears the first label.
    final endPainter = _painter(end, fontSize);
    final endX = size.width - endPainter.width;
    if (endX > left + startWidth + 8) {
      endPainter.paint(canvas, Offset(endX, y));
    }
  }

  TextPainter _painter(String text, double fontSize, {double? maxWidth}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, color: theme.textSecondary),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: maxWidth ?? double.infinity);

  /// Paints [text] at [offset]; returns its width.
  double _label(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize, {
    double? maxWidth,
  }) {
    final p = _painter(text, fontSize, maxWidth: maxWidth);
    p.paint(canvas, offset);
    return p.width;
  }

  @override
  bool shouldRepaint(covariant _CommitChartPainter old) =>
      old.values != values ||
      old.theme != theme ||
      old.start != start ||
      old.end != end;
}

final githubWidgetType = DashboardWidgetType(
  type: 'github',
  category: WidgetCategory.homeLab,
  name: 'GitHub repository',
  description:
      'Stars, issues, pull requests, releases and a weekly commit chart for '
      'your GitHub repositories — a tab each — and, with a token, who has '
      'been visiting. No token needed for public ones.',
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
          'One row per repository, each a tab along the bottom. Its address '
          '(github.com/owner/name) or just owner/name. They all share the '
          'token and the settings below.',
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
          'Optional. Needed for private repositories and traffic, and it '
          'raises GitHub’s limit from 60 requests an hour. A fine-grained '
          'token with read-only access is enough: Metadata, plus '
          'Administration for traffic. Sent only to api.github.com.',
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
    PreviewLine('owner/repository', scale: .14, accent: true),
    PreviewLine('Stars 1.2K   Forks 84   Issues 12', scale: .11),
    PreviewLine('▁▂▄▃▅▆▄▇', scale: .16, centre: true),
  ],
  build: (context, w) => GithubWidget(w: w),
);
