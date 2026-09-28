import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../look.dart';
import 'package:provider/provider.dart';

import 'dart:math';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../config/app_config.dart';
import '../services/brightness_service.dart';
import '../services/camera_service.dart';
import '../services/config_service.dart';
import '../services/dashboard_service.dart';
import '../services/indoor_sensor_service.dart';
import '../services/locked_folder_service.dart';
import '../services/media_cache.dart';
import '../services/now_playing_service.dart';
import '../services/screen_idle_service.dart';
import '../services/share_inbox_service.dart';
import '../services/spotify_service.dart';
import '../services/floatplane_site.dart';
import '../services/nebula_site.dart';
import '../services/video_player_service.dart';
import '../services/video_site.dart';
import '../services/youtube_site.dart';
import '../services/yt_dlp.dart';
import 'video_sign_in.dart';
import '../services/tv_service.dart';
import '../services/weather_service.dart';
import '../widgets/weather_overlay.dart';
import '../widgets/glass.dart';
import '../widgets/language_tile.dart';
import '../l10n/l10n.dart';
import 'about_screen.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The tabs, in order: what each is called, its icon, and what is in it.
  ///
  /// Grouped by what a person comes to change rather than by which part of
  /// the code owns it — fifteen sections in one scroll meant hunting for the
  /// one you wanted every time.
  // A getter, not a constant, so the names follow a change of language.
  static List<(String, IconData)> get tabs => [
    (tr('settings.photos', 'Photos'), Icons.photo_library_outlined),
    (tr('settings.music', 'Music'), Icons.music_note_outlined),
    (tr('settings.home', 'Home'), Icons.home_outlined),
    (tr('settings.display', 'Display'), Icons.tv_outlined),
    (tr('settings.volumes', 'Volumes'), Icons.volume_up_outlined),
    (tr('settings.sharing', 'Sharing'), Icons.ios_share),
    (tr('settings.system', 'System'), Icons.settings_suggest_outlined),
  ];

  /// Remembered while the kiosk runs, so Settings opens where it was left.
  static int _lastTab = 0;

  /// How much larger than elsewhere Settings' text is drawn.
  static const double textScale = 1.3;
  int _tab = _lastTab;

  List<Widget> _sectionsFor(
    int tab,
    ConfigService config,
    LockedFolderService locked,
    String maskedKey,
  ) {
    switch (tab) {
      case 0: // Photos
        return [
          GlassSection(
            title: tr('settings.connection', 'Connection'),
            children: [
              ListTile(
                leading: const Icon(Icons.dns),
                title: Text(tr('settings.immichServer', 'Immich server')),
                subtitle: Text(
                  config.immichUrl.isEmpty ? tr('settings.notSet', 'Not set') : config.immichUrl,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editConnection,
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: Text(tr('settings.apiKey', 'API key')),
                subtitle: Text(maskedKey),
                onTap: _editConnection,
              ),
            ],
          ),
          GlassSection(
            title: tr('settings.lockedFolder', 'Locked Folder'),
            children: [
              ListTile(
                leading: Icon(
                  locked.canUse ? Icons.lock : Icons.lock_open,
                  color: locked.canUse ? null : const Color(0xFFFFC46B),
                ),
                title: Text(tr('settings.immichAccountLogin', 'Immich account login')),
                subtitle: Text(
                  locked.canUse
                      ? tr('settings.signedInAsOpenThe', 'Signed in as {immichEmail} — open the Locked Folder tile on the home screen and enter your PIN.', {'immichEmail': config.immichEmail})
                      : tr('settings.notConfiguredRunSetImmich', 'Not configured. Run set-immich-login.sh on the Pi to store your Immich email + password (required to open the server-side Locked Folder).'),
                ),
                isThreeLine: true,
              ),
            ],
          ),
          GlassSection(
            title: tr('settings.slideshow', 'Slideshow'),
            children: [const _SlideshowSettingsTile()],
          ),
          GlassSection(title: tr('settings.storage', 'Storage'), children: [const _CacheTile()]),
        ];
      case 1: // Music
        return [
          GlassSection(
            title: tr('settings.nowPlaying', 'Now playing'),
            children: [const _NowPlayingSettingsTile()],
          ),
          GlassSection(
            title: tr('settings.spotify', 'Spotify'),
            children: [const _SpotifySettingsTile()],
          ),
          GlassSection(
            title: tr('settings.videos', 'Videos'),
            children: [
              const _VideoPlayerTile(),
              _SiteSignInTile<YouTubeSite>(
                icon: Icons.smart_display,
                colour: const Color(0xFFFF0033),
                signedInText: tr('settings.signedInPremiumYourSubscriptions', 'Signed in — Premium, your subscriptions and members-only videos'),
              ),
              _SiteSignInTile<FloatplaneSite>(
                icon: Icons.live_tv,
                colour: const Color(0xFF00AFEC),
                signedInText:
                    tr(
                      'settings.signedInYourCreatorsLatest',
                      'Signed in — your creators’ latest videos on the dashboard',
                    ),
              ),
              _SiteSignInTile<NebulaSite>(
                icon: Icons.auto_awesome,
                colour: const Color(0xFF6C7CFF),
                signedInText: tr('settings.signedInTheCreatorsYou', 'Signed in — the creators you follow on the dashboard'),
              ),
            ],
          ),
        ];
      case 2: // Home
        return [
          GlassSection(
            title: tr('settings.weather', 'Weather'),
            children: [const _WeatherSettingsTile()],
          ),
          GlassSection(
            title: tr('settings.homeAssistant', 'Home Assistant'),
            children: [const _HomeAssistantSettingsTile()],
          ),
          GlassSection(
            title: tr('settings.television', 'Television'),
            children: [const _TvSettingsTile()],
          ),
          GlassSection(
            title: tr('settings.camera', 'Camera'),
            children: [const _CameraSettingsTile()],
          ),
        ];
      case 3: // Display
        return [
          GlassSection(
            title: tr('settings.screen', 'Screen'),
            children: [const _ScreenSettingsTile()],
          ),
          GlassSection(
            title: tr('settings.dashboard', 'Dashboard'),
            children: [const _DashboardSettingsTile()],
          ),
        ];
      case 4: // Volumes
        return [
          GlassSection(
            title: tr('settings.volumes', 'Volumes'),
            children: [const _SoundSettingsTile()],
          ),
        ];
      case 5: // Sharing
        return [
          GlassSection(
            title: tr('settings.shareInbox', 'Share Inbox'),
            children: [const _ShareInboxSettingsTile()],
          ),
        ];
      case 6: // System
        return [
          GlassSection(
            title: tr('settings.language.section', 'Language'),
            children: const [LanguageTile()],
          ),
          GlassSection(
            title: tr('settings.device', 'Device'),
            children: [
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: Text(tr('settings.restart', 'Restart')),
                onTap: () => _confirmPower(
                  title: tr('settings.restart', 'Restart'),
                  action: 'reboot',
                  verb: tr('settings.restart', 'Restart'),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.power_settings_new,
                  color: Color(0xFFFF6B6B),
                ),
                title: Text(
                  tr('settings.powerOff', 'Power off'),
                  style: TextStyle(color: Color(0xFFFF8A8A)),
                ),
                onTap: () => _confirmPower(
                  title: tr('settings.powerOff', 'Power off'),
                  action: 'poweroff',
                  verb: tr('settings.powerOff', 'Power off'),
                ),
              ),
            ],
          ),
          GlassSection(
            title: tr('settings.about', 'About'),
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(tr('settings.aboutHomecanvas', 'About HomeCanvas')),
                subtitle: Text(
                  tr(
                    'settings.versionOpenSourceLibrariesLicences',
                    'Version, open-source libraries, licences and credits',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
            ],
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _tabBar() {
    return Glass(
      padding: const EdgeInsets.all(5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _TabButton(
                label: tabs[i].$1,
                icon: tabs[i].$2,
                selected: i == _tab,
                onTap: () => setState(() => _tab = _lastTab = i),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editConnection() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SetupScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _confirmPower({
    required String title,
    required String action, // 'poweroff' | 'reboot'
    required String verb,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(tr('settings.theDeviceNow', '{verb} the device now?', {'verb': verb})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await Process.run('systemctl', [action]);
      if (r.exitCode != 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'settings.couldNotRunDeployEnable',
                'Could not {verb} ({trim}). Run deploy/enable-poweroff.sh on the Pi.',
                {'trim': r.stderr.toString().trim(), 'verb': verb},
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('settings.couldNot', 'Could not {verb}: {e}', {'verb': verb, 'e': e}))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final locked = context.watch<LockedFolderService>();
    final maskedKey = config.apiKey.isEmpty
        ? '—'
        : '${config.apiKey.substring(0, config.apiKey.length.clamp(0, 4))}••••••••';

    return ModernScaffold(
      header: ScreenHeader(
        onBack: () => Navigator.of(context).maybePop(),
        trailing: _tabBar(),
        title: tr('settings.title', 'Settings'),
        subtitle: config.immichUrl.isEmpty
            ? tr('settings.notConnectedToImmichYet', 'Not connected to Immich yet')
            : tr('settings.connectedTo3', 'Connected to {immichUrl}', {'immichUrl': Uri.tryParse(config.immichUrl)?.host ?? config.immichUrl}),
      ),
      // A readable column rather than rows stretched across 1,920 pixels, and
      // larger type throughout — every piece of it, section headings and help
      // text included: this is read standing, often from across the room.
      // The tabs above keep their size so all of them still fit.
      body: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(textScale)),
        child: IconTheme.merge(
          data: const IconThemeData(size: 30),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: ListTileTheme(
                data: ListTileThemeData(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  minVerticalPadding: 12,
                  iconColor: context.look.textSecondary,
                  titleTextStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: context.look.textPrimary,
                  ),
                  subtitleTextStyle: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    color: context.look.textSecondary,
                  ),
                ),
                child: ListView(
                  // A new list per tab, so each opens at the top rather than
                  // wherever the last one was scrolled to.
                  key: ValueKey(_tab),
                  padding: const EdgeInsets.fromLTRB(32, 12, 32, 48),
                  children: [
                    ..._sectionsFor(_tab, config, locked, maskedKey),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'HomeCanvas',
                        style: TextStyle(color: context.look.wash(0.3)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherSettingsTile extends StatelessWidget {
  const _WeatherSettingsTile();

  Future<void> _editLocation(BuildContext context) async {
    final service = context.read<WeatherService>();
    final s = context.read<ConfigService>().config.weather;
    final controller = TextEditingController(text: s.location);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.weatherLocation', 'Weather location')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'settings.ukPostcodeEGCo1',
                'UK postcode (e.g. CO1 1ZY) or a place name (e.g. Colchester).',
              ),
              style: TextStyle(color: context.look.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(tr('settings.save', 'Save')),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      s.location = result.trim();
      await service.updateSettings(s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final service = context.watch<WeatherService>();
    final s = config.config.weather;
    final w = service.weather;

    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(
            w != null ? weatherIcon(w.weatherCode, w.isDay) : Icons.cloud,
          ),
          title: Text(tr('settings.showWeatherInSlideshow', 'Show weather in slideshow')),
          subtitle: Text(
            service.error ??
                (w != null
                    ? '${w.temperature.round()}${w.unit} · ${w.description} · ${w.label}'
                    : tr('settings.loading', 'Loading…')),
          ),
          value: s.enabled,
          onChanged: (v) {
            s.enabled = v;
            service.updateSettings(s);
          },
        ),
        ListTile(
          enabled: s.enabled,
          leading: const Icon(Icons.place_outlined),
          title: Text(tr('settings.location', 'Location')),
          subtitle: Text(s.location),
          trailing: const Icon(Icons.edit),
          onTap: s.enabled ? () => _editLocation(context) : null,
        ),
        ListTile(
          enabled: s.enabled,
          leading: const Icon(Icons.picture_in_picture_alt_outlined),
          title: Text(tr('settings.position', 'Position')),
          subtitle: Text(cornerLabel(s.corner)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _CornerPicker(
            value: s.corner,
            enabled: s.enabled,
            onChanged: (c) {
              final config = context.read<ConfigService>();
              config.config.assignCorner(OverlaySlot.weather, c);
              config.save();
              service.updateSettings(s);
            },
          ),
        ),
        Builder(
          builder: (context) {
            final sensor = context.watch<IndoorSensorService>();
            return SwitchListTile(
              secondary: Icon(
                Icons.home_outlined,
                color: sensor.available ? const Color(0xFFFF8A65) : null,
              ),
              title: Text(tr('settings.showIndoorTemperature', 'Show indoor temperature')),
              subtitle: Text(
                sensor.available
                    ? '${sensor.temperatureC!.toStringAsFixed(1)}°C · '
                          '${sensor.humidity?.round() ?? '—'}% · '
                          'battery ${sensor.battery ?? '—'}%'
                    : tr('settings.notReadingCheckTheHome', 'Not reading — check the Home Assistant section below'),
              ),
              value: s.showIndoor,
              onChanged: (v) {
                s.showIndoor = v;
                service.updateSettings(s);
              },
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.thermostat),
          title: Text(tr('settings.useCelsius', 'Use Celsius')),
          subtitle: Text(s.metric ? '°C' : '°F'),
          value: s.metric,
          onChanged: s.enabled
              ? (v) {
                  s.metric = v;
                  service.updateSettings(s);
                }
              : null,
        ),
        ListTile(
          enabled: s.enabled,
          leading: const Icon(Icons.refresh),
          title: Text(tr('settings.refreshNow', 'Refresh now')),
          onTap: s.enabled ? () => service.refresh(force: true) : null,
        ),
      ],
    );
  }
}

/// 2x2 grid of corner buttons mirroring the screen layout.
class _CornerPicker extends StatelessWidget {
  final OverlayCorner value;
  final bool enabled;
  final ValueChanged<OverlayCorner> onChanged;
  const _CornerPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(OverlayCorner c, Alignment align) {
      final selected = value == c;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.30)
                : context.look.wash(0.08),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: enabled ? () => onChanged(c) : null,
              child: Container(
                height: 54,
                alignment: align,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : context.look.wash(0.12),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Container(
                  width: 34,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : context.look.wash(0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        children: [
          Row(
            children: [
              cell(OverlayCorner.topLeft, Alignment.topLeft),
              cell(OverlayCorner.topRight, Alignment.topRight),
            ],
          ),
          Row(
            children: [
              cell(OverlayCorner.bottomLeft, Alignment.bottomLeft),
              cell(OverlayCorner.bottomRight, Alignment.bottomRight),
            ],
          ),
        ],
      ),
    );
  }
}

class _SlideshowSettingsTile extends StatelessWidget {
  const _SlideshowSettingsTile();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final s = config.slideshow;

    void save() => config.updateSlideshow(s);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(tr('settings.timePerPhoto', 'Time per photo')),
          trailing: Text(
            '${s.intervalSeconds}s',
            style: const TextStyle(fontSize: 18),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            min: 3,
            max: 30,
            divisions: 27,
            label: '${s.intervalSeconds}s',
            value: s.intervalSeconds.toDouble(),
            onChanged: (v) {
              s.intervalSeconds = v.round();
              save();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.animation),
          title: Text(tr('settings.transition', 'Transition')),
          trailing: DropdownButton<SlideshowTransition>(
            value: s.transition,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: SlideshowTransition.fade,
                child: Text(tr('settings.fade', 'Fade')),
              ),
              DropdownMenuItem(
                value: SlideshowTransition.slide,
                child: Text(tr('settings.slide', 'Slide')),
              ),
              DropdownMenuItem(
                value: SlideshowTransition.kenBurns,
                child: Text(tr('settings.kenBurns', 'Ken Burns')),
              ),
              DropdownMenuItem(
                value: SlideshowTransition.pageTurn,
                child: Text(tr('settings.pageTurn', 'Page turn')),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                s.transition = v;
                save();
              }
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.shuffle),
          title: Text(tr('settings.shuffle', 'Shuffle')),
          value: s.shuffle,
          onChanged: (v) {
            s.shuffle = v;
            save();
          },
        ),
      ],
    );
  }
}

/// Shows how much the on-disk media cache is using, with a way to clear it.
class _CacheTile extends StatefulWidget {
  const _CacheTile();

  @override
  State<_CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<_CacheTile> {
  int? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final b = await HomeCanvasCache.diskUsageBytes();
    if (mounted) setState(() => _bytes = b);
  }

  String _human(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    await HomeCanvasCache.clear();
    await _measure();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('settings.cacheCleared', 'Cache cleared'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.sd_storage_outlined),
      title: Text(tr('settings.photoCache', 'Photo cache')),
      subtitle: Text(
        _bytes == null
            ? tr('settings.measuring', 'Measuring…')
            : tr('settings.onDiskCacheHomecanvas', '{_bytes} on disk  •  ~/.cache/homecanvas', {'_bytes': _human(_bytes!)}),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : TextButton(onPressed: _clear, child: Text(tr('settings.clear', 'Clear'))),
    );
  }
}

/// Toggle the now-playing overlay and choose which corner it sits in.
class _NowPlayingSettingsTile extends StatelessWidget {
  const _NowPlayingSettingsTile();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final service = context.watch<NowPlayingService>();
    final s = config.config.nowPlaying;
    final n = service.now;

    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(
            s.enabled ? Icons.music_note : Icons.music_off,
            color: s.enabled ? null : context.look.wash(0.38),
          ),
          title: Text(tr('settings.showWhatMyPhoneIs', 'Show what my phone is playing')),
          subtitle: Text(
            service.available
                ? (n.hasTrack
                      ? tr('settings.connectedTo2', 'Connected to {deviceName} — {title}', {'deviceName': n.deviceName.isEmpty ? "phone" : n.deviceName, 'title': n.title})
                      : tr('settings.connectedToNothingPlaying', 'Connected to {deviceName} — nothing playing', {'deviceName': n.deviceName.isEmpty ? "phone" : n.deviceName}))
                : tr('settings.noPhoneConnectedPairOne', 'No phone connected. Pair one over Bluetooth and play something with media audio routed to this device.'),
          ),
          isThreeLine: !service.available,
          value: s.enabled,
          onChanged: (v) {
            s.enabled = v;
            config.save();
          },
        ),
        if (s.enabled)
          SwitchListTile(
            secondary: Icon(
              s.playAudioHere ? Icons.speaker : Icons.headphones,
              color: s.playAudioHere ? null : const Color(0xFF7FE3A1),
            ),
            title: Text(tr('settings.playTheAudioOnThis', 'Play the audio on this device')),
            subtitle: Text(
              s.playAudioHere
                  ? tr('settings.musicPlaysThroughThePi', 'Music plays through the Pi\'s speaker.')
                  : tr('settings.musicStaysOnThePhone', 'Music stays on the phone (e.g. your headphones) and this screen is just a remote control.'),
            ),
            isThreeLine: !s.playAudioHere,
            value: s.playAudioHere,
            onChanged: (v) {
              s.playAudioHere = v;
              config.save();
              service.preferAudioRouted = v;
            },
          ),
        if (s.enabled)
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: Text(tr('settings.visualiser', 'Visualiser')),
            subtitle: Text(
              s.playAudioHere
                  ? tr('settings.drawnInTheFullScreen', 'Drawn in the full-screen player, between the scrubber and the transport controls.')
                  : tr('settings.needsTheAudioPlayingOn', 'Needs the audio playing on this device — with it staying on the phone there is no sound here to draw.'),
            ),
            isThreeLine: !s.playAudioHere,
            trailing: DropdownButton<VisualiserStyle>(
              value: s.visualiser,
              underline: const SizedBox.shrink(),
              items: VisualiserStyle.values
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(visualiserLabel(v)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  s.visualiser = v;
                  config.save();
                }
              },
            ),
          ),
        if (s.enabled)
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt),
            title: Text(tr('settings.position', 'Position')),
            subtitle: Text(tr('settings.whichCornerThePlayerSits', 'Which corner the player sits in')),
            trailing: DropdownButton<OverlayCorner>(
              value: s.corner,
              underline: const SizedBox.shrink(),
              items: OverlayCorner.values
                  .map(
                    (c) =>
                        DropdownMenuItem(value: c, child: Text(cornerLabel(c))),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  config.config.assignCorner(OverlaySlot.nowPlaying, v);
                  config.save();
                }
              },
            ),
          ),
      ],
    );
  }
}

/// Home Assistant connection, used for the indoor temperature reading.
class _HomeAssistantSettingsTile extends StatelessWidget {
  const _HomeAssistantSettingsTile();

  Future<void> _edit(BuildContext context) async {
    final service = context.read<ConfigService>();
    final sensor = context.read<IndoorSensorService>();
    final s = service.config.homeAssistant;
    final url = TextEditingController(text: s.baseUrl);
    final token = TextEditingController(text: s.token);
    final temp = TextEditingController(text: s.temperatureEntity);
    final hum = TextEditingController(text: s.humidityEntity);
    final batt = TextEditingController(text: s.batteryEntity);
    var enabled = s.enabled;

    Widget field(String label, TextEditingController c, {String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            style: const TextStyle(fontSize: 18),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.homeAssistant', 'Home Assistant')),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'settings.theIndoorReadingComesFrom',
                    'The indoor reading comes from Home Assistant. Create a token under your Home Assistant profile → Security → Long-lived access tokens.',
                  ),
                  style: TextStyle(color: context.look.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 14),
                // A switch rather than clearing the fields: turning the
                // reading off should not cost you a long-lived token you then
                // have to re-issue in Home Assistant.
                StatefulBuilder(
                  builder: (context, setLocal) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      tr(
                        'settings.readTheIndoorSensor',
                        'Read the indoor sensor',
                      ),
                      style: TextStyle(fontSize: 18),
                    ),
                    subtitle: Text(
                      tr(
                        'settings.offStopsPollingHomeAssistant',
                        'Off stops polling Home Assistant and hides the indoor reading, keeping these settings for later.',
                      ),
                      style: TextStyle(color: context.look.textSecondary, fontSize: 13),
                    ),
                    value: enabled,
                    onChanged: (v) => setLocal(() => enabled = v),
                  ),
                ),
                const SizedBox(height: 6),
                field(tr('settings.server', 'Server'), url, hint: 'http://localhost:8123'),
                field(tr('settings.longLivedAccessToken', 'Long-lived access token'), token),
                field(
                  tr('settings.temperatureEntity', 'Temperature entity'),
                  temp,
                  hint: 'sensor.h5104_145e_temperature',
                ),
                field(tr('settings.humidityEntity', 'Humidity entity'), hum),
                field(tr('settings.batteryEntity', 'Battery entity'), batt),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('settings.save', 'Save')),
          ),
        ],
      ),
    );

    if (saved != true) return;
    s.enabled = enabled;
    s.baseUrl = url.text.trim().replaceAll(RegExp(r'/+$'), '');
    s.token = token.text.trim();
    s.temperatureEntity = temp.text.trim();
    s.humidityEntity = hum.text.trim();
    s.batteryEntity = batt.text.trim();
    await service.save();
    // Apply straight away rather than waiting for a restart.
    sensor.updateSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ConfigService>().config.homeAssistant;
    final sensor = context.watch<IndoorSensorService>();
    return ListTile(
      leading: Icon(
        Icons.home_outlined,
        color: sensor.available ? const Color(0xFFFF8A65) : null,
      ),
      title: Text(tr('settings.homeAssistant', 'Home Assistant')),
      subtitle: Text(
        !s.isConfigured
            ? tr('settings.notConfiguredNoIndoorTemperature', 'Not configured — no indoor temperature')
            : sensor.available
            ? tr('settings.readingC', '{baseUrl} — reading {temperatureC}°C', {'baseUrl': s.baseUrl, 'temperatureC': sensor.temperatureC!.toStringAsFixed(1)})
            : tr('settings.configuredButNoReadingYet', '{baseUrl} — configured, but no reading yet', {'baseUrl': s.baseUrl}),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context),
      isThreeLine: false,
    );
  }
}

