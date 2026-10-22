import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart' show ShareInboxSettings;
import 'models/immich_models.dart';
import 'dashboard/live_preview.dart';
import 'dashboard/photo_backdrop.dart';
import 'dashboard/tile_renderer.dart';
import 'services/air_quality_service.dart';
import 'services/brightness_service.dart';
import 'services/bins_service.dart';
import 'services/carbon_service.dart';
import 'services/markets_service.dart';
import 'services/tfl_service.dart';
import 'services/transitous_service.dart';
import 'services/planes_service.dart';
import 'services/tides_service.dart';
import 'services/traffic_cams_service.dart';
import 'services/fuel_service.dart';
import 'services/reminders_service.dart';
import 'services/chores_service.dart';
import 'services/govee_service.dart';
import 'services/code_widgets.dart';
import 'services/custom_widgets.dart';
import 'services/glowmarkt_service.dart';
import 'services/home_assistant_service.dart';
import 'services/homey_service.dart';
import 'services/railcam_service.dart';
import 'services/rain_service.dart';
import 'services/notes_service.dart';
import 'services/shopping_service.dart';
import 'services/timer_service.dart';
import 'services/timer_sounds.dart';
import 'dashboard/widgets/widgets.dart';
import 'services/audio_levels_service.dart';
import 'services/background_pause.dart';
import 'services/kiosk_browser.dart';
import 'services/kiosk_control_service.dart';
import 'services/floatplane_site.dart';
import 'services/nebula_site.dart';
import 'services/video_link.dart';
import 'services/video_player_service.dart';
import 'services/youtube_site.dart';
import 'services/yt_dlp.dart';
import 'services/camera_service.dart';
import 'services/article_reader.dart';
import 'services/config_service.dart';
import 'services/playback_source.dart';
import 'services/dashboard_service.dart';
import 'services/feed_service.dart';
import 'services/immich_service.dart';
import 'services/indoor_sensor_service.dart';
import 'services/locked_folder_service.dart';
import 'services/media_cache.dart';
import 'services/now_playing_service.dart';
import 'services/screen_idle_service.dart';
import 'services/voice_commands.dart';
import 'services/voice_service.dart';
import 'widgets/voice_indicator.dart';
import 'widgets/konami_overlay.dart';
import 'services/screen_state.dart';
import 'services/share_inbox_service.dart';
import 'services/spotify_service.dart';
import 'services/lan_speedtest_service.dart';
import 'services/speedtest_service.dart';
import 'services/tts_service.dart';
import 'services/tv_service.dart';
import 'services/unifi_service.dart';
import 'services/weather_service.dart';
import 'widgets/module_bar.dart' show openLockedFolder;
import 'screens/about_screen.dart';
import 'screens/album_screen.dart';
import 'screens/dashboard_screen.dart';
import 'dashboard/widgets/weather_forecast_sheet.dart';
import 'dashboard/widgets/tv_remote_sheet.dart';
import 'screens/gallery_screen.dart';
import 'screens/home_screen.dart';
import 'screens/locked_folder_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/slideshow_screen.dart';
import 'screens/video_player_screen.dart';
import 'widgets/camera_overlay.dart';
import 'widgets/incoming_share_overlay.dart';
import 'widgets/reading_bar.dart';
import 'widgets/on_screen_keyboard.dart';
import 'widgets/now_playing_overlay.dart';
import 'widgets/video_overlay.dart';
import 'app_paths.dart';
import 'l10n/l10n.dart';
import 'theme.dart';
import 'dashboard/dashboard_theme.dart';
import 'look.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Before anything reads its settings: the project was ImmichKioskPi, and
  // its folders move to their new names on the first start after that.
  await AppPaths.migrate();
  // Big in-memory image budget — the Pi has 8 GB and revisited photos should
  // redisplay with no decode cost.
  HomeCanvasCache.configureImageCache();

  final config = ConfigService();
  await config.load();
  // Before anything is drawn, so the first frame is in the right language.
  await L10n.instance.use(config.config.language);

  final weather = WeatherService(config);
  unawaited(weather.refresh());

  // Indoor temperature, read from Home Assistant rather than scanned for.
  final indoor = IndoorSensorService();
  unawaited(indoor.start(config.config.homeAssistant));

  // Whether the screen is lit. While it is dark the kiosk rests: no
  // animation, no photo decoding, no polling for the screen's sake.
  final screen = ScreenState()..start();

  // Reads what the paired phone is playing over Bluetooth AVRCP.
  final nowPlaying = NowPlayingService()
    ..screen = screen
    ..preferAudioRouted = config.config.nowPlaying.playAudioHere;
  unawaited(nowPlaying.start());

  // Full playback control for a Spotify Premium account via the Web API,
  // shown in preference to the AVRCP source above whenever it has something
  // to show. A no-op until the one-time login is done in Settings.
  final spotify = SpotifyService(config)..screen = screen;
  unawaited(spotify.start());

  // Lets the companion phone app share a photo/GIF/video/link/note to the
  // kiosk directly — no separate relay, just a small HTTP listener here.
  // Reads shared notes aloud. Built here and handed over rather than owned by
  // the inbox, so speech being unavailable is not the inbox's problem.
  final speech = TtsService();

  final shareInbox = ShareInboxService(config)..speech = speech;
  unawaited(shareInbox.start());

  // Reads a news article aloud, pausing whatever is playing while it does
  // and carrying it on afterwards — only if it was playing to begin with.
  PlaybackSource? pausedForReading;
  final reader = ArticleReader(
    output: PiperSpeechOutput(speech),
    voiceFor: speech.voiceFor,
    voiceId: speech.voiceId,
    // Nothing while Do Not Disturb is on — read at, not paused: turning it
    // off mid-article brings the voice straight back.
    volume: () => config.config.shareInbox.readerOut,
    onStart: () {
      for (final PlaybackSource p in [spotify, nowPlaying]) {
        if (p.available && p.now.isPlaying) {
          pausedForReading = p;
          unawaited(p.playPause());
          return;
        }
      }
    },
    onEnd: () {
      final p = pausedForReading;
      pausedForReading = null;
      if (p != null && p.available && !p.now.isPlaying) {
        unawaited(p.playPause());
      }
    },
  );

  // Widget types have to be registered before anything reads the dashboard:
  // the editor's palette and each widget's settings form are both generated
  // from the registry.
  registerBuiltInWidgets();

  // Feeds for the dashboard's calendar and news widgets, shared by URL so two
  // widgets on the same feed cost one fetch.
  final feeds = FeedService()..start();

  // One instance, shared with the provider below rather than created twice:
  // it holds the album and asset caches, and a second copy would warm its own
  // from scratch.
  final immich = ImmichService(config);

  // Reads the UniFi console for the network widgets. One service, one poll,
  // five widgets — none of them should cost their own round trip.
  final unifi = UnifiService(config);
  unawaited(unifi.start());

  final dashboard = DashboardService(
    config,
    // Resolved on each request so the editor's preview reflects the moment
    // it was asked for.
    previewData: () => PreviewData(
      weather: weather,
      feeds: feeds,
      playback: spotify.available ? spotify : nowPlaying,
    ),
    // For the Immich widget's album picker. Cached by the service it calls,
    // so opening the editor does not hammer the server.
    albums: () async => {
      for (final a in await immich.getAlbums()) a.id: a.name,
    },
  );
  unawaited(dashboard.start());

  // Switches the panel off by itself when nothing's playing and no
  // slideshow is running — see ScreenIdleService for why the switching
  // itself is left to the host-side screen_control.py service.
  final screenIdle = ScreenIdleService(config, [spotify, nowPlaying])..start();

  // YouTube, Floatplane and Nebula, played by the kiosk itself: sent from
  // the phone, opened from the news, or picked on the dashboard. yt-dlp
  // finds the streams; each site holds its sign-in and its feed.
  final ytDlp = YtDlp();
  final youtube = YouTubeSite(config, ytDlp);
  final floatplane = FloatplaneSite(config, ytDlp);
  final nebula = NebulaSite(config, ytDlp);
  final sites = [youtube, floatplane, nebula];
  // The sign-ins are checked once yt-dlp is known to be there to check them.
  unawaited(
    ytDlp.start().then((_) {
      for (final site in sites) {
        site.start();
      }
    }),
  );
  // Music playing already is paused rather than talked over, and a video
  // playing keeps the screen on.
  final player = VideoPlayerService(config, ytDlp, sites)
    ..onStart = () {
      for (final PlaybackSource p in [spotify, nowPlaying]) {
        if (p.available && p.now.isPlaying) unawaited(p.playPause());
      }
    }
    ..start();
  screenIdle.videoPlaying = () => player.playing;
  // Their sign-in pages, for signing in from a computer instead of the panel.
  dashboard.videoSites = sites;

  // Railcam's cameras, picked in the editor and watched through the same
  // player. Its pages name their streams, so yt-dlp is only asked about
  // the cameras YouTube carries.
  final railcam = RailcamService();
  dashboard.railcams = railcam.choices;
  player.finders['railcam'] = (link, height) => railcam.find(
    link,
    maxHeight: height,
    youtube: (yt) => player.resolve(yt, maxHeight: height),
  );

  // Programs that cannot be seen behind a full-screen video — the desktop's
  // taskbar, the TV remote app — are paused for its length, leaving the CPU
  // to the video. Carried on at start-up too, in case the kiosk stopped
  // mid-video with them paused. Chained, so a video going full screen and
  // straight back to picture-in-picture cannot leave them stopped.
  final background = BackgroundPause();
  var backgroundChange = background.resume(all: true);
  var coveredByVideo = false;
  player.addListener(() {
    final covered = player.view == VideoView.full;
    if (covered == coveredByVideo) return;
    coveredByVideo = covered;
    backgroundChange = backgroundChange.then(
      (_) => covered ? background.pause() : background.resume(),
    );
  });

  // The backlight as it was left in Settings or the editor, rather than
  // whatever systemd restored — which after a shutdown while asleep is 1.
  final brightness = BrightnessService(config);
  unawaited(brightness.start());
  dashboard.brightness = brightness;

  // A share arriving is worth waking the panel for — unless Do Not Disturb is
  // on, which the screen service checks for itself.
  shareInbox.onItemArrived = screenIdle.wakeForNotification;

  // The household notes board. Text shared from the phone app goes on it as
  // well as popping up; the editor server has a page for posting to it.
  final notes = NotesService();
  unawaited(notes.load());

  // Reminders shared from the phone app: text that reads as one — "remind
  // me to…", "don't forget…" — goes on the Reminders list rather than the
  // Notes board, and is said aloud when it falls due.
  final reminders = RemindersService();
  unawaited(reminders.load());
  reminders
    ..onDue = (r) async {
      await screenIdle.wakeForNotification();
      showRemindersPage(config);
      final words = r.from.isEmpty
          ? tr('reminders.spoken', 'Reminder: {what}', {'what': r.text})
          : tr('reminders.spokenFrom', 'Reminder from {name}: {what}', {
              'name': r.from,
              'what': r.text,
            });
      await speech.speakAll([
        words,
      ], volume: config.config.shareInbox.speechOut);
    }
    ..start();

  shareInbox.onShared = (item) {
    final text = (item.content ?? '').trim();
    if (item.type != ShareType.text || text.isEmpty) return;
    final reminder = parseReminder(text, DateTime.now());
    if (reminder != null) {
      reminders.add(reminder, from: item.sender);
    } else {
      notes.add(text, from: item.sender);
    }
  };
  dashboard.notes = notes;

  // The shopping list, added to from phones and ticked off on the panel.
  final shopping = ShoppingService();
  unawaited(shopping.load());
  dashboard.shopping = shopping;

  // Chores ticked off, and the week's stars, kept across restarts.
  final chores = ChoresService();
  unawaited(chores.load());

  // Kitchen timers, owned up here so they keep running — and still speak —
  // after the panel has left the dashboard. The sound and the voice play at
  // the timers' own volume, and not at all while Do Not Disturb is on — the
  // ring on screen still says it is done.
  final timerSounds = TimerSounds();
  ShareInboxSettings inbox() => config.config.shareInbox;
  final timers = TimerService(
    speak: (text) async {
      if (inbox().dndMuted) return;
      await speech.speak(text, volume: inbox().timerOut);
    },
    play: (sound) async {
      if (inbox().dndMuted) return;
      await timerSounds.play(sound, volume: inbox().timerOut);
    },
    silence: timerSounds.stop,
    onFinished: screenIdle.wakeForNotification,
  );
  dashboard.timerSounds = timerSounds;

  // Bin-day reminders, spoken the evening before whether or not the
  // dashboard is showing.
  final bins = BinsService(
    config,
    speak: (text) async {
      if (inbox().dndMuted) return;
      await speech.speak(text, volume: inbox().speechOut);
    },
  )..start();

  // Home Assistant entities for the dashboard, over the connection set up
  // for the indoor sensor. Idle until a widget asks; the editor's entity
  // picker asks it for the list.
  // For the editor's preview of the photo background: the photo showing
  // now, or any photo if the dashboard is not up.
  dashboard.backgroundImage = () async {
    final id =
        PhotoBackdrop.current ??
        (await immich.getRandomAssets(count: 1)).firstOrNull?.id;
    return id == null ? null : immich.previewBytes(id);
  };

  final homeAssistant = HomeAssistantService(config);
  dashboard.haEntities = homeAssistant.choices;
  // Widgets installed from a file in the editor. Drawn again as one is
  // installed or removed, so it is on the panel without a restart.
  final customWidgets = CustomWidgets(onChanged: rebuildEverything);
  await customWidgets.load();
  dashboard.customWidgets = customWidgets;
  // And as Dart, built into the app by the panel itself.
  dashboard.codeWidgets = CodeWidgets();

  final homey = HomeyService(config);
  dashboard.homeyDevices = homey.choices;
  dashboard.homeyStatus = homey.status;
  dashboard.extraLists.addAll({
    'homeyMoods': () =>
        homey.listChoices('moods/mood', (m) => m['name'] as String?),
    'homeyVariables': () =>
        homey.listChoices('logic/variable', (v) => v['name'] as String?),
    'homeyLogs': () => homey.listChoices(
      'insights/log',
      (l) => l['title'] is String ? '${l['ownerName']} · ${l['title']}' : null,
    ),
  });
  dashboard.homeyLights = homey.lightChoices;
  dashboard.homeyZones = homey.zoneChoices;
  dashboard.homeyFlows = homey.flowChoices;
  dashboard.voices = speech.voiceChoices;

  // The place in Settings → Weather, once found: where "near home" is.
  ({double lat, double lon})? home() {
    final w = config.config.weather;
    final lat = w.latitude, lon = w.longitude;
    return lat == null || lon == null ? null : (lat: lat, lon: lon);
  }

  // What the panel makes nothing of is asked of Home Assistant's Assist —
  // the lights, the heating, "what's the temperature indoors" — and its
  // answer is shown, and said at the speech volume unless Do Not Disturb
  // is on.
  Future<String?> askHomeAssistant(String heard) async {
    final answer = await homeAssistant.converse(
      VoiceCommands.forAssist(heard, wake: config.config.screen.wakeWord),
    );
    if (answer != null && !inbox().dndMuted) {
      unawaited(speech.speak(answer, volume: inbox().speechOut));
    }
    return answer;
  }

  // The wake words, and what is said after them: heard by a listener this
  // starts while voice control is switched on, and done here. The screen
  // is lit on the wake words, before anything is asked for.
  final voice = VoiceService(
    enabled: () => config.config.screen.voiceControl,
    wake: () => config.config.screen.wakeWord,
    act: (heard) => runVoiceCommand(heard, config, screenIdle),
    ask: askHomeAssistant,
    onWake: () {
      unawaited(screenIdle.wake());
      unawaited(_listeningBeep());
    },
  );
  config.addListener(voice.sync);
  voice.sync();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: config),
        Provider<ImmichService>.value(value: immich),
        ChangeNotifierProvider.value(value: unifi),
        ChangeNotifierProvider(create: (_) => LockedFolderService(config)),
        ChangeNotifierProvider.value(value: weather),
        ChangeNotifierProvider.value(value: nowPlaying),
        ChangeNotifierProvider.value(value: spotify),
        ChangeNotifierProvider.value(value: indoor),
        ChangeNotifierProvider.value(value: shareInbox),
        ChangeNotifierProvider.value(value: ytDlp),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: youtube),
        ChangeNotifierProvider.value(value: floatplane),
        ChangeNotifierProvider.value(value: nebula),
        ChangeNotifierProvider.value(value: reader),
        Provider<ScreenIdleService>.value(value: screenIdle),
        ChangeNotifierProvider.value(value: screen),
        ChangeNotifierProvider.value(value: brightness),
        ChangeNotifierProvider(create: (_) => CameraService(config)),
        ChangeNotifierProvider.value(value: feeds),
        ChangeNotifierProvider.value(value: dashboard),
        ChangeNotifierProvider(create: (_) => TvService(config)),
        // Owned above the dashboard so a test keeps running while you
        // page away from the widget, and the result is still there when
        // you come back.
        ChangeNotifierProvider(create: (_) => SpeedtestService()),
        ChangeNotifierProvider(create: (_) => LanSpeedtestService()),
        // Idle until the visualiser asks it for something: creating it costs
        // nothing, and it starts no capture until a widget attaches.
        ChangeNotifierProvider(create: (_) => AudioLevelsService()),
        ChangeNotifierProvider.value(value: voice),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider<RemindersService?>.value(value: reminders),
        ChangeNotifierProvider.value(value: shopping),
        ChangeNotifierProvider.value(value: chores),
        ChangeNotifierProvider.value(value: timers),
        ChangeNotifierProvider.value(value: bins),
        // Made when an Air & pollen widget first asks, and not before.
        ChangeNotifierProvider(create: (_) => AirQualityService(config)),
        ChangeNotifierProvider(create: (_) => CarbonService(config)),
        ChangeNotifierProvider(create: (_) => RainService(config)),
        // Made when a London lines or arrivals tile first asks.
        ChangeNotifierProvider(create: (_) => TflService()),
        // Made when a Departures (Europe) tile first asks.
        ChangeNotifierProvider(create: (_) => TransitousService()),
        ChangeNotifierProvider(create: (_) => PlanesService(home: home)),
        ChangeNotifierProvider(create: (_) => TrafficCamsService(home: home)),
        ChangeNotifierProvider(create: (_) => TidesService(home: home)),
        ChangeNotifierProvider.value(value: railcam),
        // Made when a Fuel prices tile first asks.
        ChangeNotifierProvider(create: (_) => FuelService(config)),
        // Made when a Stocks or Crypto widget first asks.
        ChangeNotifierProvider(create: (_) => MarketsService()),
        ChangeNotifierProvider.value(value: homeAssistant),
        Provider<GlowmarktService>.value(value: GlowmarktService(config)),
        ChangeNotifierProvider.value(value: homey),
        ChangeNotifierProvider.value(value: customWidgets),
        // Made when a Lights widget first asks; it then listens for Govee
        // devices on the home network.
        ChangeNotifierProvider(create: (_) => GoveeService()),
      ],
      child: const HomeCanvasApp(),
    ),
  );

  // Lets the TV remote app's copy of the control bar reach in here: open
  // the dashboard, Settings, the Locked Folder and so on. Local only — see
  // KioskControlService.
  unawaited(
    KioskControlService(
      state: () {
        final context = rootNavigatorKey.currentContext;
        final camera = context?.read<CameraService>();
        return KioskState(
          dashboard: config.config.dashboard.enabled,
          lockedFolder: context?.read<LockedFolderService>().canUse ?? false,
          camera: camera?.isConfigured ?? false,
          cameraOpen: camera?.isOpen ?? false,
          dnd: config.config.shareInbox.dndMuted,
        );
      },
      run: (command) => runKioskCommand(command, config),
      playVideo: (url) {
        final link = VideoLink.parse(url);
        if (link == null) return false;
        unawaited(player.play(link));
        return true;
      },
      setDnd: (muted) {
        config.config.shareInbox.dndMuted = muted;
        unawaited(config.save());
      },
      screenLit: screen.set,
      voice: (heard) async =>
          runVoiceCommand(heard, config, screenIdle) ??
          await askHomeAssistant(heard),
    ).start(),
  );
}

