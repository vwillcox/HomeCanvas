import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A parcel to send to the panel's Parcels tile: a tracking link or number,
/// and what it is.
///
/// A link shared from a carrier's email or app gets there without this —
/// the panel knows a tracking link when it sees one. This is for a number
/// copied out of an email, which on its own could be anything, and for
/// saying what is coming so the tile shows "Trainers" rather than "DPD
/// parcel".
class ParcelScreen extends StatefulWidget {
  const ParcelScreen({super.key});

  @override
  State<ParcelScreen> createState() => _ParcelScreenState();
}

/// What [ParcelScreen] hands back: the link or number, and its name.
typedef ParcelToSend = ({String content, String label});

class _ParcelScreenState extends State<ParcelScreen> {
  final _number = TextEditingController();
  final _label = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _canSend => _number.text.trim().isNotEmpty;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() => _number.text = text);
  }

  void _send() {
    Navigator.of(context).pop<ParcelToSend>((
      content: _number.text.trim(),
      label: _label.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track a parcel')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'It goes on the panel’s Parcels tile. Royal Mail, DPD, Evri, '
              'Yodel, DHL, UPS and the rest: a tracking link or the number '
              'from the email.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _number,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              // Typed, it is a number in capitals; pasted, a link as it is.
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Tracking link or number',
                hintText: 'QG123456789GB',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste',
                  onPressed: _paste,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What is it? (optional)',
                hintText: 'Trainers',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (_canSend) _send();
              },
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _canSend ? _send : null,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Send to the panel'),
            ),
          ],
        ),
      ),
    );
  }
}
