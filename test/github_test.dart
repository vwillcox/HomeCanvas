import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/github_api.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

void main() {
  tearDown(() => GithubApi.debugFetch = null);

  group('a repository, from whatever was typed or pasted', () {
    test('addresses, clone links and links inside a repository', () {
      for (final typed in [
        'vwillcox/HomeCanvas',
        'https://github.com/vwillcox/HomeCanvas',
        'http://www.github.com/vwillcox/HomeCanvas/',
        'github.com/vwillcox/HomeCanvas',
        'https://github.com/vwillcox/HomeCanvas.git',
        'git@github.com:vwillcox/HomeCanvas.git',
        'https://github.com/vwillcox/HomeCanvas/tree/main/lib',
        'https://github.com/vwillcox/HomeCanvas?tab=readme#top',
        '  vwillcox/HomeCanvas  ',
      ]) {
        expect(parseRepository(typed), 'vwillcox/HomeCanvas', reason: typed);
      }
      expect(parseRepository('flutter/flutter.github.io'),
          'flutter/flutter.github.io');
    });

    test('nothing that could reach another part of the API', () {
      for (final typed in [
        '',
        'justone',
        '../..',
        'owner/..',
        'owner/.',
        'owner/name?x=1&y',
        'a b/c',
        '-owner/name',
        'owner/na%2Fme',
        'https://evil.example/owner/name',
      ]) {
        final got = parseRepository(typed);
        if (got != null) {
          // Only ever exactly one owner and one name, in GitHub's alphabet.
          expect(got, matches(RegExp(r'^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$')),
              reason: typed);
          expect(got.split('/').last, isNot(anyOf('.', '..')), reason: typed);
        }
      }
      expect(parseRepository('../..'), isNull);
      expect(parseRepository('owner/..'), isNull);
      expect(parseRepository('a b/c'), isNull);
      expect(parseRepository('owner/na%2Fme'), isNull);
    });
  });

  test('a paged list is counted from its last page', () {
    expect(
      countFromLink(
        '<https://api.github.com/repositories/1/pulls?state=open&per_page=1&page=2>; rel="next", '
        '<https://api.github.com/repositories/1/pulls?state=open&per_page=1&page=37>; rel="last"',
        [{}],
      ),
      37,
    );
    expect(countFromLink(null, [{}]), 1);
    expect(countFromLink(null, []), 0);
  });

  test('a 403 is a rate limit only when none are left', () {
    DioException failed(int code, [Map<String, List<String>> h = const {}]) =>
        DioException(
          requestOptions: RequestOptions(),
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: code,
            headers: Headers.fromMap(h),
          ),
        );
    expect(classify(failed(404)), GithubFailure.notFound);
    expect(classify(failed(401)), GithubFailure.badToken);
    expect(
      classify(failed(403, {
        'x-ratelimit-remaining': ['0'],
      })),
      GithubFailure.rateLimited,
    );
    expect(
      classify(failed(403, {
        'x-ratelimit-remaining': ['4999'],
      })),
      GithubFailure.forbidden,
    );
    expect(classify(failed(429)), GithubFailure.rateLimited);
    expect(classify(DioException(requestOptions: RequestOptions())),
        GithubFailure.unreachable);
  });

  group('tiles', () {
    setUpAll(registerBuiltInWidgets);

    GithubSnapshot snapshot(String repo) => GithubSnapshot(
      repo: {
        'full_name': repo,
        'description': 'A touchscreen photo frame and home dashboard',
        'stargazers_count': 1234,
        'forks_count': 84,
        'subscribers_count': 9,
        'open_issues_count': 15,
        'language': 'Dart',
        'pushed_at': DateTime.now()
            .subtract(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
        'topics': ['flutter', 'raspberry-pi', 'kiosk'],
        'archived': true,
      },
      pulls: 3,
      contributors: 4,
      weeklyCommits: [for (var i = 0; i < 52; i++) i % 9],
      clones: {'count': 40, 'uniques': 17},
      views: {'count': 900, 'uniques': 310},
      referrers: [
        {'referrer': 'news.ycombinator.com', 'count': 120, 'uniques': 88},
      ],
    );

    Future<void> draw(
      WidgetTester tester,
      Size size,
      Map<String, dynamic> options,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find('github')!;
      final w = DashboardWidgetContext(
        theme: kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 'g',
          type: 'github',
          x: 0,
          y: 0,
          width: 4,
          height: 3,
          options: options,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: Builder(builder: (context) => t.build(context, w)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('one repository and several fit every tile shape',
        (tester) async {
      GithubApi.debugFetch = (repo, token, want) async => snapshot(repo);
      for (final options in [
        {'repository': 'vwillcox/HomeCanvas', 'token': 't'},
        {
          'token': 't',
          'repositories': [
            {'name': 'Panel', 'repository': 'vwillcox/HomeCanvas'},
            {'name': '', 'repository': 'https://github.com/flutter/flutter'},
          ],
        },
      ]) {
        for (final (w, h) in shapes) {
          await draw(tester, tile(w, h), options);
          expect(tester.takeException(), isNull, reason: '$options ${w}x$h');
        }
      }
      await draw(tester, tile(6, 4), {'repository': 'vwillcox/HomeCanvas'});
      expect(find.text('vwillcox/HomeCanvas'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      // 15 open, 3 of them pull requests.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Open issues'), findsOneWidget);
    });

    testWidgets('what isn\'t a repository says so, and asks for nothing',
        (tester) async {
      var asked = 0;
      GithubApi.debugFetch = (repo, token, want) async {
        asked++;
        return snapshot(repo);
      };
      await draw(tester, tile(4, 3), {'repository': '../..'});
      expect(find.textContaining('isn’t a repository'), findsOneWidget);
      expect(asked, 0);
    });

    testWidgets('an answer to an older question is dropped', (tester) async {
      final slow = Completer<GithubSnapshot>();
      GithubApi.debugFetch = (repo, token, want) =>
          token == 'old' ? slow.future : Future.value(snapshot('new/answer'));
      await draw(tester, tile(4, 3), {
        'repository': 'vwillcox/HomeCanvas',
        'token': 'old',
      });
      // The token changes while the first fetch is still out…
      await draw(tester, tile(4, 3), {
        'repository': 'vwillcox/HomeCanvas',
        'token': 'new',
      });
      expect(find.text('new/answer'), findsOneWidget);
      // …and its late answer doesn't replace the new one.
      slow.complete(snapshot('old/answer'));
      await tester.pump();
      expect(find.text('new/answer'), findsOneWidget);
      expect(find.text('old/answer'), findsNothing);
    });

    testWidgets('a failure explains itself', (tester) async {
      GithubApi.debugFetch = (repo, token, want) async =>
          throw const GithubException(GithubFailure.rateLimited);
      await draw(tester, tile(4, 3), {'repository': 'vwillcox/HomeCanvas'});
      expect(find.textContaining('hourly limit'), findsOneWidget);
    });
  });
}