/// Brings up the dashboard page the Reminders widget is on — when one falls
/// due, so what is being said is also on the screen. From wherever the
/// panel is: an open dashboard turns to the page, anything else gives way
/// to the dashboard.
void showRemindersPage(ConfigService config) {
  final settings = config.config.dashboard;
  if (!settings.enabled) return;
  final tile = settings.widgets.where((w) => w.type == 'reminders').firstOrNull;
  if (tile == null) return;
  DashboardScreen.requestedPage.value = tile.page;
  if (DashboardScreen.isOpen) return;
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
  navigator.push(DashboardScreen.route());
}

/// A very quiet beep: "hey canvas" was heard, and the panel is listening.
/// For when nobody is looking at it to see it say so.
///
/// Played with `pw-play` rather than a player of the kiosk's own, which
/// takes a moment to open a file — and the moment is the point. The sound
/// is quiet in the file itself, and so stays quiet whatever plays it.
bool _beepWritten = false;

Future<void> _listeningBeep() async {
  try {
    final file = File(p.join(HomeCanvasCache.root, 'listening.wav'));
    // Written out afresh each time the kiosk starts, so a new build's
    // sound replaces the old one.
    if (!_beepWritten) {
      final bytes = await rootBundle.load('assets/sounds/listening.wav');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _beepWritten = true;
    }
    await Process.run('pw-play', [file.path]);
  } catch (_) {
    // No PipeWire, no beep: the screen still says it is listening.
  }
}

