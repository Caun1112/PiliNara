import 'package:PiliPlus/common/widgets/global_back_button.dart';
import 'package:material_ui/material_ui.dart';

class HuyaPageRoute<T> extends MaterialPageRoute<T>
    implements GlobalBackButtonRoute {
  HuyaPageRoute({
    required super.builder,
    this.showGlobalBackButton = false,
  });

  @override
  final bool showGlobalBackButton;
}

Future<T?> openHuyaPage<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool showGlobalBackButton = false,
}) {
  return Navigator.of(context).push(
    HuyaPageRoute<T>(
      builder: builder,
      showGlobalBackButton: showGlobalBackButton,
    ),
  );
}
