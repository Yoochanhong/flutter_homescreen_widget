import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders a Flutter widget tree to a PNG [Uint8List].
///
/// The preferred rendering surface is registered by
/// [FlutterHomescreenWidget.builder]. A Navigator overlay is retained only as
/// a backwards-compatible fallback for callers using deprecated [init].
class WidgetRenderer {
  WidgetRenderer._();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static GlobalKey<OverlayState>? _surfaceOverlayKey;
  static Completer<OverlayState>? _surfaceReady;

  static const _surfaceReadyTimeout = Duration(seconds: 5);

  static Widget buildSurface(Widget child) {
    return _RenderingSurface(child: child);
  }

  /// Registers the package-owned rendering surface.
  static void registerSurface(GlobalKey<OverlayState> overlayKey) {
    _surfaceOverlayKey = overlayKey;
    _surfaceReady = Completer<OverlayState>();
  }

  /// Marks the package-owned rendering surface ready after it has mounted.
  static void markSurfaceReady(GlobalKey<OverlayState> overlayKey) {
    if (_surfaceOverlayKey != overlayKey) {
      return;
    }

    final overlay = overlayKey.currentState;
    if (overlay != null && !(_surfaceReady?.isCompleted ?? true)) {
      _surfaceReady!.complete(overlay);
    }
  }

  /// Fails requests still waiting when the rendering surface is removed.
  static void unregisterSurface(GlobalKey<OverlayState> overlayKey) {
    if (_surfaceOverlayKey != overlayKey) {
      return;
    }

    final ready = _surfaceReady;
    _surfaceOverlayKey = null;
    _surfaceReady = null;
    if (ready != null && !ready.isCompleted) {
      ready.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      ready.completeError(
        StateError(
          'The FlutterHomescreenWidget rendering surface was removed before '
          'rendering finished.',
        ),
      );
    }
  }

  /// Registers the app's [NavigatorState] key for legacy applications.
  ///
  /// Prefer installing [FlutterHomescreenWidget.builder].
  ///
  /// ```dart
  /// final _navKey = GlobalKey<NavigatorState>();
  ///
  /// void main() {
  ///   FlutterHomescreenWidget.init(_navKey);
  ///   runApp(MaterialApp(navigatorKey: _navKey, home: MyHome()));
  /// }
  /// ```
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  /// Renders [widget] at [size] logical pixels and returns a PNG byte array.
  ///
  /// [pixelRatio] controls the output resolution (default 3.0 for @3x).
  ///
  /// Throws [StateError] if no rendering surface is installed or initialized.
  static Future<Uint8List> render({
    required Widget widget,
    required Size size,
    double pixelRatio = 3.0,
  }) async {
    final overlay = await _waitForOverlay();
    final key = GlobalKey();

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -size.width * 2,
        top: 0,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: RepaintBoundary(
            key: key,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: DefaultTextStyle(
                style: const TextStyle(
                  decoration: TextDecoration.none,
                  color: Color(0xFFFFFFFF),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: widget,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    var inserted = false;
    try {
      overlay.insert(entry);
      inserted = true;
      await _waitForNextFrame();

      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('The widget could not be rendered for capture.');
      }

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      return _encodeImage(image);
    } finally {
      _disposeOverlayEntry(entry, inserted: inserted);
    }
  }

  static Future<Uint8List> _encodeImage(ui.Image image) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('The rendered widget did not produce image data.');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static void _disposeOverlayEntry(
    OverlayEntry entry, {
    required bool inserted,
  }) {
    if (!inserted) {
      return;
    }

    try {
      entry.remove();
    } finally {
      entry.dispose();
    }
  }

  static Future<OverlayState> _waitForOverlay() async {
    final surfaceOverlay = _surfaceOverlayKey?.currentState;
    if (surfaceOverlay != null) {
      return surfaceOverlay;
    }

    if (_surfaceOverlayKey != null) {
      final ready = _surfaceReady;
      if (ready == null) {
        throw StateError(
          'The FlutterHomescreenWidget rendering surface could not initialize.',
        );
      }

      try {
        return await ready.future.timeout(_surfaceReadyTimeout);
      } on TimeoutException {
        throw StateError(
          'The FlutterHomescreenWidget rendering surface did not become '
          'ready. Install FlutterHomescreenWidget.builder in the application '
          'before calling update().',
        );
      }
    }

    final navigatorKey = _navigatorKey;
    if (navigatorKey == null) {
      throw StateError(
        'FlutterHomescreenWidget.init() must be called with a valid NavigatorKey '
        'before rendering widgets.',
      );
    }

    final currentOverlay = navigatorKey.currentState?.overlay;
    if (currentOverlay != null) {
      return currentOverlay;
    }

    await _waitForNextFrame();

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      throw StateError(
        'The NavigatorKey is not attached to an app with an Overlay.',
      );
    }

    return overlay;
  }

  static Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return completer.future;
  }
}

class _RenderingSurface extends StatefulWidget {
  const _RenderingSurface({required this.child});

  final Widget child;

  @override
  State<_RenderingSurface> createState() => _RenderingSurfaceState();
}

class _RenderingSurfaceState extends State<_RenderingSurface> {
  final _overlayKey = GlobalKey<OverlayState>();

  @override
  void initState() {
    super.initState();
    WidgetRenderer.registerSurface(_overlayKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WidgetRenderer.markSurfaceReady(_overlayKey);
      }
    });
  }

  @override
  void dispose() {
    WidgetRenderer.unregisterSurface(_overlayKey);
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
