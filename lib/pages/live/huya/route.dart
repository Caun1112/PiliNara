import 'package:PiliPlus/common/widgets/global_back_button.dart';
import 'package:material_ui/material_ui.dart';

class HuyaPageRoute<T> extends MaterialPageRoute<T>
    implements GlobalBackButtonRoute {
  HuyaPageRoute({required super.builder});

  @override
  bool get showGlobalBackButton => false;
}

Future<T?> openHuyaPage<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return Navigator.of(context).push(HuyaPageRoute<T>(builder: builder));
}
