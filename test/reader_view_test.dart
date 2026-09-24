import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/dashboard/dashboard_model.dart';
import 'package:immich_kiosk_pi/dashboard/dashboard_theme.dart';
import 'package:immich_kiosk_pi/dashboard/widget_registry.dart';
import 'package:immich_kiosk_pi/dashboard/widgets/news_widget.dart';
import 'package:immich_kiosk_pi/services/kiosk_browser.dart';

/// The article window on the panel: 1920 less a 24px margin each side.
const double panelWindow = 1872;

DashboardWidgetContext news(Map<String, dynamic> options) =>
    DashboardWidgetContext(
      theme: kBuiltInThemes.first,
      config: DashboardWidgetConfig(
        id: 'n',
        type: 'news',
        x: 0,
        y: 0,
        width: 7,
        height: 6,
        options: options,
      ),
    );

void main() {
  group('the reader address', () {
    test('wraps the article, with its own query string intact', () {
      const article =
          'https://www.bbc.co.uk/news/articles/cjly4rv0q3l0o?at_medium=RSS&at_campaign=rss';
      final url = KioskBrowser.readerUrl(article);
      expect(url, startsWith('about:reader?url='));
      // Unencoded, the & would end Firefox's url parameter early and the
      // reader would fetch a different page.
      expect(Uri.decodeComponent(url.substring('about:reader?url='.length)),
          article);
      expect(url, isNot(contains('&at_campaign')));
    });
  });

  group('what counts as an article', () {
    test('a news story does', () {
      expect(
          KioskBrowser.looksLikeArticle(
              'https://www.bbc.co.uk/news/articles/cjly4rv0q3l0o'),
          isTrue);
      expect(
          KioskBrowser.looksLikeArticle(
              'https://www.theverge.com/2026/9/1/some-story'),
          isTrue);
    });

    test('video and live pages do not, since there is no text to extract', () {
      for (final url in [
        'https://www.bbc.co.uk/news/videos/c6804ne8knklo',
        'https://www.bbc.co.uk/news/live/world-12345',
        'https://www.bbc.co.uk/news/av/uk-12345',
        'https://www.youtube.com/watch?v=abc',
        'https://youtu.be/abc',
        'https://www.bbc.co.uk/news/in-pictures-12345',
      ]) {
        expect(KioskBrowser.looksLikeArticle(url), isFalse, reason: url);
      }
    });

    test('anything that is not a web page does not', () {
      expect(KioskBrowser.looksLikeArticle('not a url'), isFalse);
      expect(KioskBrowser.looksLikeArticle('file:///etc/passwd'), isFalse);
      expect(KioskBrowser.looksLikeArticle('about:config'), isFalse);
    });
  });

  group('sizes, as Firefox 153 draws them', () {
    test('text steps match AboutReader._setFontSize', () {
      expect(KioskBrowser.readerFontPx(1), 12);
      expect(KioskBrowser.readerFontPx(5), 20);
      expect(KioskBrowser.readerFontPx(9), 28);
      expect(KioskBrowser.readerFontPx(10), 32);
      expect(KioskBrowser.readerFontPx(11), 40);
      expect(KioskBrowser.readerFontPx(12), 56);
      expect(KioskBrowser.readerFontPx(15), 128);
    });

    test('out-of-range steps are clamped, not thrown', () {
      expect(KioskBrowser.readerFontPx(0), 12);
      expect(KioskBrowser.readerFontPx(99), 128);
    });
  });

  group('fitting the column to the screen', () {
    test('on the panel, each size gets the widest column that fits', () {
      // 32px at 50em, 40px at 40em, 56px at 30em: 1600, 1600 and 1680px of
      // a 1872px window, with room left for the reader's toolbar.
      expect(KioskBrowser.readerWidthStep(panelWindow, 10), 7);
      expect(KioskBrowser.readerWidthStep(panelWindow, 11), 5);
      expect(KioskBrowser.readerWidthStep(panelWindow, 12), 3);
    });

    test('the column never runs past the window', () {
      for (var width = 400.0; width <= 4000; width += 37) {
        for (var step = 1; step <= 15; step++) {
          final n = KioskBrowser.readerWidthStep(width, step);
          final column = (20 + 5 * (n - 1)) * KioskBrowser.readerFontPx(step);
          if (n > 1) {
            expect(column, lessThanOrEqualTo(width - 160),
                reason: 'step $step in $width');
          }
        }
      }
    });

    test('it is the widest that fits, not just any that fits', () {
      for (var step = 1; step <= 12; step++) {
        final n = KioskBrowser.readerWidthStep(panelWindow, step);
        if (n < 9) {
          final wider = (20 + 5 * n) * KioskBrowser.readerFontPx(step);
          expect(wider, greaterThan(panelWindow - 160),
              reason: 'step $step could have gone wider than $n');
        }
      }
    });

    test('a window too small for any column still gets the narrowest', () {
      expect(KioskBrowser.readerWidthStep(200, 12), 1);
    });
  });

  group('the preferences written', () {
    test('carry the size, the fitted width and the colours', () {
      final prefs = KioskBrowser.readerPrefs(
          const ReaderStyle(fontStep: 11, colourScheme: 'dark'),
          windowWidth: panelWindow);
      expect(prefs, contains('user_pref("reader.font_size", 11);'));
      expect(prefs, contains('user_pref("reader.content_width", 5);'));
      expect(prefs, contains('user_pref("reader.color_scheme", "dark");'));
    });
  });

  group('the news widget', () {
    test('opens articles in reader view by default, large and dark', () {
      final style = DashboardNewsWidget.readerStyle(news({}));
      expect(style, isNotNull);
      expect(style!.fontStep, 11);
      expect(style.colourScheme, 'dark');
    });

    test('follows its settings', () {
      final style = DashboardNewsWidget.readerStyle(
          news({'readerTextSize': 'huge', 'readerTheme': 'sepia'}));
      expect(style!.fontStep, 12);
      expect(style.colourScheme, 'sepia');
    });

    test('switched off, pages open as the site serves them', () {
      expect(DashboardNewsWidget.readerStyle(news({'readerView': false})),
          isNull);
    });
  });
}
