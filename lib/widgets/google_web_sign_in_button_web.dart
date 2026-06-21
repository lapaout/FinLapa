import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

Widget buildGoogleWebSignInButton() {
  return Center(
    child: web.renderButton(
      configuration: web.GSIButtonConfiguration(
        size: web.GSIButtonSize.large,
        theme: web.GSIButtonTheme.filledBlue,
        text: web.GSIButtonText.signinWith,
        minimumWidth: 352,
        locale: 'uk',
      ),
    ),
  );
}
