import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../look.dart';

/// The panel's own on-screen keyboard, raised whenever a text field has focus.
///
/// The Pi does run squeekboard, but the kiosk window is fullscreen and labwc
/// draws a fullscreen window over the layer squeekboard lives on: asked, it
/// reports itself shown and nobody can see it. So the keyboard is drawn here,
/// over everything else in the app, for every field rather than field by
/// field — the TV's pairing code was the field that found this out, not the
/// only one that needed it.
///
/// It types through the focused field's own [EditableTextState], so a field's
/// formatters, length limit and onChanged all behave as they would for a real
/// keyboard. While up it is reported as a bottom inset, as a real one is, so
/// dialogs and scaffolds move clear of it.
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Off under `flutter test`, where fields are typed into directly and a
  /// keyboard appearing would move them.
  final bool enabled;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

enum _Layer { letters, symbols }

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  EditableTextState? _target;
  _Layer _layer = _Layer.letters;
  bool _shift = false;
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _repeat?.cancel();
    super.dispose();
  }

  void _focusChanged() {
    final focused = FocusManager.instance.primaryFocus?.context;
    var field = focused?.mounted == true
        ? focused!.findAncestorStateOfType<EditableTextState>()
        : null;
    if (field != null && field.widget.readOnly) field = null;
    if (identical(field, _target)) return;
    // Called during a build at times (autofocus), so the change waits for
    // the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _target = field;
        _layer = _Layer.letters;
        _shift = false;
      });
      if (field != null) {
        // Once the inset has moved things, put the field back in view.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (field!.mounted) {
            Scrollable.ensureVisible(
              field.context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 150),
            );
          }
        });
      }
    });
  }

  EditableTextState? get _live => (_target?.mounted ?? false) ? _target : null;

  void _type(String s) {
    final t = _live;
    if (t == null) return;
    final v = t.textEditingValue;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final typed = _shift ? s.toUpperCase() : s;
    t.userUpdateTextEditingValue(
      TextEditingValue(
        text: v.text.replaceRange(sel.start, sel.end, typed),
        selection: TextSelection.collapsed(offset: sel.start + typed.length),
      ),
      SelectionChangedCause.keyboard,
    );
    if (_shift) setState(() => _shift = false);
  }

  void _backspace() {
    final t = _live;
    if (t == null) return;
    final v = t.textEditingValue;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    String text;
    int at;
    if (!sel.isCollapsed) {
      text = v.text.replaceRange(sel.start, sel.end, '');
      at = sel.start;
    } else {
      if (sel.start == 0) return;
      // By character, not code unit, so an emoji goes in one press.
      final before = v.text.substring(0, sel.start).characters.skipLast(1);
      text = before.string + v.text.substring(sel.start);
      at = before.string.length;
    }
    t.userUpdateTextEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: at),
      ),
      SelectionChangedCause.keyboard,
    );
  }

  void _enter() {
    final t = _live;
    if (t == null) return;
    if (t.widget.maxLines != 1) {
      _type('\n');
    } else {
      t.performAction(t.widget.textInputAction ?? TextInputAction.done);
    }
  }

  /// Put away, by letting go of the field — so tapping it again brings the
  /// keyboard back.
  void _hide() => _live?.widget.focusNode.unfocus();

  bool _isNumber(TextInputType type) =>
      type.index == TextInputType.number.index ||
      type.index == TextInputType.phone.index;

  @override
  Widget build(BuildContext context) {
    final t = widget.enabled ? _live : null;
    final mq = MediaQuery.of(context);
    final type = t?.widget.keyboardType ?? TextInputType.text;
    final number = _isNumber(type);
    final height = t == null
        ? 0.0
        : number
        ? (mq.size.height * 0.36).clamp(240.0, 360.0)
        : (mq.size.height * 0.34).clamp(240.0, 400.0);

    // The same shape with the keyboard up or down: anything else would
    // rebuild the whole app beneath it each time it came and went.
    return Stack(
      children: [
        MediaQuery(
          data: height == 0
              ? mq
              : mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: height)),
          child: widget.child,
        ),
        if (t != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            // Counted as part of the field, so typing does not read as a tap
            // outside it and take the focus away.
            child: TextFieldTapRegion(
              child: _Board(
                number: number,
                decimal: number && (type.decimal ?? false),
                layer: _layer,
                shift: _shift,
                extra: type.index == TextInputType.emailAddress.index
                    ? '@'
                    : type.index == TextInputType.url.index
                    ? '/'
                    : ',',
                onType: _type,
                onBackspace: _backspace,
                onBackspaceHold: (down) {
                  _repeat?.cancel();
                  _repeat = down
                      ? Timer.periodic(
                          const Duration(milliseconds: 70),
                          (_) => _backspace(),
                        )
                      : null;
                },
                onEnter: _enter,
                onShift: () => setState(() => _shift = !_shift),
                onLayer: () => setState(() {
                  _layer = _layer == _Layer.letters
                      ? _Layer.symbols
                      : _Layer.letters;
                  _shift = false;
                }),
                onHide: _hide,
              ),
            ),
          ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.number,
    required this.decimal,
    required this.layer,
    required this.shift,
    required this.extra,
    required this.onType,
    required this.onBackspace,
    required this.onBackspaceHold,
    required this.onEnter,
    required this.onShift,
    required this.onLayer,
    required this.onHide,
  });

  final bool number;
  final bool decimal;
  final _Layer layer;
  final bool shift;

  /// The key beside the space bar: `@` for an email address, `/` for a web
  /// address, a comma otherwise.
  final String extra;

  final void Function(String) onType;
  final VoidCallback onBackspace;
  final void Function(bool down) onBackspaceHold;
  final VoidCallback onEnter;
  final VoidCallback onShift;
  final VoidCallback onLayer;
  final VoidCallback onHide;

  static const _letters = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  static const _symbols = ['1234567890', '@#£&_-()/', '.,?!\'":'];

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final bg = look.solidSurface;
    final fg = look.textPrimary;
    final accent = Theme.of(context).colorScheme.primary;

    Widget key(
      Widget label,
      VoidCallback onTap, {
      int flex = 10,
      Color? colour,
      void Function(bool down)? onHold,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: colour ?? bg,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onLongPressStart: onHold == null ? null : (_) => onHold(true),
              onLongPressEnd: onHold == null ? null : (_) => onHold(false),
              child: InkWell(
                canRequestFocus: false,
                onTap: onTap,
                child: Center(child: label),
              ),
            ),
          ),
        ),
      );
    }

    Widget char(String c, {int flex = 10}) => key(
      Text(
        shift ? c.toUpperCase() : c,
        style: TextStyle(fontSize: 28, color: fg),
      ),
      () => onType(c),
      flex: flex,
    );

    Widget icon(IconData i, {Color? colour}) =>
        Icon(i, size: 30, color: colour ?? fg);

    Widget backspace({int flex = 15}) => key(
      icon(Icons.backspace_outlined),
      onBackspace,
      flex: flex,
      onHold: onBackspaceHold,
    );

    Widget enter({int flex = 15}) => key(
      icon(number ? Icons.check : Icons.keyboard_return, colour: look.onAccent),
      onEnter,
      flex: flex,
      colour: accent,
    );

    Widget hide({int flex = 10}) =>
        key(icon(Icons.keyboard_hide_outlined), onHide, flex: flex);

    Widget row(List<Widget> keys) => Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: keys,
      ),
    );

    final List<Widget> rows;
    double maxWidth;
    if (number) {
      maxWidth = 560;
      rows = [
        row([char('1'), char('2'), char('3'), backspace(flex: 10)]),
        row([char('4'), char('5'), char('6'), enter(flex: 10)]),
        row([char('7'), char('8'), char('9'), hide()]),
        row([
          decimal ? char('.') : const Spacer(flex: 10),
          char('0'),
          const Spacer(flex: 20),
        ]),
      ];
    } else {
      maxWidth = 1400;
      final set = layer == _Layer.letters ? _letters : _symbols;
      rows = [
        row([for (final c in set[0].split('')) char(c)]),
        row([
          if (set[1].length < 10) Spacer(flex: (10 - set[1].length) * 5),
          for (final c in set[1].split('')) char(c),
          if (set[1].length < 10) Spacer(flex: (10 - set[1].length) * 5),
        ]),
        row([
          layer == _Layer.letters
              ? key(
                  icon(
                    shift ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                    colour: shift ? look.onAccent : fg,
                  ),
                  onShift,
                  flex: 15,
                  colour: shift ? accent : null,
                )
              : const Spacer(flex: 15),
          for (final c in set[2].split('')) char(c),
          backspace(),
        ]),
        row([
          key(
            Text(
              layer == _Layer.letters
                  ? tr('keyboard.symbols', '?123')
                  : tr('keyboard.letters', 'ABC'),
              style: TextStyle(fontSize: 22, color: fg),
            ),
            onLayer,
            flex: 15,
          ),
          char(extra),
          key(
            Text(
              tr('keyboard.space', 'space'),
              style: TextStyle(fontSize: 22, color: look.textSecondary),
            ),
            () => onType(' '),
            flex: 50,
          ),
          char('.'),
          enter(),
          hide(),
        ]),
      ];
    }

    return Material(
      color: look.background.first,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: rows),
            ),
          ),
        ),
      ),
    );
  }
}
