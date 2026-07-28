import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

const double _floatingBackButtonVerticalRatio = 0.55;
const double _floatingBackButtonSize = 56;

double calculateFloatingBackButtonBottom({
  required double height,
  required double safeTop,
  required double safeBottom,
}) {
  final minVisibleBottom = safeBottom + kFloatingActionButtonMargin;
  final maxVisibleBottom = max(
    minVisibleBottom,
    height - safeTop - kFloatingActionButtonMargin - _floatingBackButtonSize,
  );
  final desiredBottom =
      height * (1 - _floatingBackButtonVerticalRatio) -
      _floatingBackButtonSize / 2;
  return desiredBottom.clamp(minVisibleBottom, maxVisibleBottom);
}

abstract interface class GlobalBackButtonRoute {
  bool get showGlobalBackButton;
}

class GlobalBackButtonObserver extends NavigatorObserver {
  final canPop = ValueNotifier<bool>(false);
  final routeRevision = ValueNotifier<int>(0);
  Route<dynamic>? _topRoute;

  bool get shouldShow {
    final route = _topRoute;
    if (route == null) return false;

    final routeName = route.settings.name ?? Get.currentRoute;
    if (routeName.startsWith('/videoV')) return false;
    if (route is GlobalBackButtonRoute) {
      return (route as GlobalBackButtonRoute).showGlobalBackButton;
    }
    return route is! PopupRoute;
  }

  void _sync() {
    canPop.value = navigator?.canPop() ?? false;
    routeRevision.value++;
  }

  @override
  void didChangeTop(
    Route<dynamic> topRoute,
    Route<dynamic>? previousTopRoute,
  ) {
    super.didChangeTop(topRoute, previousTopRoute);
    _topRoute = topRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }
}

class GlobalBackButtonOverlay extends StatelessWidget {
  const GlobalBackButtonOverlay({
    super.key,
    required this.child,
    required this.observer,
    required this.onBack,
  });

  final Widget child;
  final GlobalBackButtonObserver observer;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: observer.routeRevision,
      builder: (context, _, child) {
        if (!observer.canPop.value || !observer.shouldShow) {
          return child!;
        }

        final padding = MediaQuery.viewPaddingOf(context);
        final height = MediaQuery.sizeOf(context).height;
        return Stack(
          children: [
            child!,
            Positioned(
              right: padding.right + kFloatingActionButtonMargin,
              bottom: calculateFloatingBackButtonBottom(
                height: height,
                safeTop: padding.top,
                safeBottom: padding.bottom,
              ),
              child: FloatingActionButton(
                heroTag: 'global-back-button',
                tooltip: '返回',
                onPressed: onBack,
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
