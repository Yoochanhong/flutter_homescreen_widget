import 'package:flutter/widgets.dart';

import 'widget_renderer.dart';

/// Owns the rendering surface used by [FlutterHomescreenWidget].
///
/// Place this widget above the application widget once. The application does
/// not need to expose a [NavigatorState] key to the package.
///
/// ```dart
/// void main() {
///   runApp(
///     const FlutterHomescreenWidgetHost(
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
class FlutterHomescreenWidgetHost extends StatefulWidget {
  const FlutterHomescreenWidgetHost({super.key, required this.child});

  /// The application widget rendered alongside the package-owned surface.
  final Widget child;

  @override
  State<FlutterHomescreenWidgetHost> createState() =>
      _FlutterHomescreenWidgetHostState();
}

class _FlutterHomescreenWidgetHostState
    extends State<FlutterHomescreenWidgetHost> {
  final _overlayKey = GlobalKey<OverlayState>();

  @override
  void initState() {
    super.initState();
    WidgetRenderer.registerHost(_overlayKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WidgetRenderer.markHostReady(_overlayKey);
      }
    });
  }

  @override
  void dispose() {
    WidgetRenderer.unregisterHost(_overlayKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        Directionality(
          textDirection: TextDirection.ltr,
          child: IgnorePointer(child: Overlay(key: _overlayKey)),
        ),
      ],
    );
  }
}