/// What every video site needs: yt-dlp, which finds the stream, and how
/// sharp a picture to ask for. See [VideoPlayerService].
class _VideoPlayerTile extends StatelessWidget {
  const _VideoPlayerTile();

  @override
  Widget build(BuildContext context) {
    final ytDlp = context.watch<YtDlp>();
    return ListTile(
      leading: const Icon(Icons.play_circle_outline),
      title: Text(tr('settings.videoPlayer', 'Video player')),
      subtitle: Text(ytDlp.installing
          ? ytDlp.status ?? tr('settings.installing', 'Installing…')
          : ytDlp.status ??
              (ytDlp.ready
                  ? tr('settings.ytDlpUpdatedDailyYoutube', 'yt-dlp {version}, updated daily — YouTube, Floatplane and Nebula play here', {'version': ytDlp.version})
                  : tr('settings.notSetUpNeedsYt', 'Not set up — needs yt-dlp to play videos here'))),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _VideoPlayerDialog(),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatelessWidget {
  const _VideoPlayerDialog();

  @override
  Widget build(BuildContext context) {
    final ytDlp = context.watch<YtDlp>();
    final player = context.watch<VideoPlayerService>();
    return AlertDialog(
      title: Text(tr('settings.videoPlayer', 'Video player')),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  'settings.videosSharedFromThePhone',
                  'Videos shared from the phone app, opened from the news, or put on the dashboard play here, full screen or as a picture-in-picture window you can drag, pinch and resize.',
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download),
                title: const Text('yt-dlp'),
                subtitle: Text(ytDlp.installing
                    ? ytDlp.status ?? tr('settings.installing', 'Installing…')
                    : ytDlp.status ??
                        (ytDlp.ready
                            ? tr('settings.versionUpdatedDaily', 'Version {version} — updated daily', {'version': ytDlp.version})
                            : tr('settings.notInstalledItFetchesThe', 'Not installed. It fetches the video from the site; kept up to date automatically once installed.'))),
                trailing: ytDlp.installing
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3))
                    : FilledButton.tonal(
                        onPressed: ytDlp.install,
                        child: Text(ytDlp.ready ? tr('settings.reinstall', 'Reinstall') : tr('settings.install', 'Install')),
                      ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(tr('settings.pictureQuality', 'Picture quality')),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 720, label: Text('720p')),
                  ButtonSegment(value: 1080, label: Text('1080p')),
                ],
                selected: {player.settings.maxHeight <= 720 ? 720 : 1080},
                onSelectionChanged: (v) => player.setMaxHeight(v.first),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'settings.1080pIsSharperAndWorks',
                  '1080p is sharper and works the Pi harder. Dashboard tiles use 720p either way.',
                ),
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('settings.done', 'Done')),
        ),
      ],
    );
  }
}

