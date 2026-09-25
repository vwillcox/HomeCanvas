import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widgets/tv_inputs_sheet.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/tv_service.dart';
import 'package:home_canvas/services/vidaa_client.dart';

/// A television that remembers what it was asked to switch to.
class FakeTv extends TvService {
  FakeTv() : super(ConfigService());
  final switched = <String>[];
  var asked = 0;
  @override
  void changeSource(String id) => switched.add(id);
  @override
  void refreshSources() => asked++;
}

TvSource src(String id, String name,
        {String device = '', bool signal = false, bool active = false}) =>
    TvSource(
      id: id,
      name: name,
      deviceName: device,
      hasSignal: signal,
      isActive: active,
    );

final inputs = [
  src('TV', 'TV'),
  src('HDMI1', 'HDMI1', device: 'Fire TV Stick', signal: true, active: true),
  src('HDMI2', 'HDMI2', device: 'PlayStation'),
  src('HDMI4', 'HDMI4', device: 'XBOX', signal: true),
  src('AV', 'AV'),
];

Future<FakeTv> pumpInputs(WidgetTester tester,
    {List<TvSource>? sources, bool connected = true}) async {
  tester.view.physicalSize = const Size(1920, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tv = FakeTv();
  tv.state.sources = sources ?? inputs;
  if (connected) tv.conn = ConnState.connected;
  await tester.pumpWidget(
    ChangeNotifierProvider<TvService>.value(
      value: tv,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showTvInputs(context, kBuiltInThemes.first),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return tv;
}

Future<void> finish(WidgetTester tester, FakeTv tv) async {
  await tester.pumpWidget(const SizedBox());
  tv.dispose();
}

void main() {
  group('what each input says about itself', () {
    test('something plugged in and on names the device', () {
      final s = src('HDMI1', 'HDMI1', device: 'Fire TV Stick', signal: true);
      expect(inputStatus(s), InputStatus.live);
      expect(inputSubtitle(s), 'Fire TV Stick');
    });

    test('a device the TV remembers but cannot see is asleep, not gone', () {
      final s = src('HDMI2', 'HDMI2', device: 'PlayStation');
      expect(inputStatus(s), InputStatus.asleep);
      expect(inputSubtitle(s), 'PlayStation · off');
    });

    test('an empty socket says so', () {
      final s = src('AV', 'AV');
      expect(inputStatus(s), InputStatus.empty);
      expect(inputSubtitle(s), 'Nothing connected');
    });

    test('a live input with no name still reads as live', () {
      expect(inputSubtitle(src('HDMI3', 'HDMI3', signal: true)), 'Signal');
    });

    test('icons follow the kind of input', () {
      expect(inputIcon(src('HDMI1', 'HDMI1')), Icons.settings_input_hdmi);
      expect(inputIcon(src('TV', 'TV')), Icons.live_tv);
      expect(inputIcon(src('AV', 'AV')), Icons.settings_input_composite);
      expect(inputIcon(src('284', 'VIDAA tv')), Icons.apps);
    });
  });

  group('the pop-up', () {
    testWidgets('lists every input, and marks the one showing',
        (tester) async {
      final tv = await pumpInputs(tester);
      for (final name in ['TV', 'HDMI1', 'HDMI2', 'HDMI4', 'AV']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Showing now'), findsOneWidget);
      expect(find.text('XBOX'), findsOneWidget);
      expect(find.text('PlayStation · off'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, tv);
    });

    testWidgets('tapping an input switches to it and closes', (tester) async {
      final tv = await pumpInputs(tester);
      await tester.tap(find.text('HDMI4'));
      await tester.pumpAndSettle();
      expect(tv.switched, ['HDMI4']);
      expect(find.text('Switch input'), findsNothing);
      await finish(tester, tv);
    });

    testWidgets('closing it switches nothing', (tester) async {
      final tv = await pumpInputs(tester);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(tv.switched, isEmpty);
      expect(find.text('Switch input'), findsNothing);
      await finish(tester, tv);
    });

    testWidgets('a tap outside closes it too', (tester) async {
      final tv = await pumpInputs(tester);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Switch input'), findsNothing);
      expect(tv.switched, isEmpty);
      await finish(tester, tv);
    });

    testWidgets('it closes itself if left open', (tester) async {
      final tv = await pumpInputs(tester);
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(find.text('Switch input'), findsNothing);
      await finish(tester, tv);
    });

    testWidgets('does not ask the TV for its inputs just by opening',
        (tester) async {
      // Asking makes the set run its pairing check, which flashes a code
      // over whatever is being watched.
      final tv = await pumpInputs(tester, sources: const []);
      expect(tv.asked, 0);
      await finish(tester, tv);
    });

    testWidgets('with no list yet, it offers to ask — once', (tester) async {
      final tv = await pumpInputs(tester, sources: const []);
      await tester.tap(find.text('Ask the television'));
      await tester.pumpAndSettle();
      expect(tv.asked, 1);
      expect(find.text('Ask the television'), findsNothing);
      expect(find.textContaining('as soon as the television answers'),
          findsOneWidget);
      await finish(tester, tv);
    });

    testWidgets('not connected, it says why rather than offering to ask',
        (tester) async {
      final tv =
          await pumpInputs(tester, sources: const [], connected: false);
      expect(find.textContaining('not connected'), findsOneWidget);
      expect(find.text('Ask the television'), findsNothing);
      await finish(tester, tv);
    });
  });
}
