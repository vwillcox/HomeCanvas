import 'dart:convert';
import 'dart:io';

import 'private_file.dart';

/// Netscape `cookies.txt` files, as browser extensions export them and as
/// yt-dlp reads and writes them.
///
/// Used for signing the panel in to a video site from a browser elsewhere:
/// the password is typed there, and only the site's own cookies come here.
class CookieFile {
  CookieFile._();

  /// [text] cut down to the cookies of [domains] (and their subdomains), or
  /// null when it holds none of them — or not one named [mustHave], when that
  /// is the cookie the sign-in rests on.
  static String? filter(String text, List<String> domains, {String? mustHave}) {
    final kept = <String>[];
    var found = mustHave == null;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trimRight();
      // "#HttpOnly_" marks an HttpOnly cookie, not a comment — and the
      // sign-in cookies are exactly those.
      final bare = line.startsWith('#HttpOnly_')
          ? line.substring('#HttpOnly_'.length)
          : line;
      if (bare.isEmpty || bare.startsWith('#')) continue;
      final fields = bare.split('\t');
      if (fields.length != 7) continue;
      final domain = fields[0].toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      if (domains.any((d) => domain == d || domain.endsWith('.$d'))) {
        kept.add(line);
        if (fields[5] == mustHave) found = true;
      }
    }
    if (kept.isEmpty || !found) return null;
    return '# Netscape HTTP Cookie File\n'
        '# ${domains.join(' and ')} only, kept by HomeCanvas.\n'
        '${kept.join('\n')}\n';
  }

  /// The value of the cookie called [name] in [text], or null.
  static String? value(String text, String name) {
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.startsWith('#HttpOnly_')
          ? raw.substring('#HttpOnly_'.length)
          : raw;
      if (line.startsWith('#')) continue;
      final fields = line.trimRight().split('\t');
      if (fields.length == 7 && fields[5] == name) return fields[6];
    }
    return null;
  }

  /// Writes [contents] to [path] readable by this user only — from before
  /// anything is in it, since these are as good as a password while they
  /// last — and moves it into place whole.
  static Future<void> writePrivate(String path, String contents) =>
      writePrivateFile(path, contents);

  /// Copies [domains]' cookies out of a Firefox profile into a `cookies.txt`
  /// at [path], for a sign-in made in the kiosk's own browser.
  ///
  /// Firefox is stopped to close the sign-in window, which leaves its latest
  /// cookies in the database's write-ahead log; that is merged in first.
  /// Python's sqlite3 does the reading — the installer needs Python already.
  /// Returns whether any cookies were found.
  static Future<bool> fromFirefox(
      String profileDir, String path, List<String> domains) async {
    final db = '$profileDir/cookies.sqlite';
    if (!await File(db).exists()) return false;
    // Firefox is still letting go of the file for a moment after the kill.
    await Future<void>.delayed(const Duration(seconds: 1));
    const script = r'''
import os, sqlite3, sys
db, out, domains = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
c = sqlite3.connect(db)
c.execute("pragma wal_checkpoint(TRUNCATE)")
rows = c.execute("select host, path, isSecure, expiry, name, value from moz_cookies").fetchall()
lines = ["# Netscape HTTP Cookie File"]
for host, path, secure, expiry, name, value in rows:
    bare = host.lstrip(".").lower()
    if not any(bare == d or bare.endswith("." + d) for d in domains):
        continue
    lines.append("\t".join([host, "TRUE" if host.startswith(".") else "FALSE",
        path, "TRUE" if secure else "FALSE", str(expiry), name, value]))
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.write("\n".join(lines) + "\n")
print(len(lines) - 1)
''';
    try {
      await File(path).parent.create(recursive: true);
      final r = await Process.run(
          'python3', ['-c', script, db, path, domains.join(',')]);
      return r.exitCode == 0 && (int.tryParse('${r.stdout}'.trim()) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }
}