/// Signing in to one video site — YouTube, Floatplane, Nebula — whose
/// dashboard tile shows its latest videos. [T] is the site.
class _SiteSignInTile<T extends VideoSite> extends StatelessWidget {
  const _SiteSignInTile({
    required this.icon,
    required this.colour,
    required this.signedInText,
  });

  final IconData icon;
  final Color colour;
  final String signedInText;

  @override
  Widget build(BuildContext context) {
    final site = context.watch<T>();
    final address = context.read<DashboardService>().editorAddress;
    return ListTile(
      leading: Icon(icon, color: site.signedIn ? colour : null),
      title: Text(site.name),
      subtitle: Text(site.signedIn
          ? signedInText
          : !site.ready
              ? tr('settings.needsYtDlpInstallIt', 'Needs yt-dlp — install it under Video player, above')
              : tr('settings.notSignedInSignIn', 'Not signed in. Sign in here, or — rather than typing a password on the panel — on a computer at {address}/{id}', {'id': site.id, 'address': address})),
      isThreeLine: !site.signedIn,
      trailing: site.signedIn
          ? OutlinedButton(
              onPressed: site.signOut,
              child: Text(tr('settings.signOut', 'Sign out')),
            )
          : FilledButton(
              onPressed:
                  site.ready ? () => signInOnPanel(context, site) : null,
              child: Text(tr('settings.signIn', 'Sign in')),
            ),
    );
  }
}

