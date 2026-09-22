import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders a Flutter widget tree to a PNG [Uint8List].
///
/// Inserts the widget into the live overlay (off-screen) so that fonts,
/// images, and platform views are all available during capture.
class WidgetRenderer {
  WidgetRenderer._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Registers the app's [NavigatorState] key so the renderer can access
  /// the [Overlay]. Must be called once before [render].
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
  /// Throws [StateError] if [init] has not been called first.
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
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          throw StateError('The rendered widget did not produce image data.');
        }
        return byteData.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      if (inserted) {
        try {
          entry.remove();
        } finally {
          entry.dispose();
        }
      }
    }
  }

  static Future<OverlayState> _waitForOverlay() async {
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
