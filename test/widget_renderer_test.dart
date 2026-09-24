import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_homescreen_widget/flutter_homescreen_widget.dart';
import 'package:flutter_homescreen_widget/src/widget_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fails immediately when the host is not mounted', (tester) async {
    expect(
      () => WidgetRenderer.render(
        widget: const SizedBox(),
        size: const Size(20, 20),
        pixelRatio: 1,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('FlutterHomescreenWidgetHost is not mounted'),
        ),
      ),
    );

    expect(
      () => FlutterHomescreenWidget.update(
        widgetName: 'Widget',
        content: const SizedBox(),
        size: const Size(20, 20),
      ),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('renders through the host without a navigator key', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        builder: FlutterHomescreenWidget.builder,
        home: SizedBox.shrink(),
      ),
    );

    final renderFuture = WidgetRenderer.render(
      widget: const ColoredBox(color: Colors.blue),
      size: const Size(20, 20),
      pixelRatio: 1,
    );

    final bytes = await tester.runAsync(() => renderFuture);

    expect(bytes, isNotEmpty);
  });

  testWidgets('captures inherited theme, media, and directionality', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(primaryColor: Colors.purple),
        builder: (context, child) {
          return MediaQuery(
            data: const MediaQueryData(boldText: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: FlutterHomescreenWidgetHost(child: child!),
            ),
          );
        },
        home: const SizedBox.shrink(),
      ),
    );

    var sawTheme = false;
    var sawMediaQuery = false;
    var sawDirectionality = false;
    final bytes = await tester.runAsync(
      () => WidgetRenderer.render(
        widget: Builder(
          builder: (context) {
            sawTheme = Theme.of(context).primaryColor == Colors.purple;
            sawMediaQuery = MediaQuery.of(context).boldText;
            sawDirectionality = Directionality.of(context) == TextDirection.rtl;
            return const SizedBox.expand();
          },
        ),
        size: const Size(20, 20),
        pixelRatio: 1,
      ),
    );

    expect(bytes, isNotEmpty);
    expect(sawTheme, isTrue);
    expect(sawMediaQuery, isTrue);
    expect(sawDirectionality, isTrue);
  });

  testWidgets('preserves size and pixel ratio in the captured image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        builder: FlutterHomescreenWidget.builder,
        home: SizedBox.shrink(),
      ),
    );

    final bytes = (await tester.runAsync(
      () => WidgetRenderer.render(
        widget: const ColoredBox(color: Colors.blue),
        size: const Size(20, 10),
        pixelRatio: 2,
      ),
    ))!;
    final dimensions = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final result = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return result;
    });

    expect(dimensions, (40, 20));
  });

  testWidgets('renders when requested by a child during mount', (tester) async {
    final renderKey = GlobalKey<_RenderOnMountState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: FlutterHomescreenWidget.builder,
        home: _RenderOnMount(key: renderKey),
      ),
    );
    await tester.pump();

    final bytes = await tester.runAsync(
      () => renderKey.currentState!.renderFuture,
    );

    expect(bytes, isNotEmpty);
  });

  testWidgets('keeps the deprecated init entry point source-compatible', (
    tester,
  ) async {
    WidgetRenderer.init(GlobalKey<NavigatorState>());

    expect(
      () => WidgetRenderer.render(
        widget: const SizedBox(),
        size: const Size(20, 20),
        pixelRatio: 1,
      ),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('removes the render target after capture', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        builder: FlutterHomescreenWidget.builder,
        home: SizedBox.shrink(),
      ),
    );

    var disposed = false;
    final renderFuture = WidgetRenderer.render(
      widget: _DisposeTracker(onDispose: () => disposed = true),
      size: const Size(20, 20),
      pixelRatio: 1,
    );

    await tester.pump();
    expect(await tester.runAsync(() => renderFuture), isNotEmpty);
    await tester.pump();

    expect(disposed, isTrue);
  });

  testWidgets('serializes concurrent renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        builder: FlutterHomescreenWidget.builder,
        home: SizedBox.shrink(),
      ),
    );

    var firstDisposed = false;
    var secondDisposed = false;
    final first = WidgetRenderer.render(
      widget: _DisposeTracker(onDispose: () => firstDisposed = true),
      size: const Size(20, 20),
      pixelRatio: 1,
    );
    final second = WidgetRenderer.render(
      widget: _DisposeTracker(onDispose: () => secondDisposed = true),
      size: const Size(20, 20),
      pixelRatio: 1,
    );

    await tester.pump();
    expect(await tester.runAsync(() => first), isNotEmpty);
    await tester.pump();
    expect(await tester.runAsync(() => second), isNotEmpty);
    await tester.pump();

    expect(firstDisposed, isTrue);
    expect(secondDisposed, isTrue);
  });

  testWidgets('fails safely when the host is disposed during rendering', (
    tester,
  ) async {
    final hostKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          return FlutterHomescreenWidgetHost(key: hostKey, child: child!);
        },
        home: const SizedBox.shrink(),
      ),
    );

    final renderFuture = WidgetRenderer.render(
      widget: const SizedBox(),
      size: const Size(20, 20),
      pixelRatio: 1,
    );
    await tester.pumpWidget(const SizedBox.shrink());

    await expectLater(renderFuture, throwsA(isA<StateError>()));
  });
}

class _DisposeTracker extends StatefulWidget {
  const _DisposeTracker({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeTracker> createState() => _DisposeTrackerState();
}

class _RenderOnMount extends StatefulWidget {
  const _RenderOnMount({super.key});

  @override
  State<_RenderOnMount> createState() => _RenderOnMountState();
}

class _RenderOnMountState extends State<_RenderOnMount> {
  late final Future<Uint8List> renderFuture;

  @override
  void initState() {
    super.initState();
    renderFuture = WidgetRenderer.render(
      widget: const ColoredBox(color: Colors.green),
      size: const Size(20, 20),
      pixelRatio: 1,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DisposeTrackerState extends State<_DisposeTracker> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
