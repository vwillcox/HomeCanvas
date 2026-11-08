import 'package:flutter/material.dart' show Color;

/// A delivery company the panel knows by name: what to call it, the colour
/// its badge is drawn in, and where its own tracking page is.
class Carrier {
  const Carrier({
    required this.id,
    required this.name,
    required this.short,
    required this.colour,
    this.page,
  });

  /// Stable: it is what a saved parcel names.
  final String id;
  final String name;

  /// Two or three letters for the badge: "RM", "DPD".
  final String short;
  final Color colour;

  /// The carrier's tracking page for a number, `{n}` standing for it. Null
  /// where the panel does not know one, and a parcel keeps the link it was
  /// shared with.
  final String? page;

  static const royalMail = Carrier(
    id: 'royalmail',
    name: 'Royal Mail',
    short: 'RM',
    colour: Color(0xFFE1251B),
    page: 'https://www.royalmail.com/track-your-item#/tracking-results/{n}',
  );
  static const parcelforce = Carrier(
    id: 'parcelforce',
    name: 'Parcelforce',
    short: 'PF',
    colour: Color(0xFFE1251B),
    page: 'https://www.parcelforce.com/track-trace?trackNumber={n}',
  );
  static const dpd = Carrier(
    id: 'dpd',
    name: 'DPD',
    short: 'DPD',
    colour: Color(0xFFDC0032),
    page: 'https://track.dpd.co.uk/search?reference={n}',
  );
  static const dpdLocal = Carrier(
    id: 'dpdlocal',
    name: 'DPD Local',
    short: 'DPD',
    colour: Color(0xFFDC0032),
    page: 'https://track.dpdlocal.co.uk/search?reference={n}',
  );
  static const evri = Carrier(
    id: 'evri',
    name: 'Evri',
    short: 'EV',
    colour: Color(0xFF007BC4),
    page: 'https://www.evri.com/track/parcel/{n}/details',
  );
  static const yodel = Carrier(
    id: 'yodel',
    name: 'Yodel',
    short: 'YO',
    colour: Color(0xFF6CB33F),
    page: 'https://www.yodel.co.uk/track/{n}',
  );
  static const dhl = Carrier(
    id: 'dhl',
    name: 'DHL',
    short: 'DHL',
    colour: Color(0xFFFFCC00),
    page: 'https://www.dhl.com/gb-en/home/tracking.html?tracking-id={n}',
  );
  static const ups = Carrier(
    id: 'ups',
    name: 'UPS',
    short: 'UPS',
    colour: Color(0xFFFFB500),
    page: 'https://www.ups.com/track?tracknum={n}',
  );
  static const fedex = Carrier(
    id: 'fedex',
    name: 'FedEx',
    short: 'FX',
    colour: Color(0xFF6D3FB0),
    page: 'https://www.fedex.com/fedextrack/?trknbr={n}',
  );
  static const amazon = Carrier(
    id: 'amazon',
    name: 'Amazon',
    short: 'AMZ',
    colour: Color(0xFFFF9900),
  );
  static const inpost = Carrier(
    id: 'inpost',
    name: 'InPost',
    short: 'IP',
    colour: Color(0xFFFFCD00),
    page: 'https://inpost.co.uk/tracking/?number={n}',
  );

  /// A courier the panel cannot name. Its page is 17TRACK's, which works
  /// the carrier out from the number itself.
  static const unknown = Carrier(
    id: 'parcel',
    name: 'Parcel',
    short: '?',
    colour: Color(0xFF8A94A6),
    page: 'https://t.17track.net/en#nums={n}',
  );

  static const all = [
    royalMail,
    parcelforce,
    dpd,
    dpdLocal,
    evri,
    yodel,
    dhl,
    ups,
    fedex,
    amazon,
    inpost,
    unknown,
  ];

  static Carrier byId(String? id) =>
      all.where((c) => c.id == id).firstOrNull ?? unknown;

  /// The carrier a tracking service names, as near as it can be matched:
  /// "Royal Mail", "royal-mail", "DPD UK", "dpd-uk".
  static Carrier? named(String? name) {
    final n = (name ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (n.isEmpty) return null;
    if (n.contains('royalmail')) return royalMail;
    if (n.contains('parcelforce')) return parcelforce;
    if (n.contains('dpdlocal')) return dpdLocal;
    if (n.startsWith('dpd')) return dpd;
    if (n.contains('evri') || n.contains('hermes')) return evri;
    if (n.contains('yodel')) return yodel;
    if (n.startsWith('dhl')) return dhl;
    if (n == 'ups' || n.startsWith('upsm') || n.startsWith('unitedparcel')) {
      return ups;
    }
    if (n.startsWith('fedex')) return fedex;
    if (n.startsWith('amazon')) return amazon;
    if (n.startsWith('inpost')) return inpost;
    return null;
  }
}

/// A parcel as shared: who is carrying it, its tracking number where one
/// could be found, and the page to look at it on.
class ParcelRef {
  const ParcelRef({required this.carrier, required this.url, this.number});