/// The dashboard itself on screen, whatever was on top of it or in its
/// place — Settings, a forecast, the albums. Null when it cannot be shown.
NavigatorState? _toDashboard(ConfigService config) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null || !config.config.dashboard.enabled) return null;
  var there = false;
  navigator.popUntil((route) {
    there = route.settings.name == DashboardScreen.routeName;
    return there || route.isFirst;
  });
  if (!there) navigator.push(DashboardScreen.route());
  return navigator;
}

/// Does what was said to the panel — [heard], as words — and says what that
/// was, or null when it asked for nothing the panel knows. The listener
/// only hears; `VoiceCommands` decides what was meant.
String? runVoiceCommand(
  String heard,
  ConfigService config,
  ScreenIdleService screen,
) {
  final navigator = rootNavigatorKey.currentState;
  final context = rootNavigatorKey.currentContext;
  if (navigator == null || context == null) return null;
  final settings = config.config.dashboard;
  final action = VoiceCommands.of(
    settings,
    wake: config.config.screen.wakeWord,
  ).resolve(heard);
  if (action == null) return null;

  // Spoken to, so looked at: lit, and counted as use.
  unawaited(screen.wake());
  // The TV remote app, or a browser, may be in front of the kiosk.
  unawaited(KioskBrowser.focusKiosk());

  switch (action) {
    case VoiceMusic(:final ask):
      // Whatever the panel's own player would be showing: Spotify when it
      // has something, a phone over Bluetooth otherwise.
      final spotify = context.read<SpotifyService>();
      final PlaybackSource music = spotify.available
          ? spotify
          : context.read<NowPlayingService>();
      if (!music.available) return null;
      final playing = music.now.isPlaying;
      switch (ask) {
        case VoiceMusicAsk.play:
          if (!playing) unawaited(music.playPause());
          return 'playing';
        case VoiceMusicAsk.pause:
          if (playing) unawaited(music.playPause());
          return 'paused';
        case VoiceMusicAsk.next:
          unawaited(music.next());
          return 'next track';
        case VoiceMusicAsk.previous:
          unawaited(music.previous());
          return 'previous track';
        case VoiceMusicAsk.louder || VoiceMusicAsk.quieter:
          if (!music.hasVolume) return null;
          final step = ask == VoiceMusicAsk.louder ? 0.1 : -0.1;
          unawaited(music.setVolume((music.volume + step).clamp(0.0, 1.0)));
          return ask == VoiceMusicAsk.louder ? 'louder' : 'quieter';
        case VoiceMusicAsk.mute || VoiceMusicAsk.unmute:
          if (!music.hasVolume) return null;
          if (music.muted != (ask == VoiceMusicAsk.mute)) {
            unawaited(music.toggleMute());
          }
          return ask == VoiceMusicAsk.mute ? 'muted' : 'unmuted';
      }
    case VoiceKonami():
      KonamiOverlay.said.value++;
      return '+30 lives';
    case VoiceShowPage(:final page):
      if (!settings.enabled) return null;
      // A page asked for by name is wanted for longer than its turn: held
      // there until "resume", or a tap on the page dots. An open dashboard
      // is told; one about to open reads it from the settings.
      final hold = settings.pageSeconds > 0;
      if (hold && DashboardScreen.isOpen) {
        DashboardScreen.requestedPause.value = true;
      } else if (hold && !settings.pagesPaused) {
        settings.pagesPaused = true;
        unawaited(config.save());
      }
      if (_toDashboard(config) == null) return null;
      DashboardScreen.requestedPage.value = page;
      return 'page ${page + 1}';
    case VoiceTurnPage(:final by):
      // Onto the dashboard first, if it is not showing: there is no page
      // to turn from anywhere else.
      final turn = DashboardScreen.isOpen;
      if (_toDashboard(config) == null) return null;
      if (turn) DashboardScreen.requestedTurn.value = by;
      return by > 0 ? 'next page' : 'previous page';
    case VoicePausePages(:final paused):
      if (DashboardScreen.isOpen) {
        DashboardScreen.requestedPause.value = paused;
      } else {
        settings.pagesPaused = paused;
        unawaited(config.save());
      }
      return paused ? 'pages paused' : 'pages resumed';
    case VoiceCamera(:final open):
      final camera = context.read<CameraService>();
      if (!camera.isConfigured) return null;
      if (camera.isOpen != open) camera.toggleOpen();
      return open ? 'camera' : 'camera closed';
    case VoiceGo(:final place):
      switch (place) {
        case VoicePlace.back:
          unawaited(navigator.maybePop());
          return 'back';
        case VoicePlace.photos:
          navigator.popUntil((route) => route.isFirst);
          return 'photos';
        case VoicePlace.dashboard:
          return _toDashboard(config) == null ? null : 'dashboard';
        case VoicePlace.forecast:
          final theme = context.read<DashboardService>().themes.byId(
            settings.themeId,
          );
          unawaited(showWeatherForecast(context, theme));
          return 'forecast';
        case VoicePlace.remote:
          // The dashboard's TV remote widget, as large as the panel —
          // not the remote app, which is a different remote.
          final theme = context.read<DashboardService>().themes.byId(
            settings.themeId,
          );
          unawaited(showTvRemote(context, theme, settings));
          return 'remote';
      }
  }
}

