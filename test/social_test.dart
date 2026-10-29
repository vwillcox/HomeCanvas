import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/services/bluesky_api.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/mastodon_api.dart';
import 'package:home_canvas/services/share_inbox_service.dart';
import 'package:home_canvas/services/social.dart';
import 'package:home_canvas/services/social_notifier.dart';

import 'new_widgets_fit_test.dart' show shapes, tile;

/// Answers each request from [answer], and remembers what was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.answer);
  (int, Object) Function(RequestOptions o) answer;
  final asked = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _status({
  String id = '1',
  String content = '<p>Hello</p>',
  Map<String, dynamic>? reblog,
}) => {
  'id': id,
  'created_at': '2026-10-29T09:00:00.000Z',
  'content': content,
  'spoiler_text': '',
  'url': 'https://mastodon.social/@alice/$id',
  'account': {
    'username': 'alice',
    'acct': 'alice',
    'display_name': 'Alice :blobcat:',
    'avatar_static': '',
    'emojis': [
      {'shortcode': 'blobcat'},
    ],
  },
  'media_attachments': const [],
  'emojis': const [],
  'replies_count': 2,
  'reblogs_count': 3,
  'favourites_count': 4,
  'reblog': reblog,
};

const _alice = SocialPerson(name: 'Alice', handle: 'alice@mastodon.social');

SocialNotice _notice(String id, SocialNoticeKind kind, {DateTime? at}) =>
    SocialNotice(
      id: id,
      kind: kind,
      who: _alice,
      at: at,
      post: kind == SocialNoticeKind.follow
          ? null
          : SocialPost(id: 'p$id', author: _alice, text: 'Post $id'),
    );

class _FakeMastodon extends MastodonApi {
  List<SocialNotice> waiting = [];
  final since = <String?>[];

  @override
  Future<List<SocialNotice>> notices(
    MastodonAccount a, {
    String? sinceId,
    int limit = 30,
    bool mentionsOnly = false,
  }) async {
    since.add(sinceId);
    return [
      for (final n in waiting)
        if (sinceId == null || compareMastodonIds(n.id, sinceId) > 0) n,
    ];
  }
}

class _FakeBluesky extends BlueskyApi {
  List<SocialNotice> waiting = [];

  @override
  Future<List<SocialNotice>> notices(
    BlueskyAccount a, {
    int limit = 30,
    bool mentionsOnly = false,
  }) async => waiting;
}

