import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/link_outbox.dart';

/// "Send to…" for a link: it opens on a phone or computer instead, or as
/// well. Nothing at all where the panel has no outbox.
class SendToDeviceButton extends StatelessWidget {
  const SendToDeviceButton({
    super.key,
    required this.url,
    this.title,
    this.from,
    this.before,
    this.after,
  });

  final String url;
  final String? title;

  /// Where it was found — "Bluesky", a feed's name — for the notification.
  final String? from;

  /// Run before the picker opens, and once it has closed.
  final Future<void> Function()? before;
  final Future<void> Function()? after;

  @override
  Widget build(BuildContext context) {
    if (context.read<LinkOutbox?>() == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () async {
        await before?.call();
        if (!context.mounted) return;
        await showSendToDevice(context, url: url, title: title, from: from);
        await after?.call();
      },
      icon: const Icon(Icons.send_to_mobile_rounded, size: 26),
      label: Text(
        tr('sendTo.button', 'Send to…'),
        style: const TextStyle(fontSize: 20),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
      ),
    );
  }
}

/// Offers the phones and computers that collect links, and sends [url] to
/// each one touched. True if it went anywhere.
Future<bool> showSendToDevice(
  BuildContext context, {
  required String url,
  String? title,
  String? from,
}) async {
  final outbox = context.read<LinkOutbox?>();
  if (outbox == null) return false;
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: outbox,
      child: _SendDialog(url: url, title: title, from: from),
    ),
  );
  return sent ?? false;
}

class _SendDialog extends StatefulWidget {
  const _SendDialog({required this.url, this.title, this.from});

  final String url;
  final String? title;
  final String? from;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  final Set<String> _sending = {};
  final Set<String> _sent = {};
  final Set<String> _failed = {};

  Future<void> _send(LinkOutbox outbox, OutboxDevice d) async {
    setState(() {
      _sending.add(d.kid);
      _failed.remove(d.kid);
    });
    try {
      await outbox.send(
        d,
        url: widget.url,
        title: widget.title,
        from: widget.from,
      );
      _sent.add(d.kid);
    } catch (e) {
      debugPrint('Send to ${d.name}: $e');
      _failed.add(d.kid);
    }
    if (mounted) setState(() => _sending.remove(d.kid));
  }

  @override
  Widget build(BuildContext context) {
    final outbox = context.watch<LinkOutbox>();
    final devices = outbox.devices;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: Text(
        tr('sendTo.title', 'Send to…'),
        style: const TextStyle(fontSize: 24),
      ),
      content: SizedBox(
        width: 560,
        child: devices.isEmpty
            ? Text(
                tr(
                  'sendTo.noDevices',
                  'No phone or computer is collecting links yet. On a phone, '
                      'turn on “Receive links from the panel” in the '
                      'HomeCanvas Share app; on a computer, run the receiver '
                      'in companion_pc.',
                ),
                style: const TextStyle(fontSize: 18, height: 1.4),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in devices)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        leading: Icon(
                          d.kind == 'computer'
                              ? Icons.computer_rounded
                              : Icons.phone_android_rounded,
                          size: 34,
                        ),
                        title: Text(
                          d.name,
                          style: const TextStyle(fontSize: 22),
                        ),
                        subtitle: Text(
                          _failed.contains(d.kid)
                              ? tr('sendTo.failed', 'Could not send it')
                              : d.sender,
                          style: TextStyle(fontSize: 16, color: muted),
                        ),
                        trailing: _sending.contains(d.kid)
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : _sent.contains(d.kid)
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 30,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    tr('sendTo.sent', 'Sent'),
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ],
                              )
                            : const Icon(Icons.send_rounded, size: 30),
                        onTap: _sending.contains(d.kid) || _sent.contains(d.kid)
                            ? null
                            : () => _send(outbox, d),
                      ),
                  ],
                ),
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_sent.isNotEmpty),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          ),
          child: Text(
            tr('sendTo.done', 'Done'),
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ],
    );
  }
}