/// Carries out a command from [KioskControlService], the way the kiosk's own
/// control bar would.
void runKioskCommand(KioskCommand command, ConfigService config) {
  final navigator = rootNavigatorKey.currentState;
  final context = rootNavigatorKey.currentContext;
  if (navigator == null || context == null) return;
  switch (command) {
    case KioskCommand.photos:
      navigator.popUntil((route) => route.isFirst);
    case KioskCommand.dashboard:
      if (!config.config.dashboard.enabled) return;
      navigator.popUntil((route) => route.isFirst);
      navigator.push(DashboardScreen.route());
    case KioskCommand.settings:
      navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    case KioskCommand.lockedFolder:
      if (context.read<LockedFolderService>().canUse) {
        unawaited(openLockedFolder(context));
      }
    case KioskCommand.camera:
      final camera = context.read<CameraService>();
      if (camera.isConfigured) camera.toggleOpen();
  }
}

/// The overlay added in [HomeCanvasApp]'s `builder` sits as a *sibling* of
/// this Navigator (both are children of the same Stack), not a descendant of
/// it, so `Navigator.of(context)` from inside the overlay can't find it by
/// walking up the tree. A global key to the same Navigator sidesteps that.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class HomeCanvasApp extends StatelessWidget {
  const HomeCanvasApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The theme chosen for the dashboard dresses the whole kiosk.
    // HOMECANVAS_TEST_THEME=<id> shows another without saving it, for
    // screenshots.
    final themeId =
        Platform.environment['HOMECANVAS_TEST_THEME'] ??
        context.select<ConfigService, String>(
          (c) => c.config.dashboard.themeId,
        );
    final look = context.select<DashboardService, DashboardTheme>(
      (d) => d.themes.byId(themeId),
    );
    // Read so the app is rebuilt with Flutter's own widgets (date pickers,
    // tooltips) in the new language when it changes.
    final language = context.select<ConfigService, String>(
      (c) => c.config.language,
    );
    return KioskLook(theme: look, child: _app(context, look, language));
  }

  Widget _app(BuildContext context, DashboardTheme look, String language) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'HomeCanvas',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(look),
      // Flutter's own widgets in the panel's language where Flutter has it,
      // and in British English where it doesn't.
      locale: materialLocale(language),
      supportedLocales: [
        for (final l in kLanguages)
          if (GlobalMaterialLocalizations.delegate.isSupported(l.locale))
            l.locale,
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // The DSI touchscreen is delivered as mouse/unknown pointer events on
      // Flutter's Linux embedder, so enable drag-scrolling for every pointer
      // kind (otherwise touch drag doesn't scroll lists/grids).
      scrollBehavior: const _AppScrollBehavior(),
      // Stacked above the routed content itself (rather than added to each
      // screen individually) so a shared-content notification can pop up
      // over *any* screen — settings, a slideshow, a video — not just the
      // couple of screens the now-playing overlay lives in.
      builder: (context, child) => Listener(
        // Any touch counts as "someone's here", which is what stops the
        // idle timer switching the panel off mid-use. Listener sees the
        // event on the way down without consuming it, so nothing below
        // behaves any differently.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) =>
            context.read<ScreenIdleService>().noteInteraction(),
        child: _RestWhileDark(
          child: OnScreenKeyboard(
            enabled: !Platform.environment.containsKey('FLUTTER_TEST'),
            child: Stack(
              children: [
                if (child != null) _HiddenUnderVideo(child: child),
                // A video sent to the panel, full screen or floating over
                // whatever else is on it. Below the share popup, so something
                // arriving mid-video still shows.
                VideoOverlay(navigatorKey: rootNavigatorKey),
                IncomingShareOverlay(navigatorKey: rootNavigatorKey),
                // What is being read aloud, with its controls, over any screen.
                const ReadingBar(),
                // "Hey canvas" heard, and what was made of the rest.
                const VoiceIndicator(),
                const KonamiOverlay(),
                CameraOverlay(navigatorKey: rootNavigatorKey),
                // Draws tiles off screen for the dashboard editor's preview.
                const TileRenderHost(),
              ],
            ),
          ),
        ),
      ),
      home: const _RootGate(),
    );
  }
}

