import '../../services/floatplane_site.dart';
import '../../services/nebula_site.dart';
import 'feed_tile.dart';

/// The latest videos from the creators the Floatplane account subscribes to.
final floatplaneWidgetType = siteFeedWidgetType<FloatplaneSite>(
  type: 'floatplane',
  name: 'Floatplane',
  description:
      'The latest videos from the creators you subscribe to on Floatplane. '
      'Touch one to watch it on the panel.',
  glyph: '🎞️',
);

/// The latest videos from the creators the Nebula account follows — in HEVC,
/// decoded by the Pi's hardware, where it is 30 frames a second or fewer.
final nebulaWidgetType = siteFeedWidgetType<NebulaSite>(
  type: 'nebula',
  name: 'Nebula',
  description:
      'The latest videos from the creators you follow on Nebula. Touch one '
      'to watch it on the panel.',
  glyph: '🌌',
);
