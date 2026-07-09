import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Drag source that adapts to how the platform is driven. Touch platforms
/// (Android/iOS, including mobile browsers) keep [LongPressDraggable] so a
/// drag doesn't compete with list scrolling; mouse-driven platforms (desktop
/// builds and desktop web, e.g. Chrome on a laptop) get an immediate
/// [Draggable] because click-and-hold before dragging is unnatural with a
/// mouse.
class AdaptiveDraggable<T extends Object> extends StatelessWidget {
  final T data;
  final Widget feedback;
  final Widget? childWhenDragging;
  final Widget child;

  const AdaptiveDraggable({
    Key? key,
    required this.data,
    required this.feedback,
    this.childWhenDragging,
    required this.child,
  }) : super(key: key);

  /// Whether the current platform is primarily touch-driven. On web,
  /// [defaultTargetPlatform] reflects the underlying OS, so Chrome on a
  /// laptop counts as mouse-driven while Chrome on a phone stays touch.
  static bool get isTouchPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isTouchPlatform) {
      return LongPressDraggable<T>(
        data: data,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }
    return Draggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
}