/// The whole kiosk, hidden while the screen is dark.
///
/// Hidden as far as Flutter is concerned: TickerMode stops every animation,
/// and everything that works on a timer for the screen's sake checks it —
/// see PauseWhenHidden. Nothing is taken off screen, so the last picture
/// stays in place and is there the instant the backlight comes back, while
/// the animations take up again with the next frame.
class _RestWhileDark extends StatelessWidget {
  const _RestWhileDark({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lit = context.select<ScreenState, bool>((s) => s.lit);
    return TickerMode(enabled: lit, child: child);
  }
}

/// Everything the Navigator shows, taken off screen while a video
/// covers it.
///
/// Flutter does not skip what is hidden behind something opaque: without
/// this, the whole screen underneath — a dashboard, the photo grid — was
/// composited again for every frame of the video, and its animations and
/// timers carried on. Offstage stops the drawing and TickerMode the
/// animations; widgets that decode photos or capture sound on a timer check
/// the same TickerMode (see PauseWhenHidden). All of it is kept, not rebuilt,
/// so it is back exactly as it was the moment the video closes or shrinks to
/// picture-in-picture.
class _HiddenUnderVideo extends StatelessWidget {
  const _HiddenUnderVideo({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final covered = context.select<VideoPlayerService, bool>(
      (y) => y.view == VideoView.full,
    );
    return TickerMode(
      enabled: !covered,
      child: Offstage(offstage: covered, child: child),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

/// Shows setup until a connection is configured, then the album browser.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    // Dev aids for headless verification (only active when the env var is set):
    //   HOMECANVAS_TEST_VIDEO=<assetId>       boot into the video player
    //   HOMECANVAS_TEST_SLIDESHOW=<albumId>   boot into the slideshow
    //   HOMECANVAS_TEST_GALLERY=<albumId>     boot into the photo gallery
    //   HOMECANVAS_TEST_WEATHER=expanded      open the weather detail card
    //   HOMECANVAS_TEST_DASHBOARD=<page>      open the dashboard at a page
    final immich = context.read<ImmichService>();
    final testVideo = Platform.environment['HOMECANVAS_TEST_VIDEO'];
    if (testVideo != null && testVideo.isNotEmpty) {
      return VideoPlayerScreen(
        asset: Asset(id: testVideo, type: AssetType.video),
        source: immich,
      );
    }
    final testSlideshow = Platform.environment['HOMECANVAS_TEST_SLIDESHOW'];
    if (testSlideshow != null && testSlideshow.isNotEmpty) {
      return _DebugAlbumLoader(
        albumId: testSlideshow,
        immich: immich,
        builder: (imgs) => SlideshowScreen(
          images: imgs,
          source: immich,
          settings: context.read<ConfigService>().slideshow,
        ),
      );
    }
    final testGallery = Platform.environment['HOMECANVAS_TEST_GALLERY'];
    if (testGallery != null && testGallery.isNotEmpty) {
      return _DebugAlbumLoader(
        albumId: testGallery,
        immich: immich,
        builder: (imgs) => GalleryScreen(
          assets: imgs,
          initialIndex:
              int.tryParse(
                Platform.environment['HOMECANVAS_TEST_GALLERY_INDEX'] ?? '',
              ) ??
              0,
          source: immich,
        ),
      );
    }

    final testAlbumGrid = Platform.environment['HOMECANVAS_TEST_ALBUMGRID'];
    if (testAlbumGrid != null && testAlbumGrid.isNotEmpty) {
      return AlbumScreen(
        album: Album(
          id: testAlbumGrid,
          name: Platform.environment['HOMECANVAS_TEST_ALBUMNAME'] ?? 'Album',
          assetCount: 0,
        ),
      );
    }
    if ((Platform.environment['HOMECANVAS_TEST_ABOUT'] ?? '').isNotEmpty) {
      return const AboutScreen();
    }
    if ((Platform.environment['HOMECANVAS_TEST_SETTINGS'] ?? '').isNotEmpty) {
      return const SettingsScreen();
    }
    final testDashboard = Platform.environment['HOMECANVAS_TEST_DASHBOARD'];
    if (testDashboard != null && testDashboard.isNotEmpty) {
      return DashboardScreen(initialPage: int.tryParse(testDashboard) ?? 0);
    }
    if ((Platform.environment['HOMECANVAS_TEST_NOWPLAYING'] ?? '').isNotEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF101828),
        body: Stack(children: [NowPlayingOverlay()]),
      );
    }
    final testLocked = Platform.environment['HOMECANVAS_TEST_LOCKED'];
    if (testLocked != null && testLocked.isNotEmpty) {
      return _DebugLockedLoader(pin: testLocked);
    }
    final testLockedVideo =
        Platform.environment['HOMECANVAS_TEST_LOCKED_VIDEO'];
    if (testLockedVideo != null && testLockedVideo.isNotEmpty) {
      return _DebugLockedVideoLoader(pin: testLockedVideo);
    }

    final configured = context.watch<ConfigService>().isConfigured;
    return configured ? const HomeScreen() : const SetupScreen();
  }
}

/// Dev-only: unlock the Locked Folder with a PIN from the environment and show
/// it, to verify the Bearer-auth media path headlessly.
class _DebugLockedLoader extends StatefulWidget {
  final String pin;
  const _DebugLockedLoader({required this.pin});

