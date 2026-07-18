import 'package:flutter/widgets.dart';

/// Material icon from a stored [codePoint] (e.g. dashboard config).
IconData materialIcon(int codePoint) {
  // IconData has a const constructor; runtime code points are valid here.
  // ignore: non_const_argument_for_const_parameter
  return IconData(codePoint, fontFamily: 'MaterialIcons');
}
