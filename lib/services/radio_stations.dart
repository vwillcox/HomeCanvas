/// A station the radio widget can tune to.
class RadioStation {
  /// Stable: it is what a widget's settings keep. Never rename one in place.
  final String id;
  final String name;

  /// Where it broadcasts from, as the editor's dropdown groups it — a
  /// country, or "Internet" for stations that only exist online.
  final String country;

  /// Something mpv can play: an Icecast/Shoutcast stream or an HLS playlist.
  final String url;

  /// What its badge says, where [radioBadge] would not say it well.
  final String? badge;

  const RadioStation(this.id, this.name, this.country, this.url, {this.badge});

  /// The letters on its badge.
  String get letters => badge ?? radioBadge(name);
}

String _bbc(String pool, String id) =>
    'https://as-hls-ww-live.akamaized.net/pool_$pool/live/ww/$id/$id.isml/'
    '$id-audio%3d128000.norewind.m3u8';

/// Stations that come with the app, from around the world: public
/// broadcasters for the most part, whose addresses last, and a few
/// listener-funded internet stations. Each was checked to answer with audio
/// when it was added (2026-10-24); a station that later moves can still be
/// added by its address in the widget's settings.
///
/// The BBC's are its worldwide streams, which play outside the UK too.
final List<RadioStation> radioStations = [
  // United Kingdom
  RadioStation(
    'bbc_radio_1',
    'BBC Radio 1',
    'UK',
    _bbc('01505109', 'bbc_radio_one'),
  ),
  RadioStation(
    'bbc_1xtra',
    'BBC Radio 1Xtra',
    'UK',
    _bbc('92079267', 'bbc_1xtra'),
  ),
  RadioStation(
    'bbc_radio_2',
    'BBC Radio 2',
    'UK',
    _bbc('74208725', 'bbc_radio_two'),
  ),
  RadioStation(
    'bbc_radio_3',
    'BBC Radio 3',
    'UK',
    _bbc('23461179', 'bbc_radio_three'),
  ),
  RadioStation(
    'bbc_radio_4',
    'BBC Radio 4',
    'UK',
    _bbc('55057080', 'bbc_radio_fourfm'),
  ),
  RadioStation(
    'bbc_radio_4_extra',
    'BBC Radio 4 Extra',
    'UK',
    _bbc('26173715', 'bbc_radio_four_extra'),
  ),
  RadioStation(
    'bbc_radio_5_live',
    'BBC Radio 5 Live',
    'UK',
    _bbc('89021708', 'bbc_radio_five_live'),
  ),
  RadioStation(
    'bbc_6music',
    'BBC Radio 6 Music',
    'UK',
    _bbc('81827798', 'bbc_6music'),
  ),
  RadioStation(
    'bbc_scotland',
    'BBC Radio Scotland',
    'UK',
    _bbc('43322914', 'bbc_radio_scotland_fm'),
  ),
  RadioStation(
    'bbc_wales',
    'BBC Radio Wales',
    'UK',
    _bbc('97517794', 'bbc_radio_wales_fm'),
  ),
  RadioStation(
    'bbc_cymru',
    'BBC Radio Cymru',
    'UK',
    _bbc('24792333', 'bbc_radio_cymru'),
  ),
  RadioStation(
    'bbc_ulster',
    'BBC Radio Ulster',
    'UK',
    _bbc('31244774', 'bbc_radio_ulster'),
  ),
  RadioStation(
    'bbc_world_service',
    'BBC World Service',
    'UK',
    'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service',
  ),
  RadioStation(
    'classic_fm',
    'Classic FM',
    'UK',
    'https://media-ice.musicradio.com/ClassicFMMP3',
  ),
  RadioStation('lbc', 'LBC', 'UK', 'https://media-ice.musicradio.com/LBCUKMP3'),
  RadioStation(
    'capital',
    'Capital',
    'UK',
    'https://media-ice.musicradio.com/CapitalMP3',
  ),
  RadioStation(
    'heart_london',
    'Heart London',
    'UK',
    'https://media-ice.musicradio.com/HeartLondonMP3',
  ),
  RadioStation(
    'smooth',
    'Smooth Radio',
    'UK',
    'https://media-ice.musicradio.com/SmoothUKMP3',
  ),
  RadioStation(
    'talksport',
    'talkSPORT',
    'UK',
    'https://radio.talksport.com/stream',
  ),
  RadioStation(
    'times_radio',
    'Times Radio',
    'UK',
    'https://timesradio.wireless.radio/stream',
  ),
  RadioStation(
    'lyca_gold',
    'Lyca Gold',
    'UK',
    'https://listen-lycaradio.sharp-stream.com/1035.mp3',
  ),
  // Ireland
  RadioStation(
    'rte_radio_1',
    'RTÉ Radio 1',
    'Ireland',
    'https://icecast.rte.ie/radio1',
  ),
  RadioStation('rte_2fm', 'RTÉ 2FM', 'Ireland', 'https://icecast.rte.ie/2fm'),
  RadioStation(
    'rte_lyric',
    'RTÉ lyric fm',
    'Ireland',
    'https://icecast.rte.ie/lyric',
  ),
  // France
  RadioStation(
    'fip',
    'FIP',
    'France',
    'https://icecast.radiofrance.fr/fip-hifi.aac',
  ),
  RadioStation(
    'france_inter',
    'France Inter',
    'France',
    'https://icecast.radiofrance.fr/franceinter-hifi.aac',
  ),
  RadioStation(
    'france_culture',
    'France Culture',
    'France',
    'https://icecast.radiofrance.fr/franceculture-hifi.aac',
  ),
  RadioStation(
    'france_musique',
    'France Musique',
    'France',
    'https://icecast.radiofrance.fr/francemusique-hifi.aac',
  ),
  RadioStation(
    'radio_nova',
    'Radio Nova',
    'France',
    'https://novazz.ice.infomaniak.ch/novazz-128.mp3',
  ),
  // Germany
  RadioStation(
    'dlf',
    'Deutschlandfunk',
    'Germany',
    'https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3',
  ),
  RadioStation(
    'dlf_kultur',
    'Deutschlandfunk Kultur',
    'Germany',
    'https://st02.sslstream.dlf.de/dlf/02/128/mp3/stream.mp3',
  ),
  RadioStation(
    '1live',
    '1LIVE',
    'Germany',
    'https://wdr-1live-live.icecastssl.wdr.de/wdr/1live/live/mp3/128/stream.mp3',
  ),
  RadioStation(
    'bayern_3',
    'Bayern 3',
    'Germany',
    'https://dispatcher.rndfnk.com/br/br3/live/mp3/mid',
  ),
  RadioStation(
    'ndr_2',
    'NDR 2',
    'Germany',
    'https://icecast.ndr.de/ndr/ndr2/hamburg/mp3/128/stream.mp3',
  ),
  RadioStation(
    'ffh',
    'Hit Radio FFH',
    'Germany',
    'https://mp3.ffh.de/radioffh/hqlivestream.mp3',
  ),
  // Netherlands and Belgium
  RadioStation(
    'npo_radio_1',
    'NPO Radio 1',
    'Netherlands',
    'https://icecast.omroep.nl/radio1-bb-mp3',
  ),
  RadioStation(
    'npo_radio_2',
    'NPO Radio 2',
    'Netherlands',
    'https://icecast.omroep.nl/radio2-bb-mp3',
  ),
  RadioStation(
    'npo_3fm',
    'NPO 3FM',
    'Netherlands',
    'https://icecast.omroep.nl/3fm-bb-mp3',
  ),
  RadioStation(
    'vrt_radio_1',
    'VRT Radio 1',
    'Belgium',
    'https://icecast.vrtcdn.be/radio1-high.mp3',
  ),
  RadioStation(
    'stubru',
    'Studio Brussel',
    'Belgium',
    'https://icecast.vrtcdn.be/stubru-high.mp3',
  ),
  // Switzerland and Austria
  RadioStation(
    'swiss_jazz',
    'Radio Swiss Jazz',
    'Switzerland',
    'https://stream.srg-ssr.ch/m/rsj/mp3_128',
  ),
  RadioStation(
    'swiss_classic',
    'Radio Swiss Classic',
    'Switzerland',
    'https://stream.srg-ssr.ch/m/rsc_de/mp3_128',
  ),
  RadioStation(
    'swiss_pop',
    'Radio Swiss Pop',
    'Switzerland',
    'https://stream.srg-ssr.ch/m/rsp/mp3_128',
  ),
  RadioStation(
    'fm4',
    'FM4',
    'Austria',
    'https://orf-live.ors-shoutcast.at/fm4-q2a',
  ),
  RadioStation(
    'oe1',
    'Ö1',
    'Austria',
    'https://orf-live.ors-shoutcast.at/oe1-q2a',
  ),
  // Southern Europe
  RadioStation(
    'rai_radio_1',
    'Rai Radio 1',
    'Italy',
    'https://icestreaming.rai.it/1.mp3',
  ),
  RadioStation(
    'rai_radio_2',
    'Rai Radio 2',
    'Italy',
    'https://icestreaming.rai.it/2.mp3',
  ),
  RadioStation(
    'rai_radio_3',
    'Rai Radio 3',
    'Italy',
    'https://icestreaming.rai.it/3.mp3',
  ),
  RadioStation(
    'rne',
    'RNE Radio Nacional',
    'Spain',
    'https://dispatcher.rndfnk.com/crtve/rne1/mad/mp3/high',
  ),
  RadioStation(
    'cadena_ser',
    'Cadena SER',
    'Spain',
    'https://playerservices.streamtheworld.com/api/livestream-redirect/CADENASER.mp3',
  ),
  RadioStation(
    'antena_1',
    'Antena 1',
    'Portugal',
    'https://radiocast.rtp.pt/antena180a.mp3',
  ),
  RadioStation(
    'antena_3',
    'Antena 3',
    'Portugal',
    'https://radiocast.rtp.pt/antena380a.mp3',
  ),
  // Nordics
  RadioStation(
    'sr_p1',
    'Sveriges Radio P1',
    'Sweden',
    'https://sverigesradio.se/topsy/direkt/132-hi-aac',
  ),
  RadioStation(
    'sr_p2',
    'Sveriges Radio P2',
    'Sweden',
    'https://sverigesradio.se/topsy/direkt/163-hi-aac',
  ),
  RadioStation(
    'sr_p3',
    'Sveriges Radio P3',
    'Sweden',
    'https://sverigesradio.se/topsy/direkt/164-hi-aac',
  ),
  RadioStation(
    'nrk_p1',
    'NRK P1',
    'Norway',
    'https://lyd.nrk.no/nrk_radio_p1_ostlandssendingen_mp3_h',
  ),
  RadioStation(
    'nrk_p3',
    'NRK P3',
    'Norway',
    'https://lyd.nrk.no/nrk_radio_p3_mp3_h',
  ),
  RadioStation(
    'nrk_jazz',
    'NRK Jazz',
    'Norway',
    'https://lyd.nrk.no/nrk_radio_jazz_mp3_h',
  ),
  RadioStation(
    'dr_p1',
    'DR P1',
    'Denmark',
    'https://live-icy.dr.dk/A/A03H.mp3',
  ),
  RadioStation(
    'dr_p3',
    'DR P3',
    'Denmark',
    'https://live-icy.dr.dk/A/A05H.mp3',
  ),
  RadioStation(
    'dr_p8_jazz',
    'DR P8 Jazz',
    'Denmark',
    'https://live-icy.dr.dk/A/A22H.mp3',
  ),
  RadioStation(
    'yle_radio_1',
    'Yle Radio 1',
    'Finland',
    'https://icecast.live.yle.fi/radio/YleRadio1/icecast.audio',
  ),
  RadioStation(
    'yle_radio_suomi',
    'Yle Radio Suomi',
    'Finland',
    'https://icecast.live.yle.fi/radio/YleRS/icecast.audio',
  ),
  RadioStation(
    'yle_x',
    'YleX',
    'Finland',
    'https://icecast.live.yle.fi/radio/YleX/icecast.audio',
  ),
  // Eastern Europe
  RadioStation(
    'kiss_fm_ua',
    'Kiss FM',
    'Ukraine',
    'https://online.kissfm.ua/KissFM',
  ),
  // North America
  RadioStation(
    'npr',
    'NPR News',
    'USA',
    'https://npr-ice.streamguys1.com/live.mp3',
  ),
  RadioStation('wnyc', 'WNYC 93.9 FM', 'USA', 'https://fm939.wnyc.org/wnycfm'),
  RadioStation('wqxr', 'WQXR', 'USA', 'https://stream.wqxr.org/wqxr'),
  RadioStation(
    'kexp',
    'KEXP Seattle',
    'USA',
    'https://kexp.streamguys1.com/kexp160.aac',
  ),
  RadioStation('kcrw', 'KCRW', 'USA', 'https://streams.kcrw.com/kcrw_mp3'),
  RadioStation(
    'kcrw_e24',
    'KCRW Eclectic24',
    'USA',
    'https://streams.kcrw.com/e24_mp3',
  ),
  RadioStation('wfmu', 'WFMU', 'USA', 'https://stream0.wfmu.org/freeform-128k'),
  RadioStation(
    'jazz24',
    'Jazz24',
    'USA',
    'https://knkx-live-a.edge.audiocdn.com/6285_256k',
  ),
  RadioStation(
    'cbc_radio_one',
    'CBC Radio One Toronto',
    'Canada',
    'https://26183.live.streamtheworld.com/CBLAFM_CBC_SC',
  ),
  RadioStation(
    'los40_mx',
    'Los 40 México',
    'Mexico',
    'https://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_MEXICO_SC',
  ),
  // South America
  RadioStation(
    'radio_disney_br',
    'Rádio Disney',
    'Brazil',
    'https://playerservices.streamtheworld.com/api/livestream-redirect/DISNEY_BRA_SP.mp3',
  ),
  RadioStation(
    'radio_mitre',
    'Radio Mitre',
    'Argentina',
    'https://playerservices.streamtheworld.com/api/livestream-redirect/AM790_56AAC.aac',
  ),
  // Africa
  RadioStation(
    'capital_fm_ke',
    'Capital FM',
    'Kenya',
    'https://atunwadigital.streamguys1.com/capitalfm',
  ),
  RadioStation(
    '5fm',
    '5FM',
    'South Africa',
    'https://playerservices.streamtheworld.com/api/livestream-redirect/5FMAAC.aac',
  ),
  // Asia
  RadioStation(
    'nhk_world',
    'NHK World Radio Japan',
    'Japan',
    'https://masterpl.hls.nhkworld.jp/hls/r1/live/master.m3u8',
  ),
  RadioStation(
    'rthk_radio_1',
    'RTHK Radio 1',
    'Hong Kong',
    'https://stm1.rthk.hk/radio1',
  ),
  RadioStation(
    'arirang',
    'Arirang Radio',
    'South Korea',
    'http://amdlive.ctnd.com.edgesuite.net/arirang_3ch/smil:arirang_3ch.smil/playlist.m3u8',
  ),
  RadioStation(
    'vividh_bharati',
    'AIR Vividh Bharati',
    'India',
    'https://air.pc.cdn.bitgravity.com/air/live/pbaudio001/playlist.m3u8',
  ),
  // Oceania
  RadioStation(
    'triple_j',
    'triple j',
    'Australia',
    'https://streaming.abc-cdn.net.au/audio/hls/triplejnsw.m3u8',
  ),
  RadioStation(
    'double_j',
    'Double J',
    'Australia',
    'https://streaming.abc-cdn.net.au/audio/hls/doublejnsw.m3u8',
  ),
  RadioStation(
    'abc_classic',
    'ABC Classic',
    'Australia',
    'https://mediaserviceslive.akamaized.net/hls/live/2038316/classicfmnsw/masterhq.m3u8',
  ),
  RadioStation(
    'abc_rn',
    'ABC Radio National',
    'Australia',
    'https://abc.streamguys1.com/live/rnnsw/icecast.audio',
  ),
  RadioStation(
    'rnz_national',
    'RNZ National',
    'New Zealand',
    'http://radionz-ice.streamguys.com/national.mp3',
  ),
  RadioStation(
    'rnz_concert',
    'RNZ Concert',
    'New Zealand',
    'http://radionz-ice.streamguys.com/concert.mp3',
  ),
  // Internet only
  RadioStation(
    'radio_paradise',
    'Radio Paradise',
    'Internet',
    'https://stream.radioparadise.com/aac-320',
  ),
  RadioStation(
    'radio_paradise_mellow',
    'Radio Paradise Mellow',
    'Internet',
    'https://stream.radioparadise.com/mellow-320',
  ),
  RadioStation(
    'somafm_groove_salad',
    'SomaFM Groove Salad',
    'Internet',
    'https://ice2.somafm.com/groovesalad-128-mp3',
  ),
  RadioStation(
    'somafm_drone_zone',
    'SomaFM Drone Zone',
    'Internet',
    'https://ice2.somafm.com/dronezone-128-mp3',
  ),
  RadioStation(
    'somafm_secret_agent',
    'SomaFM Secret Agent',
    'Internet',
    'https://ice2.somafm.com/secretagent-128-mp3',
  ),
  RadioStation(
    'somafm_indie_pop',
    'SomaFM Indie Pop Rocks',
    'Internet',
    'https://ice1.somafm.com/indiepop-128-mp3',
  ),
];