  final Carrier carrier;

  /// In capitals, as carriers print them. Null for a link that names no
  /// number — an Amazon order's — which can be looked at but not tracked.
  final String? number;
  final String url;

  /// What makes two shares the same parcel.
  String get key => number ?? url;

  /// [url] came with it, rather than being made from the number: a page
  /// that goes straight to the parcel, where the made one is a search.
  bool get linked {
    final n = number;
    return n == null || url != of(carrier, n).url;
  }

  @override
  String toString() => 'ParcelRef(${carrier.id}, $number, $url)';

  /// The parcel [text] is about, or null when it reads as something else.
  ///
  /// A link to a parcel on a carrier's site is one — a link with its number
  /// in it — wherever it is in the text;
  /// so is a number in a carrier's own unmistakable format — Royal Mail's
  /// `AB123456789GB`, UPS's `1Z…`. A bare run of digits could be anything,
  /// and counts only beside the carrier's name ("DPD 15501234567890"), or
  /// when [explicit] says the sender meant a parcel.
  static ParcelRef? find(String text, {bool explicit = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 4000) return null;
    for (final m in _url.allMatches(trimmed)) {
      final uri = Uri.tryParse(_tidyUrl(m[0]!));
      if (uri == null || uri.host.isEmpty) continue;
      final found = _fromLink(uri);
      if (found != null) return found;
    }
    final hinted = _hint(trimmed);
    final upper = trimmed.toUpperCase();
    for (final (pattern, carrier) in _formats) {
      final m = pattern.firstMatch(upper);
      if (m == null) continue;
      final number = m[1] ?? m[0]!;
      final shaped = carrier(number);
      // The shape says more than the words ("your Amazon order, UPS
      // 1Z…"), except where it is shared: post from abroad is anyone's,
      // and Parcelforce prints Royal Mail's format too.
      final vague =
          shaped == Carrier.unknown ||
          (shaped == Carrier.royalMail && hinted == Carrier.parcelforce);
      return of(vague ? hinted ?? shaped : shaped, number);
    }
    // A carrier named beside a run of digits, in a few words or words about
    // a delivery: "DPD 15501234567890", not a note that mentions Amazon and
    // a phone number.
    if (hinted != null && (explicit || _aboutDelivery(trimmed))) {
      for (final m in _digits.allMatches(upper)) {
        final n = m[0]!;
        // A UK phone number, not a parcel.
        if (n.length == 11 && n.startsWith('0')) continue;
        return of(hinted, n);
      }
    }
    if (explicit) {
      // The longest run of letters and digits with a digit in it: what is
      // left of "my number is 1234-5678-90" once the words are passed over.
      final tokens = [
        for (final m in _token.allMatches(upper))
          if (RegExp(r'\d').hasMatch(m[0]!)) m[0]!.replaceAll('-', ''),
      ]..sort((a, b) => b.length.compareTo(a.length));
      final best = tokens.where((t) => t.length >= 6).firstOrNull;
      if (best != null) return of(hinted ?? Carrier.unknown, best);
    }
    return null;
  }

  /// [number] with [carrier]'s own page for it.
  static ParcelRef of(Carrier carrier, String number) {
    final n = number.toUpperCase();
    final page = carrier.page ?? Carrier.unknown.page!;
    return ParcelRef(
      carrier: carrier,
      number: n,
      url: page.replaceAll('{n}', Uri.encodeComponent(n)),
    );
  }

  static final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// Punctuation a sentence put after a link, not part of it.
  static String _tidyUrl(String s) => s.replaceAll(RegExp(r'[).,;:!?]+$'), '');

  /// Letters and digits, possibly hyphenated, as a tracking number is.
  static final _token = RegExp(r'[A-Z0-9][A-Z0-9-]{4,38}[A-Z0-9]');

  /// Eight to twenty-two digits on their own: DPD's 14, DHL's 10.
  static final _digits = RegExp(r'(?<![A-Z0-9])\d{8,22}(?![A-Z0-9])');