/// Full Spotify playback control via the Web API, shown in preference to the
/// AVRCP phone source whenever it has something active. Authenticated with
/// OAuth Authorization Code + PKCE, so only a Client ID is needed — see
/// [SpotifyService] for the flow itself.
class _SpotifySettingsTile extends StatelessWidget {
  const _SpotifySettingsTile();

  Future<void> _edit(BuildContext context) async {
    final config = context.read<ConfigService>();
    final spotify = context.read<SpotifyService>();
    await showDialog<void>(
      context: context,
      builder: (_) => _SpotifyDialog(config: config, spotify: spotify),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ConfigService>().config.spotify;
    final spotify = context.watch<SpotifyService>();
    return ListTile(
      leading: Icon(
        Icons.podcasts,
        color: spotify.available ? const Color(0xFF1ED760) : null,
      ),
      title: Text(tr('settings.spotify', 'Spotify')),
      subtitle: Text(
        !s.isConfigured
            ? tr('settings.notConnectedFullPlaybackControl', 'Not connected — full playback control alongside the phone')
            : spotify.available
            ? tr('settings.connectedPlaying', 'Connected — playing "{title}"', {'title': spotify.now.title})
            : tr('settings.connectedButNothingPlayingRight', 'Connected, but nothing playing right now'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context),
    );
  }
}

class _SpotifyDialog extends StatefulWidget {
  final ConfigService config;
  final SpotifyService spotify;
  const _SpotifyDialog({required this.config, required this.spotify});

  @override
  State<_SpotifyDialog> createState() => _SpotifyDialogState();
}

class _SpotifyDialogState extends State<_SpotifyDialog> {
  late final TextEditingController _clientId = TextEditingController(
    text: widget.config.config.spotify.clientId,
  );
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final id = _clientId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = tr('settings.enterTheClientIdFirst', 'Enter the Client ID first.'));
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final err = await widget.spotify.connect(id);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _connecting = false;
      _error = err;
    });
  }

  Future<void> _disconnect() async {
    await widget.spotify.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isConfigured = widget.config.config.spotify.isConfigured;
    return AlertDialog(
      title: Text(tr('settings.spotify', 'Spotify')),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'settings.createAFreeAppAt',
                  'Create a free app at developer.spotify.com/dashboard, then paste its Client ID below. Register this exact Redirect URI on that app:',
                ),
                style: TextStyle(color: context.look.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SelectableText(
                SpotifyService.redirectUri,
                style: TextStyle(
                  color: context.look.textPrimary,
                  fontSize: 15,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _clientId,
                enabled: !_connecting,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: tr('settings.clientId', 'Client ID'),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A))),
              ],
              if (_connecting) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          'settings.aBrowserWindowOpenedFor',
                          'A browser window opened for you to log into Spotify. Come back here once you have approved access.',
                        ),
                        style: TextStyle(color: context.look.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (isConfigured)
          TextButton(
            onPressed: _connecting ? null : _disconnect,
            child: Text(
              tr('settings.disconnect', 'Disconnect'),
              style: TextStyle(color: Color(0xFFFF8A8A)),
            ),
          ),
        TextButton(
          onPressed: _connecting ? null : () => Navigator.of(context).pop(),
          child: Text(tr('settings.cancel', 'Cancel')),
        ),
        FilledButton(
          onPressed: _connecting ? null : _connect,
          child: Text(isConfigured ? tr('settings.reconnect', 'Reconnect') : tr('settings.connect', 'Connect')),
        ),
      ],
    );
  }
}

