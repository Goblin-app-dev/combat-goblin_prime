import 'package:flutter/widgets.dart';

import 'import_session_controller.dart';

/// InheritedNotifier for ImportSessionController.
///
/// Provides controller access throughout the widget tree without
/// external state management dependencies.
class ImportSessionProvider extends InheritedNotifier<ImportSessionController> {
  const ImportSessionProvider({
    super.key,
    required ImportSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static ImportSessionController of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ImportSessionProvider>();
    assert(
      provider != null,
      'No ImportSessionProvider found in context. '
      'Wrap your widget tree with ImportSessionProvider.',
    );
    return provider!.notifier!;
  }

  static ImportSessionController? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ImportSessionProvider>();
    return provider?.notifier;
  }
}
