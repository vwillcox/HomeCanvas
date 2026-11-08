import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/config/app_config.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/parcel_carriers.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

/// Recognising a parcel. In a file of its own, away from any widget test:
/// those answer every real HTTP request with a 400, and the inbox's tests
/// below make real ones, to a server of their own.
void main() {
  group('a tracking link', () {
    ParcelRef? f(String s) => ParcelRef.find(s);

    test('Royal Mail keeps its number after the #', () {
      final p = f(
        'https://www.royalmail.com/track-your-item#/tracking-results/QG123456785GB',
      )!;
      expect(p.carrier, Carrier.royalMail);
      expect(p.number, 'QG123456785GB');
    });

    test('Royal Mail by parameter', () {
      final p = f(
        'https://www.royalmail.com/portal/rm/track?trackNumber=tt123456789gb',
      )!;
      expect(p.carrier, Carrier.royalMail);
      expect(p.number, 'TT123456789GB');
    });

    test('DPD keeps the link that goes straight to the parcel', () {
      const link = 'https://track.dpd.co.uk/parcels/15501234567890*19826';
      final p = f('Your DPD parcel is on its way! $link.')!;
      expect(p.carrier, Carrier.dpd);
      expect(p.number, '15501234567890');
      expect(p.url, link);
    });

    test('DPD by reference, and DPD Local', () {
      expect(
        f(
          'https://www.dpd.co.uk/apps/tracking/?reference=15509876543210',
        )!.number,
        '15509876543210',
      );
      expect(
        f('https://track.dpdlocal.co.uk/parcels/15501112223334*12345')!.carrier,
        Carrier.dpdLocal,
      );
    });

    test('Evri, Yodel, UPS, FedEx, DHL', () {
      expect(
        f('https://www.evri.com/track/parcel/H01HYA0012345678/details'),
        isA<ParcelRef>()
            .having((p) => p.carrier, 'carrier', Carrier.evri)
            .having((p) => p.number, 'number', 'H01HYA0012345678'),
      );
      expect(
        f('https://www.yodel.co.uk/track/JD0002251234567890')!.carrier,
        Carrier.yodel,
      );
      final ups = f(
        'https://www.ups.com/track?loc=en_GB&tracknum=1Z999AA10123456784',
      )!;
      expect((ups.carrier, ups.number), (Carrier.ups, '1Z999AA10123456784'));
      expect(
        f('https://www.fedex.com/fedextrack/?trknbr=123456789012')!.carrier,
        Carrier.fedex,
      );
      expect(
        f(
          'https://www.dhl.com/gb-en/home/tracking/tracking-express.html?tracking-id=1234567890',
        )!.number,
        '1234567890',
      );
    });

    test('a carrier link with no number is not a parcel', () {
      expect(f('https://www.royalmail.com/track-your-item'), isNull);
      expect(
        f('https://www.royalmail.com/news/stamp-prices-change-in-april'),
        isNull,
      );
      expect(f('https://www.royalmail.com/news/track-and-trace-upgrade'), isNull);
      expect(
        f('https://www.dhl.com/gb-en/home/press/press-archive/2026/news.html'),
        isNull,
      );
      expect(f('https://www.ups.com/gb/en/shipping/zones-and-rates'), isNull);
      // Nor in what was sent as a parcel: there is no number to track.
      expect(
        ParcelRef.find(
          'https://www.royalmail.com/track-your-item',
          explicit: true,
        ),
        isNull,
      );
    });

    test('an Amazon delivery, but not an Amazon product', () {
      expect(
        f(
          'https://www.amazon.co.uk/progress-tracker/package/ref=ppx_yo_dt?orderId=205-1234567-1234567&shipmentId=Abc123',
        )!.carrier,
        Carrier.amazon,
      );
      expect(f('https://www.amazon.co.uk/dp/B0ABCDEF12'), isNull);
    });

    test('a tracker of every carrier, by the number', () {
      final p = f('https://t.17track.net/en#nums=QG123456785GB')!;
      expect((p.carrier, p.number), (Carrier.royalMail, 'QG123456785GB'));
      expect(
        f('https://parcelsapp.com/en/tracking/15501234567890')!.carrier,
        Carrier.unknown,
      );
    });

    test('a shop\'s own tracking page naming a number', () {
      final p = f(
        'https://shop.example.com/order/track?trackingNumber=AB12345678',
      )!;
      expect((p.carrier, p.number), (Carrier.unknown, 'AB12345678'));
    });

    test('links that are not parcels', () {
      expect(
        f('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
        isNull,
      );
      expect(f('https://www.bbc.co.uk/news/articles/c4g0123456'), isNull);
      expect(f('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
      expect(f('https://example.com/results/12345678'), isNull);
    });
  });

  group('a number in words', () {
    test('in a carrier\'s own format, alone or in a sentence', () {
      expect(ParcelRef.find('QG123456785GB')!.carrier, Carrier.royalMail);
      expect(
        ParcelRef.find('Your parcel 1z999aa10123456784 has shipped')!.carrier,
        Carrier.ups,
      );
      expect(ParcelRef.find('H01HYA0012345678')!.carrier, Carrier.evri);
      expect(ParcelRef.find('TBA123456789012')!.carrier, Carrier.amazon);
    });

    test('the shape beats the words, except where it is shared', () {
      expect(
        ParcelRef.find('Amazon order, with UPS: 1Z999AA10123456784')!.carrier,
        Carrier.ups,
      );
      expect(
        ParcelRef.find('Parcelforce CH123456789GB')!.carrier,
        Carrier.parcelforce,
      );
      expect(
        ParcelRef.find('Coming from China: LP123456789CN')!.carrier,
        Carrier.unknown,
      );
    });

    test('digits count beside a carrier\'s name', () {
      final p = ParcelRef.find('DPD 15501234567890')!;
      expect((p.carrier, p.number), (Carrier.dpd, '15501234567890'));
      expect(p.url, 'https://track.dpd.co.uk/search?reference=15501234567890');
    });

    test('but not a note that only mentions one', () {
      expect(
        ParcelRef.find('Call 07700900123 about the ups and downs'),
        isNull,
      );
      expect(
        ParcelRef.find(
          'Remember to tell Amazon customer services, the number to ring is '
          '0800 279 7234 and the account is 99887766554 - ask for Sam',
        ),
        isNull,
      );
      expect(ParcelRef.find('Buy milk'), isNull);
      expect(ParcelRef.find('Pick up the kids at 3'), isNull);
    });

    test('anything with a digit, when sent as a parcel', () {
      final p = ParcelRef.find('5566-7788-99', explicit: true)!;
      expect((p.carrier, p.number), (Carrier.unknown, '5566778899'));
      expect(p.url, 'https://t.17track.net/en#nums=5566778899');
      expect(ParcelRef.find('no number here', explicit: true), isNull);
    });
  });

  test('a tracking service\'s name for the carrier', () {
    expect(Carrier.named('Royal Mail'), Carrier.royalMail);
    expect(Carrier.named('dpd-uk'), Carrier.dpd);
    expect(Carrier.named('DPD Local'), Carrier.dpdLocal);
    expect(Carrier.named('Evri (Hermes UK)'), Carrier.evri);
    expect(Carrier.named('ups'), Carrier.ups);
    expect(Carrier.named('Some Courier'), isNull);
  });

  group('shared to the panel', () {
    late HttpServer server;
    late ShareInboxService inbox;
    final shared = <SharedItem>[];

    setUp(() async {
      shared.clear();
      final config = ConfigService();
      config.config.shareInbox.senderTokens = [
        SenderToken(name: 'Vinny', token: 'right'),
      ];
      inbox = ShareInboxService(config)..onShared = shared.add;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(inbox.handle);
    });
    tearDown(() => server.close(force: true));

    Future<int> post(Map<String, Object> body) async {
      final client = HttpClient();
      try {
        final r = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/share'),
        );
        r.headers
          ..set('authorization', 'Bearer right')
          ..contentType = ContentType.json;
        r.write(jsonEncode(body));
        final response = await r.close();
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close();
      }
    }

    test('a tracking link shared as a link is a parcel', () async {
      expect(
        await post({
          'type': 'link',
          'content': 'https://track.dpd.co.uk/parcels/15501234567890*19826',
        }),
        200,
      );
      final item = shared.single;
      expect(item.type, ShareType.parcel);
      expect(item.parcel!.carrier, Carrier.dpd);
      expect(item.sender, 'Vinny');
    });

    test('a number sent as a parcel, with its name', () async {
      expect(
        await post({
          'type': 'parcel',
          'content': '5566778899',
          'label': 'Birthday present',
        }),
        200,
      );
      expect(shared.single.parcel!.number, '5566778899');
      expect(shared.single.title, 'Birthday present');
    });

    test('a parcel that is not one is turned away', () async {
      expect(await post({'type': 'parcel', 'content': 'hello'}), 400);
      expect(shared, isEmpty);
    });

    test('a note is still a note', () async {
      expect(await post({'type': 'text', 'content': 'Buy milk'}), 200);
      expect(shared.single.type, ShareType.text);
      expect(shared.single.parcel, isNull);
    });
  });
}