/// Lets people with the companion app share a photo/GIF/video/link/note to
/// the kiosk. See [ShareInboxService] for how it's actually received —
/// there's no relay, the kiosk listens for these itself.
class _ShareInboxSettingsTile extends StatelessWidget {
  const _ShareInboxSettingsTile();

  Future<void> _edit(BuildContext context) async {
    final config = context.read<ConfigService>();
    final shareInbox = context.read<ShareInboxService>();
    await showDialog<void>(
      context: context,
      builder: (_) => _ShareInboxDialog(config: config, shareInbox: shareInbox),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ConfigService>().config.shareInbox;
    return ListTile(
      leading: const Icon(Icons.ios_share),
      title: Text(tr('settings.shareInbox', 'Share Inbox')),
      subtitle: Text(
        s.senderTokens.isEmpty
            ? tr('settings.listeningOnNoSendersAdded', 'Listening on :{listenPort} — no senders added yet', {'listenPort': s.listenPort})
            : 'Listening on :${s.listenPort} — ${s.senderTokens.length} '
                  '${s.senderTokens.length == 1 ? 'sender' : 'senders'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context),
    );
  }
}

class _ShareInboxDialog extends StatefulWidget {
  final ConfigService config;
  final ShareInboxService shareInbox;
  const _ShareInboxDialog({required this.config, required this.shareInbox});

  @override
  State<_ShareInboxDialog> createState() => _ShareInboxDialogState();
}

class _ShareInboxDialogState extends State<_ShareInboxDialog> {
  late final TextEditingController _port;
  late List<SenderToken> _tokens;
  late bool _speak;
  late bool _speakSender;
  final _newName = TextEditingController();

  static final _rand = Random.secure();
  static String _randomToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(32, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    final s = widget.config.config.shareInbox;
    _port = TextEditingController(text: s.listenPort.toString());
    _speak = s.speakNotes;
    _speakSender = s.speakSender;
    _tokens = s.senderTokens
        .map((t) => SenderToken(name: t.name, token: t.token))
        .toList();
  }

  @override
  void dispose() {
    _port.dispose();
    _newName.dispose();
    super.dispose();
  }

  void _addSender() {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _tokens.add(SenderToken(name: name, token: _randomToken()));
      _newName.clear();
    });
  }

