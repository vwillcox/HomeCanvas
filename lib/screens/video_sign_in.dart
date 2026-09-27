import 'package:flutter/material.dart';

import '../services/video_site.dart';
import 'link_viewer_screen.dart';

/// Opens [site]'s own sign-in page in the kiosk's browser, then checks it
/// took. Returns whether the panel is signed in afterwards.
///
/// The password, the second step, the "is this you?" all happen on the
/// site's page, in a browser profile kept for the purpose; the kiosk never
/// sees a password. Its cookies are then copied out of the profile into the
/// same file an upload from a computer makes — see
/// [VideoSite.afterPanelSignIn].
Future<bool> signInOnPanel(BuildContext context, VideoSite site) async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LinkViewerScreen(
      url: site.signInUrl,
      title: 'Sign in to ${site.name}, then tap Close',
      profile: site.loginProfile,
      keepProfile: true,
      // Long enough for a code from a phone and a second attempt at a
      // password; the window is closed by hand long before, normally.
      timeout: const Duration(minutes: 15),
    ),
  ));
  final ok = await site.afterPanelSignIn();
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Signed in to ${site.name}.'
          : 'Not signed in — ${site.name} did not recognise an account.'),
    ));
  }
  return ok;
}
