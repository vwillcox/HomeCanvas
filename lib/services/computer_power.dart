import 'link_outbox.dart';
import 'wake_on_lan.dart';

/// What became of [ComputerPower.setPower].
enum PcSwitch {
  /// Asked to switch off: it shows a notice it can be stopped from, then
  /// does. Or woken, and since heard from.
  done,

  /// It already was as asked: asking, so on — or not asking, so off.
  already,

  /// Sent the Wake-on-LAN packet, and not heard from in time after.
  notWoken,

  /// Off, and it has never said what it wakes on: its receiver predates
  /// that, or has only ever asked from outside the house.
  cannotWake,

  /// No computer collects links from the panel.
  none,
}

/// Switches a computer on and off from the panel — "turn the PC off".
///
/// The computer's own `homecanvas-links` receiver does the switching off:
/// it holds a request open on the panel's Share Inbox port all the time it
/// is on, so a command left in the outbox for it is collected at once,
/// sealed to its key like a link. It shows a notice with a way to stop it,
/// then shuts down. Switching on is Wake-on-LAN, to the hardware address
/// the receiver has told the panel, at the address it last asked from — see
/// [WakeOnLan] for how that crosses to another network.
///
/// Whether it is on is whether its receiver is asking: [LinkOutbox.isHere].
class ComputerPower {
  ComputerPower(
    this.outbox, {
    Future<bool> Function(String mac, String host)? wake,
    this.wakeWait = const Duration(minutes: 3),
  }) : _wake = wake ?? WakeOnLan.send;

  final LinkOutbox outbox;
  final Future<bool> Function(String mac, String host) _wake;

  /// How long a woken computer has to start and ask: a boot, a sign-in
  /// and the receiver starting with the session.
  final Duration wakeWait;

  /// The computers that collect links from the panel.
  List<OutboxDevice> get computers => [
    for (final d in outbox.devices)
      if (d.kind == 'computer') d,
  ];

  /// What they are called, for the voice to hear: "omarchy".
  List<String> get names => [for (final c in computers) c.name];

  bool get any => computers.isNotEmpty;

  /// The computer [named], or with no name the one most recently heard
  /// from — [LinkOutbox.devices] has them that way round.
  OutboxDevice? find([String? named]) {
    final all = computers;
    if (named == null) return all.firstOrNull;
    final want = named.toLowerCase();
    return all.where((c) => c.name.toLowerCase() == want).firstOrNull ??
        all.firstOrNull;
  }

  /// Switches [named] — or the computer, with one — on or off.
  ///
  /// Switching on waits, up to [wakeWait], to hear from it, and says
  /// [PcSwitch.notWoken] when it does not: the packet is sent across the
  /// router, which may not pass it on, and the only way to know is to see
  /// whether the computer comes.
  Future<PcSwitch> setPower(bool on, {String? named}) async {
    final pc = find(named);
    if (pc == null) return PcSwitch.none;
    final here = outbox.isHere(pc);
    if (here == on) return PcSwitch.already;
    if (!on) {
      await outbox.command(pc, {'do': 'power', 'state': 'off'});
      return PcSwitch.done;
    }
    final mac = pc.wakeMac, at = pc.address;
    if (mac == null || at == null) return PcSwitch.cannotWake;
    final since = outbox.now;
    await _wake(mac, at);
    final came = await outbox.heardFrom(pc, since: since, within: wakeWait);
    return came ? PcSwitch.done : PcSwitch.notWoken;
  }
}