final Map<String, RadioStation> _byId = {
  for (final s in radioStations) s.id: s,
};

RadioStation? radioStation(String id) => _byId[id];

/// id → "UK · BBC Radio 4", for the editor's dropdown, in the order above
/// so each country's stations sit together.
Map<String, String> radioStationChoices() => {
  for (final s in radioStations) s.id: '${s.country} · ${s.name}',
};

/// The stations a Radio tile's settings name, in their order: one from the
/// catalogue, or any stream by its address. Rows filled in with neither are
/// left out. [rows] is the tile's `stations` option as saved.
List<RadioStation> radioStationsFrom(Object? rows) {
  final out = <RadioStation>[];
  for (final row in (rows is List ? rows : const []).whereType<Map>()) {
    final url = '${row['url'] ?? ''}'.trim();
    final name = '${row['name'] ?? ''}'.trim();
    if (url.isNotEmpty) {
      final host = Uri.tryParse(url)?.host ?? '';
      out.add(
        RadioStation(
          'url:$url',
          name.isNotEmpty ? name : (host.isNotEmpty ? host : url),
          '',
          url,
        ),
      );
      continue;
    }
    final known = radioStation('${row['station'] ?? ''}');
    if (known == null) continue;
    out.add(
      name.isEmpty
          ? known
          // Renamed, so its badge comes from the new name.
          : RadioStation(known.id, name, known.country, known.url),
    );
  }
  return out;
}

