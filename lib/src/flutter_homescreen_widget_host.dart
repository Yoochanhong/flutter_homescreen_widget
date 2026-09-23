import 'package:flutter/widgets.dart';

import 'flutter_homescreen_widget_surface.dart';

/// Legacy wrapper for the package-owned rendering surface.
///
/// Prefer [FlutterHomescreenWidget.builder], which installs the surface inside
/// the application's inherited widget context.
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
@Deprecated('Use FlutterHomescreenWidget.builder instead.')
class FlutterHomescreenWidgetHost extends StatelessWidget {
  const FlutterHomescreenWidgetHost({super.key, required this.child});

  /// The application widget rendered alongside the package-owned surface.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FlutterHomescreenWidgetSurface(child: child);
  }
}
