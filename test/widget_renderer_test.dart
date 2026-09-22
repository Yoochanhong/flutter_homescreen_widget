import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_homescreen_widget/src/widget_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('waits for the overlay and first frame before rendering', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    WidgetRenderer.init(navigatorKey);

    final renderFuture = WidgetRenderer.render(
      widget: const ColoredBox(color: Colors.blue),
      size: const Size(20, 20),
      pixelRatio: 1,
    );
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );
    await tester.pump();
    await tester.pump();

    final bytes = await tester.runAsync(() => renderFuture);
    expect(bytes, isNotEmpty);
  });

  testWidgets('removes the overlay entry after capture', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    WidgetRenderer.init(navigatorKey);
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
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
}

class _DisposeTracker extends StatefulWidget {
  const _DisposeTracker({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeTracker> createState() => _DisposeTrackerState();
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
