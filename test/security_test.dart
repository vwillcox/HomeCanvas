import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/services/dashboard_service.dart';
import 'package:home_canvas/services/kiosk_browser.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

void main() {
  test('the editor answers only to names on the home network', () {
    bool ok(String? h) => DashboardService.localHostName(h);
    expect(ok('192.168.1.57:8090'), isTrue);
    expect(ok('192.168.1.57'), isTrue);
    expect(ok('homecanvas.local'), isTrue);
    expect(ok('homecanvas.local:8090'), isTrue);
    expect(ok('HomeCanvas.Local.'), isTrue);
    expect(ok('homecanvas'), isTrue);
    expect(ok('localhost:8090'), isTrue);
    expect(ok('homecanvas.lan'), isTrue);
    expect(ok('pi.home.arpa'), isTrue);
    expect(ok('[::1]:8090'), isTrue);
    // A public name pointed at the panel by its owner: DNS rebinding.
    expect(ok('evil.example.com:8090'), isFalse);
    expect(ok('local.evil.com'), isFalse);
    expect(ok(''), isFalse);
    expect(ok(null), isFalse);
  });

  test('only web addresses go to the browser', () {
    bool ok(String u) => KioskBrowser.isWebAddress(u);
    expect(ok('https://www.bbc.co.uk/news/1'), isTrue);
    expect(ok('http://192.168.1.10:8123/'), isTrue);
    expect(ok('file:///home/pi/.config/homecanvas/config.json'), isFalse);
    expect(ok('javascript:alert(1)'), isFalse);
    expect(ok('--renderer-cmd-prefix=sh'), isFalse);
    expect(ok('-P'), isFalse);
    expect(ok('https://'), isFalse);
    expect(ok('about:config'), isFalse);
  });

  test('tokens compare equal only when they are', () {
    expect(ShareInboxService.sameSecret('abc123', 'abc123'), isTrue);
    expect(ShareInboxService.sameSecret('abc123', 'abc124'), isFalse);
    expect(ShareInboxService.sameSecret('abc123', 'abc12'), isFalse);
    expect(ShareInboxService.sameSecret('abc', 'abc123'), isFalse);
    expect(ShareInboxService.sameSecret('', ''), isTrue);
    expect(ShareInboxService.sameSecret('', 'a'), isFalse);
  });
}
