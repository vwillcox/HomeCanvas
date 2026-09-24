import 'package:flutter_test/flutter_test.dart';

import 'package:immich_kiosk_pi/services/feed_service.dart';

FeedItem item(String title, {String? link, List<String> categories = const []}) =>
    FeedItem(title: title, link: link, categories: categories);

void main() {
  group('promotions are hidden', () {
    // Real headlines from the WIRED feed on the day this was written.
    for (final title in [
      'Peacock Promo Codes: 40% Off September 2026',
      r'Motley Fool Promo Code: $200 Off on Stock Advisor September 2026',
      'AirDoctor Coupon Codes: 40% Off | September 2026',
      'Wayfair Coupons: Up to 80% Off September 2026',
      'TurboTax Full Service Coupons This September 2026',
      'PlayStation Discount Code: Save on PS5 Games September 2026',
      'Nike Promo Codes and Discounts: 30% for September 2026',
    ]) {
      test(title, () => expect(isPromotional(item(title)), isTrue));
    }

    test('by what they say they are', () {
      for (final title in [
        'Sponsored: The laptop that does it all',
        'Paid post: How we build trust',
        'Partner content — the future of banking',
        '[Ad] Our favourite mattress',
        '£30 off this week only',
        'Black Friday deals on everything',
        'Deal alert: headphones at their lowest price',
        'Get a voucher for your next shop',
      ]) {
        expect(isPromotional(item(title)), isTrue, reason: title);
      }
    });

    test('by their address, whatever the headline says', () {
      expect(
          isPromotional(item('Save on your next order',
              link: 'https://www.wired.com/story/peacock-promo-code/')),
          isTrue);
      expect(
          isPromotional(item('Our friends at Acme',
              link: 'https://example.com/sponsored/acme-feature')),
          isTrue);
    });

    test("by the publisher's own category", () {
      expect(
          isPromotional(item('Stock Advisor, for less',
              categories: ['Gear', 'Gear / Deals'])),
          isTrue);
      expect(isPromotional(item('Something', categories: ['Sponsored Content'])),
          isTrue);
    });
  });

  group('news is kept', () {
    test('real headlines from the same feeds', () {
      for (final title in [
        'AT&T Is Automating Away Jobs—and Its Old Telecom Empire',
        r'How to Claim Your Cut of Apple’s $250 Million Siri Settlement',
        '£170 a bag? Protein users squeezed as prices soar',
        'Lidl banned from selling copycat Birkenstock sandals, Dutch court rules',
        'Meta ditches the camera on its newest smart glasses',
        'Judge temporarily overturns Trump\'s White House media ban',
      ]) {
        expect(isPromotional(item(title)), isFalse, reason: title);
      }
    });

    test('"deal" on its own is news, not shopping', () {
      for (final title in [
        'UK and US sign trade deal',
        'Nurses accept pay deal after months of strikes',
        'Brexit deal vote delayed again',
        'Club agrees record transfer deal',
      ]) {
        expect(isPromotional(item(title)), isFalse, reason: title);
      }
    });

    test('reviews and buying guides stay — editorial, even with commission',
        () {
      expect(
          isPromotional(item('The Best Samsung Phones of 2026: Ultra, Fold, Budget',
              link: 'https://www.wired.com/gallery/best-samsung-phones/',
              categories: ['Gear', 'Gear / Buying Guides'])),
          isFalse);
      expect(
          isPromotional(item('Kiwibit Bird Feeder 2 Pro Review: Premium but Paywalled',
              link: 'https://www.wired.com/review/kiwibit-bird-feeder-2-pro/',
              categories: ['Gear', 'Gear / Reviews'])),
          isFalse);
    });

    test('headlines that merely start with "ad"', () {
      for (final title in [
        'Ad giants face new privacy rules',
        'Adobe Premiere comes to Android',
        'Adele announces farewell tour',
      ]) {
        expect(isPromotional(item(title)), isFalse, reason: title);
      }
    });

    test('percentages that are not discounts', () {
      for (final title in [
        'Inflation falls to 2% as energy prices ease',
        'Turnout up 12% on the last election',
      ]) {
        expect(isPromotional(item(title)), isFalse, reason: title);
      }
    });

    test('a news category that merely contains a trigger word', () {
      expect(
          isPromotional(item('Retail sales slump', categories: ['Business / Deals and Mergers'])),
          isFalse);
    });
  });

  group('reading categories from the feed', () {
    test('RSS <category> elements, including nested paths', () {
      final items = FeedService.parseFeed('''<?xml version="1.0"?>
<rss><channel><item>
  <title>Peacock Promo Codes: 40% Off</title>
  <link>https://www.wired.com/story/peacock-promo-code/</link>
  <category>Gear</category>
  <category><![CDATA[Gear / Deals]]></category>
</item></channel></rss>''');
      expect(items.single.categories, ['Gear', 'Gear / Deals']);
    });

    test('Atom term attributes', () {
      final items = FeedService.parseFeed('''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><entry>
  <title>Meta is making a standalone Muse AI gadget</title>
  <link href="https://www.theverge.com/tech/999750/muse"/>
  <category term="AI"/><category term="Meta"/>
</entry></feed>''');
      expect(items.single.categories, ['AI', 'Meta']);
    });
  });
}