  /// Numbers whose shape says who carries them.
  static final List<(RegExp, Carrier Function(String))> _formats = [
    // The UPU's S10: two letters, nine digits, the country. Royal Mail's
    // own end GB; any other is post from abroad, handed over at the border.
    (
      RegExp(r'(?<![A-Z0-9])([A-Z]{2}\d{9}[A-Z]{2})(?![A-Z0-9])'),
      (n) => n.endsWith('GB') ? Carrier.royalMail : Carrier.unknown,
    ),
    (RegExp(r'(?<![A-Z0-9])(1Z[0-9A-Z]{16})(?![A-Z0-9])'), (_) => Carrier.ups),
    (RegExp(r'(?<![A-Z0-9])(TBA\d{9,12})(?![A-Z0-9])'), (_) => Carrier.amazon),
    (RegExp(r'(?<![A-Z0-9])(JD\d{16,18})(?![A-Z0-9])'), (_) => Carrier.yodel),
    // Evri's barcodes: an H, then fifteen letters and digits.
    (
      RegExp(r'(?<![A-Z0-9])(H(?=[0-9A-Z]*\d)[0-9A-Z]{15})(?![A-Z0-9])'),
      (_) => Carrier.evri,
    ),
  ];

  /// The carrier the words name: "your DPD parcel", "Evri".
  static Carrier? _hint(String text) {
    final t = ' ${text.toLowerCase()} ';
    bool has(String w) => RegExp('(^|[^a-z])$w([^a-z]|\$)').hasMatch(t);
    if (has('royal ?mail')) return Carrier.royalMail;
    if (has('parcel ?force')) return Carrier.parcelforce;
    if (has('dpd ?local')) return Carrier.dpdLocal;
    if (has('dpd')) return Carrier.dpd;
    if (has('evri') || has('hermes')) return Carrier.evri;
    if (has('yodel')) return Carrier.yodel;
    if (has('dhl')) return Carrier.dhl;
    // In capitals only: "ups and downs" is not a courier.
    if (RegExp(r'(^|[^A-Za-z])UPS([^A-Za-z]|$)').hasMatch(text)) {
      return Carrier.ups;
    }
    if (has('fed ?ex')) return Carrier.fedex;
    if (has('inpost')) return Carrier.inpost;
    if (has('amazon')) return Carrier.amazon;
    return null;
  }

  /// A few words, or words about a delivery.
  static bool _aboutDelivery(String text) =>
      text.length <= 60 ||
      RegExp(
        r'parcel|package|tracking|track|deliver|shipment|shipped|dispatch|'
        r'consignment|courier',
        caseSensitive: false,
      ).hasMatch(text);

  /// The parcel a link is to, or null when it is a link to anything else.
  static ParcelRef? _fromLink(Uri uri) {
    final host = uri.host.toLowerCase();
    bool on(String domain) => host == domain || host.endsWith('.$domain');
    final carrier = switch (host) {
      _ when on('royalmail.com') => Carrier.royalMail,
      _ when on('parcelforce.com') => Carrier.parcelforce,
      _ when on('dpdlocal.co.uk') => Carrier.dpdLocal,
      _ when on('dpd.co.uk') => Carrier.dpd,
      _ when on('evri.com') || on('myhermes.co.uk') => Carrier.evri,
      _ when on('yodel.co.uk') => Carrier.yodel,
      _
          when on('dhl.com') ||
              on('dhl.co.uk') ||
              on('dhlparcel.co.uk') ||
              on('dhlparcel.com') =>
        Carrier.dhl,
      _ when on('ups.com') => Carrier.ups,
      _ when on('fedex.com') => Carrier.fedex,
      _ when on('inpost.co.uk') => Carrier.inpost,
      _ when _amazon.hasMatch(host) => Carrier.amazon,
      _ => null,
    };
    // Trackers of every carrier's parcels: the number is all they hold.
    final aggregator =
        on('17track.net') || on('parcelsapp.com') || on('ship24.com');

    final number = _numberIn(uri);
    if (carrier == Carrier.amazon) {
      // A product or a basket is not a parcel; only its delivery pages are.
      final path = uri.path.toLowerCase();
      final tracking =
          path.contains('progress-tracker') ||
          path.contains('ship-track') ||
          path.contains('shiptrack') ||
          path.contains('/tracking');
      if (!tracking) return null;
      return ParcelRef(
        carrier: carrier!,
        number: number != null && number.startsWith('TBA') ? number : null,
        url: uri.toString(),
      );
    }
    if (carrier != null) {
      // Only a link with a number in it: the rest of a carrier's site — its
      // news, its prices, its tracking page before a number is put in — is
      // not a parcel, and could never be tracked as one.
      if (number == null) return null;
      // The link as shared, which goes straight to the parcel — DPD's
      // carries a code of its own after the number that its search page
      // would otherwise ask for.
      return ParcelRef(carrier: carrier, number: number, url: uri.toString());
    }
    if (number == null) return null;
    if (aggregator) return of(_shaped(number) ?? Carrier.unknown, number);
    // Any other site's: a number in a carrier's own shape, or a tracking
    // page naming one in the way tracking pages do. A music service's
    // `/track/<id>` is neither — the id is in the path, not a parameter.
    if (_notParcels.any(on)) return null;
    final shaped = _shaped(number);
    if (shaped != null) {
      return ParcelRef(carrier: shaped, number: number, url: uri.toString());
    }
    final whole = '$host${uri.path}#${uri.fragment}'.toLowerCase();
    if (whole.contains('track') && _numberInParams(uri) != null) {
      return ParcelRef(
        carrier: Carrier.unknown,
        number: number,
        url: uri.toString(),
      );
    }
    return null;
  }

