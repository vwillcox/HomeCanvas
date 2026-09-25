import 'package:flutter/material.dart';
import '../look.dart';

import '../config/credits.dart';
import '../widgets/glass.dart';

/// Version shown on the About screen. Keep in step with pubspec.yaml.
const String kAppVersion = '1.0.0';

/// Attribution for everything this app is built on: Dart packages, system
/// libraries, network services, and the code that came from elsewhere.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        title: 'About',
        subtitle: 'Version, libraries, licences and credits',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
        children: [
          const _Header(),

          _SectionTitle('Dart packages', accent),
          Text(
            'Open-source packages this app depends on directly.',
            style: TextStyle(color: context.look.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...kDartPackages.map((c) => _CreditTile(credit: c)),

          _SectionTitle('System libraries', accent),
          Text(
            'Provided by the operating system.',
            style: TextStyle(color: context.look.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...kSystemLibraries.map((c) => _CreditTile(credit: c)),

          _SectionTitle('Services', accent),
          Text(
            'Network services this app talks to.',
            style: TextStyle(color: context.look.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...kServices.map((c) => _CreditTile(credit: c)),

          _SectionTitle('Credits and sources', accent),
          Text(
            'Almost all of the code here was written for this project. These '
            'parts came from, or were adapted from, elsewhere.',
            style: TextStyle(color: context.look.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...kSourceCredits.map((s) => _SourceTile(source: s)),

          const SizedBox(height: 28),
          const _Licence(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_library,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'HomeCanvas',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Version $kAppVersion',
                    style: TextStyle(color: context.look.textSecondary, fontSize: 17),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A touchscreen photo frame and media browser for a self-hosted '
            'Immich server, built for a Raspberry Pi with a DSI touch display.',
            style: TextStyle(fontSize: 17, color: context.look.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 10),
          SelectableText(
            'https://github.com/vwillcox/HomeCanvas',
            style: TextStyle(fontSize: 16, color: context.look.accent),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color accent;
  const _SectionTitle(this.text, this.accent);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Divider(color: accent.withValues(alpha: 0.25), height: 1),
        ],
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  final Credit credit;
  const _CreditTile({required this.credit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.look.solidSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  credit.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.look.wash(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  credit.licence,
                  style: TextStyle(fontSize: 14, color: context.look.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            credit.purpose,
            style: TextStyle(fontSize: 16, color: context.look.textSecondary),
          ),
          const SizedBox(height: 6),
          SelectableText(
            credit.url,
            style: TextStyle(fontSize: 15, color: context.look.accent),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final SourceCredit source;
  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.look.solidSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.what,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            source.detail,
            style: TextStyle(
              fontSize: 16,
              color: context.look.textSecondary,
              height: 1.35,
            ),
          ),
          if (source.url != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              source.url!,
              style: TextStyle(fontSize: 15, color: context.look.accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _Licence extends StatelessWidget {
  const _Licence();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.look.solidSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.look.wash(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Licence',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'HomeCanvas is released under the MIT Licence. It talks only to '
            'your own Immich server and to Open-Meteo for the weather — there '
            'is no analytics and no third-party tracking.',
            style: TextStyle(fontSize: 16, color: context.look.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }
}