  void _copy(String token) {
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('settings.tokenCopied', 'Token copied'))));
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('settings.enterAPortBetween1', 'Enter a port between 1 and 65535'))),
      );
      return;
    }
    final s = widget.config.config.shareInbox;
    s.listenPort = port;
    s.speakNotes = _speak;
    s.speakSender = _speakSender;
    s.senderTokens = _tokens;
    await widget.config.save();
    await widget.shareInbox.refreshFromSettings();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('settings.shareInbox', 'Share Inbox')),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'settings.peopleWithTheCompanionApp',
                  'People with the companion app can share a photo, GIF, video, link or note to this kiosk. Add a name below, hand that person the generated token to enter in their app.',
                ),
                style: TextStyle(color: context.look.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: tr('settings.listenPort', 'Listen port'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('settings.readNotesAloud', 'Read notes aloud'),
                  style: TextStyle(color: context.look.textPrimary),
                ),
                subtitle: Text(
                  tr(
                    'settings.textNotesOnlyPhotosHave',
                    'Text notes only. Photos have nothing to read, and a link read out is a stream of letters nobody can follow.',
                  ),
                  style: TextStyle(color: context.look.textSecondary, fontSize: 13),
                ),
                value: _speak,
                onChanged: (v) => setState(() => _speak = v),
              ),
              if (_speak) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('settings.sayWhoItIsFrom', 'Say who it is from first'),
                    style: TextStyle(color: context.look.textPrimary),
                  ),
                  value: _speakSender,
                  onChanged: (v) => setState(() => _speakSender = v),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                tr('settings.senders', 'Senders'),
                style: TextStyle(
                  color: context.look.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_tokens.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    tr('settings.noOneAddedYet', 'No one added yet'),
                    style: TextStyle(color: context.look.textSecondary),
                  ),
                ),
              for (final t in _tokens)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          t.name,
                          style: TextStyle(color: context.look.textPrimary),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          t.token,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.look.textSecondary,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: tr('settings.copyToken', 'Copy token'),
                        onPressed: () => _copy(t.token),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Color(0xFFFF8A8A),
                        ),
                        tooltip: tr('settings.remove', 'Remove'),
                        onPressed: () => setState(() => _tokens.remove(t)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newName,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: tr('settings.addSenderName', 'Add sender (name)'),
                        hintText: "Mum's phone",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addSender(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _addSender, child: Text(tr('settings.add', 'Add'))),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('settings.cancel', 'Cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('settings.save', 'Save'))),
      ],
    );
  }
}

/// Switching the panel off by itself when there's nothing worth showing.
/// The switching is done by the same host-side service Alexa drives, so a
/// touch brings it back — see [ScreenIdleService].
/// The volumes of the sounds the panel makes by itself, apart from the
/// music: saved as you drag, so you can judge them by ear. The web editor's
/// Sound card sets the same ones.
///
/// Do Not Disturb sits at the top because it mutes every one of them. The
/// sliders keep their levels while it is on, so turning it off puts each
/// back where it was.
class _SoundSettingsTile extends StatelessWidget {
  const _SoundSettingsTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final s = service.config.shareInbox;
    final muted = s.dndMuted;

