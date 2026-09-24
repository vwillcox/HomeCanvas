import 'dart:math' as math;

/// Sunrise, sunset and the moon's phase, worked out on the Pi.
///
/// No network: the sun from NOAA's published approximation, good to a minute
/// or so at the latitudes anyone would hang this panel; the moon from the
/// length of the synodic month, good to within a day of the named phases.
/// Both are plenty for a wall, and neither ever says "could not reach".
class SunDay {
  const SunDay({
    required this.sunrise,
    required this.sunset,
    required this.solarNoon,
    this.polar,
  });

  /// Local times. Null on a day the sun does not rise or does not set.
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime solarNoon;

  /// Set only when there is no sunrise and sunset to speak of: true for a
  /// day the sun never sets, false for one it never rises.
  final bool? polar;

  Duration get dayLength => sunrise == null || sunset == null
      ? (polar == true ? const Duration(hours: 24) : Duration.zero)
      : sunset!.difference(sunrise!);

  /// How far through the daylight [now] is, 0 at sunrise and 1 at sunset;
  /// below 0 before dawn and above 1 after dusk.
  double progress(DateTime now) {
    if (sunrise == null || sunset == null) return polar == true ? 0.5 : -1;
    final total = sunset!.difference(sunrise!).inSeconds;
    if (total <= 0) return -1;
    return now.difference(sunrise!).inSeconds / total;
  }
}

class SunMoon {
  SunMoon._();

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;

  /// The sun for the local calendar day [date], at [latitude], [longitude]
  /// (degrees, east positive).
  static SunDay sun(DateTime date, double latitude, double longitude) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final dayOfYear = day.difference(DateTime.utc(date.year)).inDays + 1;
    final daysInYear = DateTime.utc(
      date.year + 1,
    ).difference(DateTime.utc(date.year)).inDays;

    // The fractional year, at noon.
    final g = 2 * math.pi / daysInYear * (dayOfYear - 1);
    final eqTime =
        229.18 *
        (0.000075 +
            0.001868 * math.cos(g) -
            0.032077 * math.sin(g) -
            0.014615 * math.cos(2 * g) -
            0.040849 * math.sin(2 * g));
    final decl =
        0.006918 -
        0.399912 * math.cos(g) +
        0.070257 * math.sin(g) -
        0.006758 * math.cos(2 * g) +
        0.000907 * math.sin(2 * g) -
        0.002697 * math.cos(3 * g) +
        0.00148 * math.sin(3 * g);

    final lat = _rad(latitude);
    // 90.833°: the sun's centre below the horizon when its top edge meets
    // it, allowing for refraction — the moment the almanacs call sunrise.
    final cosHa =
        math.cos(_rad(90.833)) / (math.cos(lat) * math.cos(decl)) -
        math.tan(lat) * math.tan(decl);

    DateTime at(double minutesUtc) =>
        day.add(Duration(milliseconds: (minutesUtc * 60000).round())).toLocal();

    final noon = at(720 - 4 * longitude - eqTime);
    if (cosHa > 1) {
      return SunDay(sunrise: null, sunset: null, solarNoon: noon, polar: false);
    }
    if (cosHa < -1) {
      return SunDay(sunrise: null, sunset: null, solarNoon: noon, polar: true);
    }
    final ha = _deg(math.acos(cosHa));
    return SunDay(
      sunrise: at(720 - 4 * (longitude + ha) - eqTime),
      sunset: at(720 - 4 * (longitude - ha) - eqTime),
      solarNoon: noon,
    );
  }

  /// The average length of a lunar month, new moon to new moon.
  static const double synodicDays = 29.530588853;

  /// A known new moon: 6 January 2000, 18:14 UTC.
  static final DateTime _newMoon = DateTime.utc(2000, 1, 6, 18, 14);

  /// How far through its cycle the moon is at [when]: 0 new, 0.5 full.
  static double moonPhase(DateTime when) {
    final days =
        when.toUtc().difference(_newMoon).inSeconds / Duration.secondsPerDay;
    final cycles = days / synodicDays;
    return cycles - cycles.floorToDouble();
  }

  /// The lit share of the moon's face for [phase], 0 to 1.
  static double illumination(double phase) =>
      (1 - math.cos(2 * math.pi * phase)) / 2;

  /// The phase's everyday name.
  static String phaseName(double phase) {
    // The four principal phases are instants; a day either side of each is
    // given its name, which is how the almanacs and the calendars read.
    const day = 1 / synodicDays;
    if (phase < day || phase > 1 - day) return 'New moon';
    if ((phase - 0.25).abs() < day) return 'First quarter';
    if ((phase - 0.5).abs() < day) return 'Full moon';
    if ((phase - 0.75).abs() < day) return 'Last quarter';
    if (phase < 0.25) return 'Waxing crescent';
    if (phase < 0.5) return 'Waxing gibbous';
    if (phase < 0.75) return 'Waning gibbous';
    return 'Waning crescent';
  }

  /// When the moon is next at [target] phase (0.5 for full) after [from].
  static DateTime next(double target, DateTime from) {
    var ahead = target - moonPhase(from);
    if (ahead <= 0.001) ahead += 1;
    return from.add(
      Duration(seconds: (ahead * synodicDays * Duration.secondsPerDay).round()),
    );
  }
}
