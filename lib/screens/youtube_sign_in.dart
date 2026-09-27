import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/youtube_service.dart';
import 'link_viewer_screen.dart';

/// Opens YouTube's own sign-in in the kiosk's browser, then checks it took.
///
/// Google's sign-in — the password, the second step, the "is this you?" —
/// happens on Google's page, in a browser profile kept for the purpose; the
/// kiosk never sees a password. yt-dlp then reads that profile's cookies,
/// which is the only way it can use an account now that YouTube has shut its
/// older sign-in route to programs like it.
///
/// Returns whether the kiosk is signed in afterwards.
Future<bool> signInToYouTube(BuildContext context) async {
  final yt = context.read<YouTubeService>();
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const LinkViewerScreen(
      url: YouTubeService.signInUrl,
      title: 'Sign in to YouTube, then tap Close',
      profile: YouTubeService.loginProfile,
      keepProfile: true,
      // Long enough for a code from a phone and a second attempt at a
      // password; the window is closed by hand long before, normally.
      timeout: Duration(minutes: 15),
    ),
  ));
  final ok = await yt.afterPanelSignIn();
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Signed in to YouTube.'
          : 'Not signed in — YouTube did not recognise an account.'),
    ));
  }
  return ok;
}