    Widget slider({
      required IconData icon,
      required String title,
      required String help,
      required double value,
      required void Function(double) set,
    }) {
      return Opacity(
        opacity: muted ? 0.45 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Slider(
                value: value.clamp(0, 100),
                max: 100,
                divisions: 20,
                label: '${value.round()}%',
                // Still movable while muted: set it now, hear it later.
                onChanged: (v) {
                  set(v);
                  service.save();
                },
              ),
              trailing: Text(muted ? tr('settings.muted', 'Muted') : '${value.round()}%'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(80, 0, 24, 12),
              child: Text(
                help,
                style: TextStyle(color: context.look.textSecondary, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SwitchListTile(
          secondary: Icon(
            muted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
          ),
          title: Text(tr('settings.doNotDisturb', 'Do Not Disturb')),
          subtitle: Text(
            muted
                ? tr('settings.onEverythingBelowIsMuted', 'On — everything below is muted. Turn it off to hear them again at the same levels.')
                : tr('settings.mutesEverySoundBelowAt', 'Mutes every sound below at once, and keeps the screen from waking for shares. The same switch as the top bar.'),
          ),
          value: muted,
          onChanged: (on) {
            s.dndMuted = on;
            service.save();
          },
        ),
        const Divider(height: 1),
        slider(
          icon: Icons.notifications,
          title: tr('settings.notifications', 'Notifications'),
          help: tr('settings.theChimeWhenSomethingIs', 'The chime when something is shared to the panel.'),
          value: s.notificationVolume,
          set: (v) => s.notificationVolume = v,
        ),
        slider(
          icon: Icons.record_voice_over,
          title: tr('settings.speech', 'Speech'),
          help: tr('settings.sharedNotesReadAloudAnd', 'Shared notes read aloud, and bin-day reminders.'),
          value: s.speechVolume,
          set: (v) => s.speechVolume = v,
        ),
        slider(
          icon: Icons.menu_book_outlined,
          title: tr('settings.newsReader', 'News reader'),
          help: tr('settings.articlesReadOutFromThe', 'Articles read out from the news widget.'),
          value: s.readerVolume,
          set: (v) => s.readerVolume = v,
        ),
        slider(
          icon: Icons.timer_outlined,
          title: tr('settings.timers', 'Timers'),
          help: "A kitchen timer's sound, and its voice saying which it was.",
          value: s.timerVolume,
          set: (v) => s.timerVolume = v,
        ),
      ],
    );
  }
}

class _ScreenSettingsTile extends StatelessWidget {
  const _ScreenSettingsTile();

  static const List<int> _choices = [2, 5, 10, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final s = service.config.screen;
    final light = context.watch<BrightnessService>();
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: Text(tr('settings.brightness', 'Brightness')),
          subtitle: Slider(
            value: light.level.toDouble(),
            min: BrightnessService.minimum.toDouble(),
            max: 100,
            divisions: 100 - BrightnessService.minimum,
            label: '${light.level}%',
            onChanged: light.set,
          ),
          trailing: Text('${light.level}%'),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.brightness_4),
          title: Text(tr('settings.turnTheScreenOffWhen', 'Turn the screen off when idle')),
          subtitle: Text(
            tr(
              'settings.onceNothingIsPlayingNo',
              'Once nothing is playing, no slideshow is running and nobody has touched it. A touch brings it straight back.',
            ),
          ),
          isThreeLine: true,
          value: s.autoOffEnabled,
          onChanged: (v) {
            s.autoOffEnabled = v;
            service.save();
          },
        ),
        if (s.autoOffEnabled) ...[
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(tr('settings.waitFor', 'Wait for')),
            trailing: DropdownButton<int>(
              value: _choices.contains(s.idleMinutes) ? s.idleMinutes : 15,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in _choices)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m == 60 ? tr('settings.1Hour', '1 hour') : '$m minutes'),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                s.idleMinutes = v;
                service.save();
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.music_note),
            title: Text(tr('settings.wakeWhenMusicStarts', 'Wake when music starts')),
            subtitle: Text(
              tr(
                'settings.onlyUndoesASwitchOff',
                'Only undoes a switch-off this setting made — it leaves the screen alone if you turned it off by voice.',
              ),
            ),
            isThreeLine: true,
            value: s.wakeOnMusic,
            onChanged: (v) {
              s.wakeOnMusic = v;
              service.save();
            },
          ),
        ],
      ],
    );
  }
}

/// A phone running the android-ip-camera app, used as a wireless camera.
///
/// The stream itself is H.264 straight from the phone's hardware encoder, and
/// zooming asks the phone to zoom its sensor rather than enlarging the picture
/// once it arrives — see [CameraService] for the control protocol.
class _CameraSettingsTile extends StatelessWidget {
  const _CameraSettingsTile();

  Future<void> _edit(BuildContext context) async {
    final service = context.read<ConfigService>();
    final camera = context.read<CameraService>();
    final s = service.config.camera;
    final address = TextEditingController(text: s.address);
    final user = TextEditingController(text: s.username);
    final pass = TextEditingController(text: s.password);
    final resolution = TextEditingController(text: s.streamResolution);
    final rotate = TextEditingController(text: '${s.rotate}');
    final turns = TextEditingController(text: '${s.viewQuarterTurns}');

    Widget field(
      String label,
      TextEditingController c, {
      String? hint,
      bool obscure = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.camera', 'Camera')),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'settings.aPhoneRunningAndroidIp',
                    'A phone running android-ip-camera, on the same network. Take the address and credentials from the app on the phone; turn its HTTPS off, since it uses a self-signed certificate.',
                  ),
                  style: TextStyle(color: context.look.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 14),
                field(tr('settings.address', 'Address'), address, hint: '192.168.1.52:4444'),
                field(tr('settings.username', 'Username'), user),
                field(tr('settings.password', 'Password'), pass, obscure: true),
                field(tr('settings.streamSize', 'Stream size'), resolution, hint: '1920x1080'),
                field(
                  tr(
                    'settings.rotateOnThePhoneDegrees',
                    'Rotate on the phone (degrees)',
                  ),
                  rotate,
                  hint: tr('settings.090180Or270', '0, 90, 180 or 270 — MJPEG only'),
                ),
                field(
                  tr(
                    'settings.turnThePictureHereQuarter',
                    'Turn the picture here (quarter turns)',
                  ),
                  turns,
                  hint:
                      tr(
                        'settings.03ForWhenThe',
                        '0-3, for when the phone gets its own orientation wrong',
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('settings.save', 'Save')),
          ),
        ],
      ),
    );

    if (saved != true) return;
    s.address = address.text.trim().replaceAll(RegExp(r'^https?://'), '');
    s.username = user.text.trim();
    s.password = pass.text;
    s.streamResolution = resolution.text.trim();
    s.rotate = int.tryParse(rotate.text.trim()) ?? 0;
    s.viewQuarterTurns = (int.tryParse(turns.text.trim()) ?? 0) % 4;
    await service.save();
    await camera.refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final s = service.config.camera;
    final camera = context.watch<CameraService>();
    final status = camera.status;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.videocam),
          title: Text(tr('settings.phoneCamera', 'Phone camera')),
          subtitle: Text(
            tr(
              'settings.showsALiveViewFrom',
              'Shows a live view from a phone running android-ip-camera, from a button in the top bar.',
            ),
          ),
          isThreeLine: true,
          value: s.enabled,
          onChanged: (v) {
            s.enabled = v;
            service.save();
          },
        ),
        if (s.enabled) ...[
          ListTile(
            leading: const Icon(Icons.picture_in_picture_alt_outlined),
            title: Text(tr('settings.position', 'Position')),
            subtitle: Text(cornerLabel(s.corner)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _CornerPicker(
              value: s.corner,
              enabled: true,
              onChanged: (c) {
                service.config.assignCorner(OverlaySlot.camera, c);
                service.save();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(tr('settings.cameraPhone', 'Camera phone')),
            subtitle: Text(
              s.address.isEmpty
                  ? tr('settings.notConfigured', 'Not configured')
                  : status == null
                  ? '${s.address} — ${camera.lastError ?? 'not reached yet'}'
                  : '${s.address} — ${status.lenses.length} lens'
                        '${status.lenses.length == 1 ? '' : 'es'}'
                        '${status.batteryPercent == null ? '' : ', battery ${status.batteryPercent}%'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _edit(context),
          ),
        ],
      ],
    );
  }
}

/// The widget dashboard and the browser page that arranges it.
class _DashboardSettingsTile extends StatelessWidget {
  const _DashboardSettingsTile();

