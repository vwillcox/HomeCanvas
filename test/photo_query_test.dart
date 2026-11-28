import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/screens/photo_search_screen.dart' show faceNames;
import 'package:home_canvas/services/immich_service.dart' show Person;
import 'package:home_canvas/services/photo_query.dart';

void main() {
  // As Immich lists them: the most photographed first.
  const ellie = Person(id: 'g', name: 'Ellie Parker');
  const sam = Person(id: 'a', name: 'Sam Parker');
  const nan = Person(id: 'n1', name: 'Nan Parker');
  const nanToo = Person(id: 'n2', name: 'Nan');
  const june = Person(id: 'j', name: 'June');
  const jackAndBen = Person(id: 'nt', name: 'Jack and Ben Parker');
  const olivia = Person(id: 'o', name: 'Olivia Parker');
  const people = [ellie, sam, nan, jackAndBen, nanToo, june, olivia];
  const places = [
    PhotoPlace(PhotoPlaceKind.city, 'Llandudno'),
    PhotoPlace(PhotoPlaceKind.city, 'London'),
    PhotoPlace(PhotoPlaceKind.city, 'City of London'),
    PhotoPlace(PhotoPlaceKind.city, 'Southend-on-Sea'),
    PhotoPlace(PhotoPlaceKind.state, 'Wales'),
    PhotoPlace(PhotoPlaceKind.country, 'Ireland'),
  ];
  final now = DateTime(2026, 11, 3, 15);

  PhotoQuery ask(String s) =>
      PhotoQuery.parse(s, people: people, places: places, now: now)!;

  group('what is in them', () {
    test('is what is left once the asking is gone', () {
      expect(ask('show me photos of the beach').text, 'beach');
      expect(ask('find pictures of a dog in the snow').text, 'dog in the snow');
      expect(ask('sunsets').text, 'sunsets');
      expect(ask('beach photos').text, 'beach');
    });

    test('keeps what was asked, less the asking', () {
      expect(ask('of the beach').asked, 'beach');
      expect(ask("show me Ellie's photos").asked, "Ellie's photos");
    });

    test('asks for nothing when nothing is left', () {
      expect(PhotoQuery.parse('show me photos'), isNull);
      expect(PhotoQuery.parse('pictures of the'), isNull);
      expect(PhotoQuery.parse(''), isNull);
    });

    test('is chosen by looks, closest first; the rest newest first', () {
      expect(ask('the beach').byLooks, isTrue);
      expect(ask('photos of Ellie').byLooks, isFalse);
      expect(const PhotoQuery.like('x').byLooks, isTrue);
    });
  });

  group('who', () {
    test('by first name or whole name, apostrophe and all', () {
      expect(ask('photos of ellie').people, [ellie]);
      expect(ask('photos of Ellie Parker').people, [ellie]);
      expect(ask("Ellie's birthday").people, [ellie]);
      expect(ask("Ellie's birthday").text, 'birthday');
    });

    test('everyone named, the "and" between them taken too', () {
      final q = ask('ellie and sam at the beach');
      expect(q.people, [ellie, sam]);
      expect(q.text, 'beach');
      expect(ask('ellie and sam together').text, isEmpty);
    });

    test('the most photographed of two with one name', () {
      expect(ask('photos of nan').people, [nan]);
    });

    test('a name of several words, "and" in it', () {
      expect(ask('photos of jack and ben parker').people, [jackAndBen]);
    });

    test('one letter misheard', () {
      expect(ask('photos of olivea').people, [olivia]);
    });

    test('nobody, when no one is named', () {
      expect(ask('dog and cat').people, isEmpty);
      expect(ask('dog and cat').text, 'dog and cat');
    });
  });

  group('where', () {
    test('a town, a nation, a country', () {
      expect(ask('photos from llandudno').place, places[0]);
      expect(ask('photos from llandudno').text, isEmpty);
      expect(ask('the beach in wales').place, places[4]);
      expect(ask('the beach in wales').text, 'beach');
      expect(ask('ireland').place, places[5]);
    });

    test('the longest name said', () {
      expect(ask('photos of the city of london').place, places[2]);
      expect(ask('southend on sea').place, places[3]);
    });

    test('with what is left reading as a phrase', () {
      expect(ask('snow at llandudno with the dog').text, 'snow with the dog');
    });
  });

  group('when', () {
    PhotoWhen when(String s) => ask(s).when!;

    test('a year, in figures or in words', () {
      expect(
        when('photos from 2019'),
        PhotoWhen(DateTime(2019), DateTime(2020), '2019'),
      );
      expect(when('twenty nineteen').after, DateTime(2019));
      expect(when('twenty twenty four').after, DateTime(2024));
      expect(when('nineteen ninety nine').after, DateTime(1999));
      expect(when('two thousand and nine').after, DateTime(2009));
      expect(when('nineteen oh five').after, DateTime(1905));
    });

    test('never one still to come', () {
      expect(ask('photos from 2030').when, isNull);
      expect(ask('photos from 2030').text, '2030');
    });

    test('last year, this year, years ago', () {
      expect(when('last year').after, DateTime(2025));
      expect(when('this year').after, DateTime(2026));
      expect(when('five years ago').after, DateTime(2021));
      expect(when('a year ago').after, DateTime(2025));
    });

    test('a month with its year, or after "in"', () {
      final march = when('march 2024');
      expect(march.after, DateTime(2024, 3));
      expect(march.before, DateTime(2024, 4));
      // Not yet this year: last year's.
      expect(when('photos in december').after, DateTime(2025, 12));
      expect(when('photos in august').after, DateTime(2026, 8));
      expect(when('last month').after, DateTime(2026, 10));
    });

    test('a month alone is someone of that name', () {
      final q = ask('photos of june');
      expect(q.when, isNull);
      expect(q.people, [june]);
      expect(ask('june 2020').when!.after, DateTime(2020, 6));
    });

    test('seasons', () {
      final summer = when('summer 2019');
      expect(summer.after, DateTime(2019, 6));
      expect(summer.before, DateTime(2019, 9));
      expect(summer.label, 'Summer 2019');
      // In November: this year's summer has been.
      expect(when('last summer').after, DateTime(2026, 6));
      expect(when('this summer').after, DateTime(2026, 6));
      // Last winter began last December.
      expect(when('last winter').after, DateTime(2025, 12));
      expect(when('last winter').before, DateTime(2026, 3));
      // A season alone is what it looks like.
      expect(ask('summer').when, isNull);
      expect(ask('summer').text, 'summer');
    });

    test('in the middle of a season, "last" is the one before', () {
      final july = DateTime(2026, 7, 10);
      PhotoWhen at(String s) => PhotoQuery.parse(s, now: july)!.when!;
      expect(at('last summer').after, DateTime(2025, 6));
      expect(at('this summer').after, DateTime(2026, 6));
      final january = DateTime(2026, 1, 10);
      expect(
        PhotoQuery.parse('this winter', now: january)!.when!.after,
        DateTime(2025, 12),
      );
    });

    test('decades', () {
      expect(
        when('the nineties'),
        PhotoWhen(DateTime(1990), DateTime(2000), 'The 1990s'),
      );
      expect(when('photos from the 1980s').after, DateTime(1980));
      expect(when('80s').after, DateTime(1980));
      expect(ask('photos from the nineties').text, isEmpty);
    });

    test('today and yesterday', () {
      expect(when('today').after, DateTime(2026, 11, 3));
      expect(when('yesterday').before, DateTime(2026, 11, 3));
    });
  });

  test('all of it at once', () {
    final q = ask(
      'show me pictures of ellie and sam at the beach in wales in summer 2019',
    );
    expect(q.people, [ellie, sam]);
    expect(q.place, places[4]);
    expect(q.when!.label, 'Summer 2019');
    expect(q.text, 'beach');
    expect(q.label, 'Ellie & Sam · Beach · Wales · Summer 2019');
  });

  test('videos only, when only videos are asked for', () {
    expect(ask('videos of ellie').videos, isTrue);
    expect(ask('photos and videos of ellie').videos, isFalse);
    expect(ask('slide show of ellie').people, [ellie]);
  });

  group('the search Immich is sent', () {
    test('by looks, with whatever else was said', () {
      final body = ask('ellie at the beach in 2019').body();
      expect(body['query'], 'beach');
      expect(body['personIds'], ['g']);
      expect(body['takenAfter'], '2019-01-01T00:00:00.000Z');
      expect(body['takenBefore'], '2020-01-01T00:00:00.000Z');
      expect(body.containsKey('order'), isFalse);
    });

    test('by details, newest first', () {
      final body = ask('photos from llandudno').body(page: 2, size: 120);
      expect(body['city'], 'Llandudno');
      expect(body['order'], 'desc');
      expect(body['page'], 2);
      expect(body['size'], 120);
      expect(body.containsKey('query'), isFalse);
    });

    test('never the Locked Folder or the archive', () {
      expect(ask('beach').body()['visibility'], 'timeline');
      expect(const PhotoQuery.like('x').body()['visibility'], 'timeline');
      expect(const PhotoQuery.like('x').body()['queryAssetId'], 'x');
    });
  });

  test('faces named without the family surname, unless two would match', () {
    expect(
      faceNames(const [
        Person(id: '1', name: 'Ellie Parker'),
        Person(id: '2', name: 'Sam Parker'),
        Person(id: '3', name: 'Nan Parker'),
        Person(id: '4', name: 'Nan'),
        Person(id: '5', name: 'Jack and Ben Parker'),
        Person(id: '6', name: 'Auntie Mary'),
      ]),
      ['Ellie', 'Sam', 'Nan Parker', 'Nan', 'Jack and Ben', 'Auntie Mary'],
    );
    // A surname two people share is theirs to keep.
    expect(
      faceNames(const [
        Person(id: '1', name: 'Ellie Parker'),
        Person(id: '2', name: 'Sam Parker'),
        Person(id: '3', name: 'Jo Smith'),
      ]),
      ['Ellie Parker', 'Sam Parker', 'Jo Smith'],
    );
  });
}