void main() {
  group('a server, from whatever was typed', () {
    test('names, addresses and handles', () {
      for (final typed in [
        'mastodon.social',
        'https://mastodon.social',
        'https://mastodon.social/',
        'https://mastodon.social/@alice',
        '@alice@mastodon.social',
        'alice@mastodon.social',
        '  MASTODON.social ',
      ]) {
        expect(serverAddress(typed), 'https://mastodon.social', reason: typed);
      }
      expect(serverAddress('http://10.0.0.5:3000'), 'http://10.0.0.5:3000');
    });

    test('nothing that could send a token elsewhere', () {
      for (final typed in [
        '',
        'not a server',
        'mastodon.social@evil.example/x',
        'ftp://mastodon.social',
        'https://user:pass@mastodon.social',
        '-bad.example',
      ]) {
        expect(serverAddress(typed), isNull, reason: typed);
      }
    });
  });

  test('Mastodon ids compare as the numbers they are', () {
    expect(compareMastodonIds('110', '99'), greaterThan(0));
    expect(compareMastodonIds('99', '110'), lessThan(0));
    expect(compareMastodonIds('115', '114'), greaterThan(0));
    expect(compareMastodonIds('7', '7'), 0);
  });

  test('a post\'s HTML as text, its paragraphs kept and links shortened', () {
    expect(
      postText(
        '<p>Hello <span class="h-card"><a href="x" class="u-url mention">'
        '@<span>bob</span></a></span> &amp; all</p><p>Line one<br>line two'
        '<br />see <a href="https://example.com/a/very/long/path">'
        '<span class="invisible">https://</span><span class="ellipsis">'
        'example.com/a/very</span><span class="invisible">/long/path'
        '</span></a></p>',
      ),
      'Hello @bob & all\n\nLine one\nline two\nsee example.com/a/very…',
    );
    expect(withoutShortcodes('Alice :blobcat: :x:', ['blobcat']), 'Alice :x:');
  });

  group('Mastodon', () {
    test('a post, with its counts and its author', () {
      final p = MastodonApi.parseStatus(_status());
      expect(p.author.name, 'Alice');
      expect(p.author.handle, 'alice');
      expect(p.text, 'Hello');
      expect((p.replies, p.boosts, p.likes), (2, 3, 4));
      expect(p.boostedBy, isNull);
      expect(p.url, 'https://mastodon.social/@alice/1');
    });

    test('a boost is the post boosted, and who boosted it', () {
      final p = MastodonApi.parseStatus({
        ..._status(id: '2', content: ''),
        'account': {'username': 'bob', 'acct': 'bob', 'display_name': 'Bob'},
        'reblog': _status(id: '1', content: '<p>Original</p>'),
      });
      expect(p.text, 'Original');
      expect(p.author.name, 'Alice');
      expect(p.boostedBy?.name, 'Bob');
    });

    test('a content warning, pictures and a link card', () {
      final p = MastodonApi.parseStatus({
        ..._status(),
        'spoiler_text': 'Food',
        'sensitive': true,
        'in_reply_to_id': '9',
        'card': {'title': 'A page'},
        'media_attachments': [
          {
            'type': 'image',
            'preview_url': 'https://f/small.jpg',
            'url': 'https://f/big.jpg',
            'description': 'Cake',
          },
          {'type': 'video', 'preview_url': 'https://f/still.jpg'},
          {'type': 'audio', 'preview_url': null},
        ],
      });
      expect(p.warning, 'Food');
      expect(p.sensitive, isTrue);
      expect(p.isReply, isTrue);
      expect(p.linkTitle, 'A page');
      expect(p.images.map((i) => i.full), [
        'https://f/big.jpg',
        'https://f/still.jpg',
      ]);
      expect(p.images.first.alt, 'Cake');
    });

    test('notifications, by what they are about', () {
      SocialNoticeKind kind(String type, {Map<String, dynamic>? status}) =>
          MastodonApi.parseNotification({
            'id': '5',
            'type': type,
            'account': {'username': 'bob', 'display_name': ''},
            'status': status,
          }).kind;
      expect(kind('mention', status: _status()), SocialNoticeKind.mention);
      expect(
        kind('mention', status: {..._status(), 'in_reply_to_id': '1'}),
        SocialNoticeKind.reply,
      );
      expect(kind('reblog'), SocialNoticeKind.boost);
      expect(kind('favourite'), SocialNoticeKind.like);
      expect(kind('follow'), SocialNoticeKind.follow);
      expect(kind('admin.sign_up'), SocialNoticeKind.other);
      final n = MastodonApi.parseNotification({
        'id': '5',
        'type': 'follow',
        'account': {'username': 'bob', 'display_name': ''},
      });
      expect(n.who.name, 'bob', reason: 'no display name: the username');
      expect(noticeLine(n, SocialNetwork.mastodon), 'bob followed you');
    });

    test('the token goes only to the server, and a refusal says so', () async {
      final adapter = _Adapter(
        (o) => (401, {'error': 'The access token is invalid'}),
      );
      final api = MastodonApi(dio: Dio()..httpClientAdapter = adapter);
      const account = MastodonAccount(
        server: 'https://mastodon.example',
        token: 'secret',
      );
      await expectLater(
        api.feed(account, MastodonFeed.home),
        throwsA(
          isA<SocialException>().having(
            (e) => e.failure,
            'failure',
            SocialFailure.badCredentials,
          ),
        ),
      );
      expect(adapter.asked.single.uri.host, 'mastodon.example');
      expect(adapter.asked.single.headers['Authorization'], 'Bearer secret');
    });

    test('a list is found by its name', () async {
      final adapter = _Adapter(
        (o) => switch (o.uri.path) {
          '/api/v1/accounts/verify_credentials' => (
            200,
            {'id': '1', 'acct': 'me'},
          ),
          '/api/v1/lists' => (
            200,
            [
              {'id': '42', 'title': 'Friends'},
            ],
          ),
          '/api/v1/timelines/list/42' => (200, [_status()]),
          _ => (404, {'error': 'Not found'}),
        },
      );
      final api = MastodonApi(dio: Dio()..httpClientAdapter = adapter);
      const account = MastodonAccount(
        server: 'https://lists.example',
        token: 't',
      );
      final feed = await api.feed(account, MastodonFeed.list, list: 'friends');
      expect(feed.who, '@me@lists.example');
      expect(feed.posts.single.text, 'Hello');
      await expectLater(
        api.feed(account, MastodonFeed.list, list: 'Enemies'),
        throwsA(isA<SocialException>()),
      );
    });
  });

  group('Bluesky', () {
    tearDown(BlueskyApi.debugForget);

    Map<String, dynamic> post({List<Map<String, dynamic>>? labels}) => {
      'uri': 'at://did:plc:abc/app.bsky.feed.post/3kxyz',
      'author': {
        'did': 'did:plc:abc',
        'handle': 'alice.bsky.social',
        'displayName': 'Alice',
        'avatar': 'https://cdn/a.jpg',
      },
      'record': {'text': 'Hi there', 'createdAt': '2026-10-29T09:00:00Z'},
      'embed': {
        r'$type': 'app.bsky.embed.images#view',
        'images': [
          {'thumb': 'https://cdn/t.jpg', 'fullsize': 'https://cdn/f.jpg'},
        ],
      },
      'replyCount': 1,
      'repostCount': 2,
      'likeCount': 3,
      'labels': labels ?? const [],
    };

    test('a post in a feed, with who reposted it', () {
      final p = BlueskyApi.parseFeedItem({
        'post': post(),
        'reason': {
          r'$type': 'app.bsky.feed.defs#reasonRepost',
          'by': {'handle': 'bob.bsky.social', 'displayName': ''},
        },
      })!;
      expect(p.text, 'Hi there');
      expect(p.author.name, 'Alice');
      expect(p.boostedBy?.name, 'bob.bsky.social');
      expect(p.images.single.full, 'https://cdn/f.jpg');
      expect((p.replies, p.boosts, p.likes), (1, 2, 3));
      expect(p.url, 'https://bsky.app/profile/alice.bsky.social/post/3kxyz');
      expect(p.sensitive, isFalse);
      final adult = BlueskyApi.parseFeedItem({
        'post': post(
          labels: [
            {'val': 'porn'},
          ],
        ),
      })!;
      expect(adult.sensitive, isTrue);
    });

    test('a handle that no longer checks out is linked by its DID', () {
      expect(
        BlueskyApi.postUrl(
          'at://did:plc:abc/app.bsky.feed.post/3k',
          'handle.invalid',
        ),
        'https://bsky.app/profile/did:plc:abc/post/3k',
      );
    });

    test('a like brings the post liked; a reply carries its own', () {
      final liked = BlueskyApi.parsePost(post());
      final like = BlueskyApi.parseNotification(
        {
          'uri': 'at://did:plc:bob/app.bsky.feed.like/1',
          'reason': 'like',
          'reasonSubject': liked.id,
          'author': {'handle': 'bob.bsky.social', 'displayName': 'Bob'},
          'record': {r'$type': 'app.bsky.feed.like'},
          'indexedAt': '2026-10-29T10:00:00Z',
        },
        {liked.id: liked},
      );
      expect(like.kind, SocialNoticeKind.like);
      expect(like.post?.text, 'Hi there');
      expect(noticeLine(like, SocialNetwork.bluesky), 'Bob liked your post');
      final reply = BlueskyApi.parseNotification({
        'uri': 'at://did:plc:bob/app.bsky.feed.post/2',
        'reason': 'reply',
        'author': {'handle': 'bob.bsky.social', 'displayName': 'Bob'},
        'record': {'text': 'Lovely'},
        'indexedAt': '2026-10-29T10:00:00Z',
      });
      expect(reply.direct, isTrue);
      expect(reply.post?.text, 'Lovely');
    });

    BlueskyAccount account() => const BlueskyAccount(
      identifier: 'alice.bsky.social',
      password: 'app-pass',
    );

    test(
      'signs in once, on the account\'s own server, and renews there',
      () async {
        var timelines = 0;
        final adapter = _Adapter((o) {
          final method = o.uri.pathSegments.last;
          return switch (method) {
            'com.atproto.server.createSession' => (
              200,
              {
                'accessJwt': 'a1',
                'refreshJwt': 'r1',
                'did': 'did:plc:abc',
                'handle': 'alice.bsky.social',
                'didDoc': {
                  'service': [
                    {
                      'id': '#atproto_pds',
                      'serviceEndpoint': 'https://pds.example',
                    },
                  ],
                },
              },
            ),
            'com.atproto.server.refreshSession' => (
              200,
              {
                'accessJwt': 'a2',
                'refreshJwt': 'r2',
                'did': 'did:plc:abc',
                'handle': 'alice.bsky.social',
              },
            ),
            'app.bsky.feed.getTimeline' when ++timelines == 2 => (
              400,
              {'error': 'ExpiredToken'},
            ),
            'app.bsky.feed.getTimeline' => (
              200,
              {
                'feed': [
                  {'post': post()},
                ],
              },
            ),
            _ => (404, {}),
          };
        });
        final api = BlueskyApi(dio: Dio()..httpClientAdapter = adapter);
        final first = await api.feed(account(), BlueskyFeed.following);
        expect(first.who, '@alice.bsky.social');
        expect(first.posts.single.text, 'Hi there');
        // The second is turned away as expired, renewed, and asked again.
        await api.feed(account(), BlueskyFeed.following);
        final asked = [
          for (final o in adapter.asked)
            '${o.uri.host} ${o.uri.pathSegments.last}',
        ];
        expect(asked, [
          'bsky.social com.atproto.server.createSession',
          'pds.example app.bsky.feed.getTimeline',
          'pds.example app.bsky.feed.getTimeline',
          'pds.example com.atproto.server.refreshSession',
          'pds.example app.bsky.feed.getTimeline',
        ]);
        expect(adapter.asked.last.headers['Authorization'], 'Bearer a2');
      },
    );

    test('a refused password is not tried again straight away', () async {
      final adapter = _Adapter(
        (o) => (
          401,
          {
            'error': 'AuthenticationRequired',
            'message': 'Invalid identifier or password',
          },
        ),
      );
      final api = BlueskyApi(dio: Dio()..httpClientAdapter = adapter);
      for (var i = 0; i < 3; i++) {
        await expectLater(
          api.feed(account(), BlueskyFeed.following),
          throwsA(
            isA<SocialException>().having(
              (e) => e.failure,
              'failure',
              SocialFailure.badCredentials,
            ),
          ),
        );
      }
      expect(adapter.asked, hasLength(1));
    });
  });

  group('notifications on the panel', () {
    late ConfigService config;
    late _FakeMastodon mastodon;
    late _FakeBluesky bluesky;
    late List<({String from, String title, String text})> cards;
    late SocialNotifier notifier;

    DashboardWidgetConfig tile(String type, String notify, {String id = 'w'}) =>
        DashboardWidgetConfig(
          id: id,
          type: type,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          options: {
            'notify': notify,
            'server': 'mastodon.social',
            'token': 't',
            'handle': 'alice.bsky.social',
            'appPassword': 'p',
          },
        );

    setUp(() {
      config = ConfigService();
      config.config.dashboard.enabled = true;
      mastodon = _FakeMastodon();
      bluesky = _FakeBluesky();
      cards = [];
      notifier = SocialNotifier(
        config,
        mastodon: mastodon,
        bluesky: bluesky,
        onNotices: ({required from, required title, required text}) =>
            cards.add((from: from, title: title, text: text)),
      );
    });

    test(
      'what was waiting at the start is not news; what comes after is',
      () async {
        config.config.dashboard.widgets = [tile('mastodon', 'all')];
        mastodon.waiting = [_notice('10', SocialNoticeKind.like)];
        await notifier.check();
        expect(cards, isEmpty);
        mastodon.waiting = [
          _notice('12', SocialNoticeKind.mention),
          _notice('11', SocialNoticeKind.like),
          _notice('10', SocialNoticeKind.like),
        ];
        await notifier.check();
        expect(mastodon.since, [null, '10']);
        expect(cards.single.from, 'Mastodon');
        expect(cards.single.title, '2 new notifications');
        // Oldest first, what was said quoted.
        expect(
          cards.single.text,
          'Alice favourited your post: “Post 11”\n\n'
          'Alice mentioned you: “Post 12”',
        );
        await notifier.check();
        expect(cards, hasLength(1), reason: 'nothing new the third time');
      },
    );

    test('mentions only leaves likes and follows out', () async {
      config.config.dashboard.widgets = [tile('mastodon', 'mentions')];
      await notifier.check();
      mastodon.waiting = [
        _notice('3', SocialNoticeKind.follow),
        _notice('2', SocialNoticeKind.like),
      ];
      await notifier.check();
      expect(cards, isEmpty);
      mastodon.waiting = [_notice('4', SocialNoticeKind.reply)];
      await notifier.check();
      expect(cards.single.title, 'Alice replied');
    });

    test(
      'two tiles for one account give one card; a tile set to no, none',
      () async {
        config.config.dashboard.widgets = [
          tile('mastodon', 'mentions', id: 'a'),
          tile('mastodon', 'all', id: 'b'),
          tile('bluesky', 'off', id: 'c'),
        ];
        await notifier.check();
        mastodon.waiting = [_notice('7', SocialNoticeKind.like)];
        bluesky.waiting = [
          _notice('x', SocialNoticeKind.mention, at: DateTime(2026, 10, 29)),
        ];
        await notifier.check();
        expect(cards.single.title, 'Alice favourited your post');
      },
    );

    test('Bluesky\'s are new by when they came', () async {
      config.config.dashboard.widgets = [tile('bluesky', 'all')];
      bluesky.waiting = [
        _notice('a', SocialNoticeKind.like, at: DateTime(2026, 10, 29, 9)),
      ];
      await notifier.check();
      bluesky.waiting = [
        _notice('b', SocialNoticeKind.follow, at: DateTime(2026, 10, 29, 10)),
        ...bluesky.waiting,
      ];
      await notifier.check();
      expect(cards.single.from, 'Bluesky');
      expect(cards.single.title, 'Alice followed you');
    });

    test('nothing while the dashboard is switched off', () async {
      config.config.dashboard
        ..enabled = false
        ..widgets = [tile('mastodon', 'all')];
      await notifier.check();
      mastodon.waiting = [_notice('1', SocialNoticeKind.mention)];
      await notifier.check();
      expect(mastodon.since, isEmpty);
    });

    test('a long run of them is counted after the first few', () {
      final many = [
        for (var i = 0; i < 9; i++) _notice('$i', SocialNoticeKind.follow),
      ];
      final text = SocialNotifier.cardText(many, SocialNetwork.mastodon);
      expect(text.split('\n\n'), hasLength(SocialNotifier.shownOnCard + 1));
      expect(text, endsWith('and 3 more'));
    });

    test('the card is the share inbox\'s, as a notice', () {
      final inbox = ShareInboxService(config)
        ..notice(from: 'Mastodon', title: 'Alice replied', text: 'Hello');
      expect(inbox.current?.type, ShareType.notice);
      expect(inbox.current?.title, 'Alice replied');
      expect(inbox.current?.sender, 'Mastodon');
    });
  });

  group('the tiles', () {
    setUpAll(registerBuiltInWidgets);
    tearDown(() {
      MastodonApi.debugFeed = null;
      BlueskyApi.debugFeed = null;
    });

    final posts = [
      for (var i = 0; i < 8; i++)
        SocialPost(
          id: '$i',
          author: const SocialPerson(
            name: 'Someone with a long display name',
            handle: 'someone@a.very.long.server.example',
          ),
          text: 'A post that goes on for a while, ' * (i + 1),
          at: DateTime.now().subtract(Duration(minutes: i * 7)),
          replies: i,
          boosts: i * 2,
          likes: i * 3,
          boostedBy: i.isOdd ? _alice : null,
          isReply: i == 2,
          warning: i == 3 ? 'Spoilers' : null,
          linkTitle: i == 4 ? 'A linked page' : null,
        ),
    ];
    final notices = [
      for (final kind in SocialNoticeKind.values)
        _notice('${kind.index}', kind, at: DateTime.now()),
    ];

    Future<void> draw(
      WidgetTester tester,
      String type,
      Size size,
      Map<String, dynamic> options, {
      DashboardTheme? theme,
    }) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = WidgetRegistry.find(type)!;
      final w = DashboardWidgetContext(
        theme: theme ?? kBuiltInThemes.first,
        config: DashboardWidgetConfig(
          id: 's',
          type: type,
          x: 0,
          y: 0,
          width: 4,
          height: 4,
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

    testWidgets('posts and notifications fit every tile shape', (tester) async {
      MastodonApi.debugFeed = (a, feed) async => feed == MastodonFeed.home
          ? SocialFeed(who: '@me@mastodon.social', posts: posts)
          : SocialFeed(who: '@me@mastodon.social', notices: notices);
      BlueskyApi.debugFeed = (a, feed) async => feed == BlueskyFeed.following
          ? SocialFeed(who: '@me.bsky.social', posts: posts)
          : SocialFeed(who: '@me.bsky.social', notices: notices);
      final lcars = kBuiltInThemes.firstWhere((t) => t.isLcars);
      for (final (type, options) in [
        ('mastodon', {'server': 'mastodon.social', 'token': 't'}),
        (
          'mastodon',
          {'server': 'mastodon.social', 'token': 't', 'feed': 'notifications'},
        ),
        ('bluesky', {'handle': 'me.bsky.social', 'appPassword': 'p'}),
        (
          'bluesky',
          {'handle': 'me.bsky.social', 'appPassword': 'p', 'feed': 'mentions'},
        ),
      ]) {
        for (final theme in [kBuiltInThemes.first, lcars]) {
          for (final (w, h) in shapes) {
            if (w < 2 || h < 2) continue;
            await draw(tester, type, tile(w, h), options, theme: theme);
            expect(
              tester.takeException(),
              isNull,
              reason: '$type $options ${w}x$h',
            );
          }
        }
      }
      await draw(tester, 'mastodon', tile(4, 4), {
        'server': 'mastodon.social',
        'token': 't',
      });
      expect(find.text('Home · @me@mastodon.social'), findsOneWidget);
      expect(find.text('Boosted by Alice'), findsWidgets);
      expect(find.text('Content warning: Spoilers'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('says what the settings lack, and asks for nothing', (
      tester,
    ) async {
      var asked = 0;
      MastodonApi.debugFeed = (a, feed) async {
        asked++;
        return const SocialFeed(who: '');
      };
      await draw(tester, 'mastodon', tile(4, 4), const {});
      expect(
        find.text(
          'Add your server and an access token in the widget settings.',
        ),
        findsOneWidget,
      );
      await draw(tester, 'mastodon', tile(4, 4), {
        'server': 'not a server',
        'token': 't',
      });
      expect(find.textContaining('isn’t a server'), findsOneWidget);
      await draw(tester, 'bluesky', tile(4, 4), {'handle': 'me.bsky.social'});
      expect(
        find.text(
          'Add your handle and an app password in the widget settings.',
        ),
        findsOneWidget,
      );
      expect(asked, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a refusal is explained', (tester) async {
      BlueskyApi.debugFeed = (a, feed) async =>
          throw const SocialException(SocialFailure.badCredentials);
      await draw(tester, 'bluesky', tile(4, 4), {
        'handle': 'me.bsky.social',
        'appPassword': 'wrong',
      });
      expect(
        find.text(
          'Bluesky did not accept the sign-in. Check it in the widget settings.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
