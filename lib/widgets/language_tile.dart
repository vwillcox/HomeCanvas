import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/config_service.dart';

/// Settings' language row: the language in use, and a list to choose
/// another from. Each is listed by its own name, with what it is called in
/// English and whether an AI translated it.
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context) {
    final current = L10n.instance.language;
    return ListTile(
      leading: const Icon(Icons.translate),
      title: Text(tr('settings.language.title', 'Language')),
      subtitle: Text(
        current.aiCreated
            ? tr(
                'settings.language.aiSubtitle',
                '{name} — translated by AI and not yet checked by a person',
                {'name': current.name},
              )
            : current.name,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _choose(context),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final config = context.read<ConfigService>();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('settings.language.choose', 'Choose a language')),
        children: [
          for (final l in kLanguages)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(l.code),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: l.code == L10n.instance.code
                        ? const Icon(Icons.check, size: 24)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: const TextStyle(fontSize: 20)),
                        if (l.english != l.name)
                          Text(
                            l.english,
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(ctx).hintColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (l.aiCreated) _AiChip(),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null && chosen != L10n.instance.code) {
      await config.setLanguage(chosen);
    }
  }
}

class _AiChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colour = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tr('settings.language.aiCreated', 'AI-created'),
        style: TextStyle(
          color: colour,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