/// Up to four letters to stand for a station on its badge: "R4" for BBC
/// Radio 4, "FM4", "KEXP", "P1" for NRK P1, "SG" for SomaFM Groove Salad.
String radioBadge(String name) {
  final words = name
      .split(RegExp(r'[\s·\-–]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  bool digits(String w) => w.contains(RegExp(r'\d'));
  // A word with a figure in it says most: P1, FM4, 3FM, 1LIVE, 5FM.
  for (final w in words) {
    if (digits(w) && w.length <= 5 && !RegExp(r'^\d+(\.\d+)?$').hasMatch(w)) {
      return w.toUpperCase();
    }
  }
  // A bare number is the word before it, initialled: Radio 4, Antena 1.
  for (final (i, w) in words.indexed) {
    if (i > 0 && RegExp(r'^\d{1,2}$').hasMatch(w)) {
      return '${words[i - 1][0].toUpperCase()}$w';
    }
  }
  // Letters in capitals are already an abbreviation: KEXP, FIP, LBC.
  const plain = {'BBC', 'FM', 'AM', 'HD', 'ABC'};
  for (final w in words) {
    if (w.length >= 2 &&
        w.length <= 5 &&
        w == w.toUpperCase() &&
        w != w.toLowerCase() &&
        !plain.contains(w)) {
      return w;
    }
  }
  // Otherwise the first two words' first letters, an FM or AM kept whole:
  // Smooth Radio is SR, Classic FM is CFM.
  final letters = words
      .where((w) => w.toUpperCase() != 'BBC' && w.toUpperCase() != 'ABC')
      .take(2)
      .map((w) {
        final up = w.toUpperCase();
        return up == 'FM' || up == 'AM' ? up : up[0];
      })
      .join();
  return letters.isEmpty ? words.first[0].toUpperCase() : letters;
}

/// The words of a station's name as said aloud: lower case, figures as
/// words, so "BBC Radio 4" and "radio four" meet. "BBC" and "radio" are
/// left out, being in half the names and often not said.
List<String> _spoken(String s) {
  const figures = {
    '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four', //
    '5': 'five', '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine',
  };
  const skip = {'bbc', 'radio', 'the', 'fm', 'com', 'station'};
  final out = <String>[];
  final text = s
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\d'), (m) => ' ${figures[m[0]]} ')
      .replaceAll(RegExp(r'[^a-z0-9à-ÿ ]+'), ' ');
  for (final w in text.split(' ')) {
    if (w.isNotEmpty && !skip.contains(w)) out.add(w);
  }
  return out;
}

/// The station in [stations] that [said] names best, or null when none is
/// named at all. Every word said must be in the name; between those, the
/// one with the fewest words left over wins, then the earliest. With
/// [whole], only a name said in full.
RadioStation? matchRadioStation(
  String said,
  List<RadioStation> stations, {
  bool whole = false,
}) {
  final want = _spoken(said);
  if (want.isEmpty) return null;
  RadioStation? best;
  var bestExtra = 1 << 30;
  for (final s in stations) {
    final name = _spoken(s.name);
    if (!want.every(name.contains)) continue;
    final extra = name.length - want.length;
    if (whole && extra > 0) continue;
    if (extra < bestExtra) {
      best = s;
      bestExtra = extra;
    }
  }
  return best;
}