  @override
  State<_DebugLockedLoader> createState() => _DebugLockedLoaderState();
}

class _DebugLockedLoaderState extends State<_DebugLockedLoader> {
  late final Future<UnlockResult> _future = context
      .read<LockedFolderService>()
      .unlock(widget.pin);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UnlockResult>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == UnlockResult.success) {
          return const LockedFolderScreen();
        }
        return Scaffold(body: Center(child: Text('unlock: ${snap.data}')));
      },
    );
  }
}

/// Dev-only: unlock + play the first locked video via media_kit, to reproduce
/// the in-app Locked Folder video path headlessly.
class _DebugLockedVideoLoader extends StatefulWidget {
  final String pin;
  const _DebugLockedVideoLoader({required this.pin});

  @override
  State<_DebugLockedVideoLoader> createState() =>
      _DebugLockedVideoLoaderState();
}

class _DebugLockedVideoLoaderState extends State<_DebugLockedVideoLoader> {
  late final LockedFolderService _locked = context.read<LockedFolderService>();
  Asset? _video;
  String _status = 'unlocking…';

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    final r = await _locked.unlock(widget.pin);
    if (!mounted) return;
    if (r != UnlockResult.success) {
      setState(() => _status = 'unlock failed: $r');
      return;
    }
    final assets = await _locked.getLockedAssets();
    if (!mounted) return;
    final v = assets
        .where((a) => a.isVideo)
        .cast<Asset?>()
        .firstWhere((a) => true, orElse: () => null);
    if (v == null) {
      setState(() => _status = 'no locked video found');
      return;
    }
    setState(() => _video = v);
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    if (v == null) {
      return Scaffold(body: Center(child: Text(_status)));
    }
    return VideoPlayerScreen(
      asset: v,
      source: _locked.mediaSource!,
      onBeforePlay: _locked.ensureElevated,
    );
  }
}

/// Dev-only: fetch an album's image assets, then hand them to [builder].
class _DebugAlbumLoader extends StatelessWidget {
  final String albumId;
  final ImmichService immich;
  final Widget Function(List<Asset> images) builder;
  const _DebugAlbumLoader({
    required this.albumId,
    required this.immich,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Asset>>(
      future: immich.getAlbumAssets(albumId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final imgs = snap.data!.where((a) => a.isImage).toList();
        return builder(imgs);
      },
    );
  }
}
