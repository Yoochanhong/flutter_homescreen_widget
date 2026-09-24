import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders a Flutter widget tree to a PNG [Uint8List].
///
/// Rendering is available only while [FlutterHomescreenWidgetHost] is mounted.
/// The host provides the app context used to copy inherited themes and view
/// configuration into an independent offscreen render tree.
class WidgetRenderer {
  WidgetRenderer._();

  static _FlutterHomescreenWidgetHostState? _host;

  static Widget buildHost(Widget child) {
    return FlutterHomescreenWidgetHost(child: child);
  }

  static void _attach(_FlutterHomescreenWidgetHostState host) {
    _host = host;
  }

  static void _detach(_FlutterHomescreenWidgetHostState host) {
    if (identical(_host, host)) {
      _host = null;
    }
  }

  /// Keeps the old entry point source-compatible during migration.
  ///
  /// The key is intentionally no longer used. Applications must install
  /// [FlutterHomescreenWidgetHost] through [FlutterHomescreenWidget.builder]
  /// (or directly in `MaterialApp.builder`) before calling [render].
  static void init(GlobalKey<NavigatorState> navigatorKey) {}

  /// Renders [widget] at [size] logical pixels and returns a PNG byte array.
  ///
  /// [pixelRatio] controls the output resolution (default 3.0 for @3x).
  /// Throws [StateError] immediately when the host is not mounted.
  static Future<Uint8List> render({
    required Widget widget,
    required Size size,
    double pixelRatio = 3.0,
  }) {
    ensureHostMounted();
    return _host!.render(widget: widget, size: size, pixelRatio: pixelRatio);
  }

  static void ensureHostMounted() {
    final host = _host;
    if (host == null || !host.mounted) {
      throw _hostNotMountedError();
    }
  }

  static StateError hostNotMountedError() => _hostNotMountedError();

  static StateError _hostNotMountedError() {
    return StateError(
      'FlutterHomescreenWidgetHost is not mounted. '
      'Register it in MaterialApp.builder before calling update().',
    );
  }

  static Future<Uint8List> _renderOffscreen({
    required BuildContext context,
    required Widget widget,
    required Size size,
    required double pixelRatio,
  }) async {
    final logicalConstraints = BoxConstraints.tight(size);
    final pipelineOwner = PipelineOwner();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: View.of(context),
      configuration: ViewConfiguration(
        logicalConstraints: logicalConstraints,
        physicalConstraints: logicalConstraints * pixelRatio,
        devicePixelRatio: pixelRatio,
      ),
      child: repaintBoundary,
    );

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildErrors = <FlutterErrorDetails>[];

    T collectBuildErrors<T>(T Function() callback) {
      final previousOnError = FlutterError.onError;
      FlutterError.onError = buildErrors.add;
      try {
        return callback();
      } finally {
        FlutterError.onError = previousOnError;
      }
    }

    void throwFirstBuildError() {
      if (buildErrors.isEmpty) {
        return;
      }

      final error = buildErrors.first;
      Error.throwWithStackTrace(
        error.exception,
        error.stack ?? StackTrace.current,
      );
    }

    final content = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: MediaQuery.maybeOf(context) ?? const MediaQueryData(),
        child: Directionality(
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(
              decoration: TextDecoration.none,
              color: Color(0xFFFFFFFF),
            ),
            child: widget,
          ),
        ),
      ),
    );

    RenderObjectToWidgetElement<RenderBox>? rootElement;

    try {
      rootElement = collectBuildErrors(
        () => RenderObjectToWidgetAdapter<RenderBox>(
          container: repaintBoundary,
          child: content,
        ).attachToRenderTree(buildOwner),
      );
      throwFirstBuildError();
      buildOwner.finalizeTree();

      collectBuildErrors(pipelineOwner.flushLayout);
      throwFirstBuildError();
      pipelineOwner
        ..flushCompositingBits()
        ..flushPaint();

      final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
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
      try {
        if (rootElement != null) {
          // Update the root adapter to remove the content and dispose its
          // Element tree before releasing the render tree and its BuildOwner.
          final detachedRoot = RenderObjectToWidgetAdapter<RenderBox>(
            container: repaintBoundary,
          ).attachToRenderTree(buildOwner, rootElement);
          buildOwner.buildScope(detachedRoot);
          buildOwner.finalizeTree();
        }
      } finally {
        pipelineOwner.rootNode = null;
      }
    }
  }
}

/// Registers the rendering context while it is mounted in the app tree.
///
/// The widget itself renders [child] unchanged. Actual captures are built in a
/// separate render tree owned by [WidgetRenderer].
class FlutterHomescreenWidgetHost extends StatefulWidget {
  const FlutterHomescreenWidgetHost({super.key, required this.child});

  final Widget child;

  @override
  State<FlutterHomescreenWidgetHost> createState() =>
      _FlutterHomescreenWidgetHostState();
}

class _FlutterHomescreenWidgetHostState
    extends State<FlutterHomescreenWidgetHost> {
  Future<void> _renderQueue = Future<void>.value();
  final _disposed = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetRenderer._attach(this);
  }

  @override
  void dispose() {
    WidgetRenderer._detach(this);
    if (!_disposed.isCompleted) {
      _disposed.complete();
    }
    super.dispose();
  }

  Future<Uint8List> render({
    required Widget widget,
    required Size size,
    required double pixelRatio,
  }) {
    if (!mounted) {
      throw WidgetRenderer.hostNotMountedError();
    }

    final result = _renderQueue.then<Uint8List>(
      (_) => _renderOne(widget: widget, size: size, pixelRatio: pixelRatio),
    );

    _renderQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    final disposed = _disposed.future.then<Uint8List>((_) {
      throw WidgetRenderer.hostNotMountedError();
    });
    disposed.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    final completion = Future.any<Uint8List>([result, disposed]);
    completion.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return completion;
  }

  Future<Uint8List> _renderOne({
    required Widget widget,
    required Size size,
    required double pixelRatio,
  }) async {
    if (!mounted) {
      throw WidgetRenderer.hostNotMountedError();
    }

    final bytes = await WidgetRenderer._renderOffscreen(
      context: context,
      widget: widget,
      size: size,
      pixelRatio: pixelRatio,
    );

    if (!mounted) {
      throw WidgetRenderer.hostNotMountedError();
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