  Future<void> _editPort(BuildContext context) async {
    final service = context.read<ConfigService>();
    final dashboard = context.read<DashboardService>();
    final s = service.config.dashboard;
    final port = TextEditingController(text: '${s.editorPort}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.editorPort', 'Editor port')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'settings.thePortTheDashboardEditor',
                  'The port the dashboard editor is served on. Separate from the Share Inbox, so one can be exposed beyond your network without the other.',
                ),
                style: TextStyle(color: context.look.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: port,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: tr('settings.port', 'Port'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('settings.save', 'Save')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    s.editorPort = int.tryParse(port.text.trim()) ?? 8090;
    await service.save();
    await dashboard.refreshFromSettings();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final dashboard = context.watch<DashboardService>();
    final s = service.config.dashboard;
    final theme = dashboard.themes.byId(s.themeId);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.dashboard_outlined),
          title: Text(tr('settings.widgetDashboard', 'Widget dashboard')),
          subtitle: Text(
            tr(
              'settings.aScreenOfWidgetsClock',
              'A screen of widgets — clock, weather, calendar, news, now playing — arranged from a browser. Adds a button to the top bar.',
            ),
          ),
          isThreeLine: true,
          value: s.enabled,
          onChanged: (v) async {
            s.enabled = v;
            await service.save();
            await dashboard.refreshFromSettings();
          },
        ),
        if (s.enabled) ...[
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: Text(tr('settings.arrangeItInABrowser', 'Arrange it in a browser')),
            isThreeLine: dashboard.editorIpAddress != null ||
                dashboard.webPortNote != null,
            subtitle: Text([
              dashboard.editorAddress,
              if (dashboard.editorIpAddress != null)
                'or ${dashboard.editorIpAddress}',
              ?dashboard.webPortNote,
            ].join('\n')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editPort(context),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr('settings.theme', 'Theme')),
            // It dresses every screen now, not just the dashboard.
            subtitle: Text(tr('settings.theWholeKioskSLook', '{name} · the whole kiosk\'s look', {'name': theme.name})),
            trailing: DropdownButton<String>(
              value: dashboard.themes.all.any((t) => t.id == s.themeId)
                  ? s.themeId
                  : dashboard.themes.all.first.id,
              underline: const SizedBox.shrink(),
              items: dashboard.themes.all
                  .map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                s.themeId = v;
                service.save();
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// A Hisense VIDAA television, driven by the dashboard's TV widget.
class _TvSettingsTile extends StatelessWidget {
  const _TvSettingsTile();

  Future<void> _edit(BuildContext context) async {
    final service = context.read<ConfigService>();
    final s = service.config.tv;
    final host = TextEditingController(text: s.host);
    final uuid = TextEditingController(text: s.uuid);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.television', 'Television')),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'settings.theSetMustBeOn',
                  'The set must be on the same network. Only one controller may hold a session at a time — the connection identity comes from this UUID, so two controllers sharing one will displace each other. Changing the UUID means pairing again.',
                ),
                style: TextStyle(color: context.look.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: host,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: tr('settings.address', 'Address'),
                  hintText: '192.168.1.156',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: uuid,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: tr('settings.controllerUuid', 'Controller UUID'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('settings.save', 'Save')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    s.host = host.text.trim();
    s.uuid = uuid.text.trim();
    await service.save();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConfigService>();
    final s = service.config.tv;
    final tv = context.watch<TvService>();

    final status = switch (tv.conn) {
      ConnState.connected => tr('settings.connectedTo', 'Connected to {host}', {'host': s.host}),
      ConnState.connecting => tr('settings.connectingTo', 'Connecting to {host}…', {'host': s.host}),
      ConnState.needsPairing => tr('settings.needsPairingOpenTheTv', 'Needs pairing — open the TV widget'),
      ConnState.error => tv.lastError ?? tr('settings.couldNotReach', 'Could not reach {host}', {'host': s.host}),
      ConnState.disconnected => tr('settings.connectsWhenTheTvWidget', 'Connects when the TV widget is on screen'),
    };

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.tv),
          title: Text(tr('settings.televisionRemote', 'Television remote')),
          subtitle: Text(
            tr(
              'settings.addsATvRemoteTo',
              'Adds a TV remote to the dashboard widgets — power, volume and a direction pad for a Hisense VIDAA set.',
            ),
          ),
          isThreeLine: true,
          value: s.enabled,
          onChanged: (v) {
            s.enabled = v;
            service.save();
          },
        ),
        if (s.enabled)
          ListTile(
            leading: Icon(
              Icons.settings_remote,
              color: tv.conn == ConnState.connected ? Colors.greenAccent : null,
            ),
            title: Text(tr('settings.addressAndPairing', 'Address and pairing')),
            subtitle: Text(status),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _edit(context),
          ),
        if (s.enabled)
          ListTile(
            leading: const Icon(Icons.pin),
            title: Text(tr('settings.pairAgain', 'Pair again')),
            subtitle: Text(
              tr(
                'settings.onlyIfTheRemoteHas',
                'Only if the remote has stopped working. The saved pairing is kept across restarts, so the TV no longer shows its code each time the panel starts.',
              ),
            ),
            isThreeLine: true,
            trailing: OutlinedButton(
              onPressed: () => _pairAgain(context),
              child: Text(tr('settings.showCodeOnTv', 'Show code on TV')),
            ),
          ),
      ],
    );
  }

  Future<void> _pairAgain(BuildContext context) async {
    final tv = context.read<TvService>();
    await tv.pairAgain();
    if (!context.mounted || tv.conn != ConnState.needsPairing) return;
    final pin = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('settings.enterTheCodeOnThe', 'Enter the code on the TV')),
        content: TextField(
          controller: pin,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 28, letterSpacing: 6),
          textAlign: TextAlign.center,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('settings.cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(pin.text),
            child: Text(tr('settings.pair', 'Pair')),
          ),
        ],
      ),
    );
    final code = entered?.trim() ?? '';
    if (code.isEmpty || int.tryParse(code) == null) {
      // Left waiting for a PIN, the widget would say so; reconnecting on
      // the old token puts things back as they were.
      unawaited(tv.connect());
      return;
    }
    final ok = await tv.submitPin(code);
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(ok ? tr('settings.pairedWithTheTv', 'Paired with the TV.') : tr('settings.theTvDidNotAccept', 'The TV did not accept that code.')),
      ));
    }
  }
}

/// One tab: an icon and its name, white when chosen — the kiosk's pill style.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? context.look.background.first : context.look.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? context.look.textPrimary : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
