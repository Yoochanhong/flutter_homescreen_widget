import 'package:flutter/widgets.dart';

import 'widget_renderer.dart';

/// Installs the package-owned rendering surface around an application child.
///
/// This widget is intended to be used by [FlutterHomescreenWidget.builder].
/// It is kept separate from the public API so the rendering lifecycle remains
/// internal to the package.
class FlutterHomescreenWidgetSurface extends StatefulWidget {
  const FlutterHomescreenWidgetSurface({super.key, required this.child});

  final Widget child;

  @override
  State<FlutterHomescreenWidgetSurface> createState() =>
      _FlutterHomescreenWidgetSurfaceState();
}

class _FlutterHomescreenWidgetSurfaceState
    extends State<FlutterHomescreenWidgetSurface> {
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