  /// Sites with "track" in their links that are never parcels.
  static const _notParcels = [
    'spotify.com',
    'youtube.com',
    'youtu.be',
    'soundcloud.com',
    'apple.com',
    'deezer.com',
    'tidal.com',
    'last.fm',
    'bandcamp.com',
    'strava.com',
  ];

  /// The carrier [number]'s shape alone says, if any.
  static Carrier? _shaped(String number) {
    for (final (pattern, carrier) in _formats) {
      final m = pattern.firstMatch(number);
      if (m != null && (m[1] ?? m[0]) == number) return carrier(number);
    }
    return null;
  }

  static final _amazon = RegExp(r'(^|\.)amazon\.(co\.uk|com|de|fr|it|es|nl)$');

  /// Query parameters a tracking number goes in, lower-cased.
  static const _numberParams = {
    'tracknumber',
    'trackingnumber',
    'tracking_number',
    'trackingid',
    'tracking-id',
    'tracking',
    'tracknum',
    'tracknums',
    'trknbr',
    'tracknumbers',
    'trackno',
    'inquirynumber1',
    'parcel',
    'parcelnumber',
    'parcelcode',
    'parcelid',
    'barcode',
    'reference',
    'consignment',
    'con',
    'awb',
    'number',
    'nums',
    'p',
  };

  static bool _named(String param) =>
      _numberParams.contains(param.toLowerCase());

  /// The tracking number in [uri]: a parameter named for one, a path segment
  /// shaped like one, or the same in the part after `#` — Royal Mail's and
  /// 17TRACK's pages keep it there.
  static String? _numberIn(Uri uri) {
    String? fromPath(String path) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      // The segment after one naming what follows: /parcels/<n>,
      // /tracking-results/<n>, /track/parcel/<n>/details.
      for (var i = 0; i < segments.length - 1; i++) {
        final s = segments[i].toLowerCase();
        if (s.contains('parcel') ||
            s.contains('track') ||
            s.contains('result') ||
            s == 'shipment' ||
            s == 'shipments') {
          final n = _clean(segments[i + 1]);
          if (n != null) return n;
        }
      }
      return null;
    }

    return _numberInParams(uri) ??
        fromPath(uri.path) ??
        fromPath(uri.fragment.split('?').first);
  }

  /// A number in a parameter named for one, in the query or after the `#`.
  static String? _numberInParams(Uri uri) {
    Map<String, String> params(String query) {
      try {
        return Uri.splitQueryString(query);
      } on FormatException {
        return const {};
      } on ArgumentError {
        return const {};
      }
    }

    final fragment = uri.fragment;
    final hashQuery = fragment.contains('?')
        ? fragment.substring(fragment.indexOf('?') + 1)
        : (fragment.contains('=') ? fragment : '');
    for (final q in [uri.queryParameters, params(hashQuery)]) {
      for (final e in q.entries) {
        if (!_named(e.key)) continue;
        final n = _clean(e.value);
        if (n != null) return n;
      }
    }
    return null;
  }

  /// [v] as a tracking number — capitals, no spaces or hyphens — or null
  /// when it cannot be one. DPD's `15501234567890*19826` is the number
  /// before the star.
  static String? _clean(String? v) {
    if (v == null) return null;
    String s;
    try {
      s = Uri.decodeComponent(v);
    } on ArgumentError {
      s = v;
    }
    s = s.split(RegExp(r'[*,]')).first.trim();
    s = s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (s.length < 6 || s.length > 40) return null;
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(s)) return null;
    if (!RegExp(r'\d').hasMatch(s)) return null;
    return s;
  }
}
