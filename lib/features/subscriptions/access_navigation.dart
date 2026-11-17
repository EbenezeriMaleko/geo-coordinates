import 'package:flutter/material.dart';

import '../auth/models/auth_models.dart';
import '../auth/ui/login_page.dart';
import 'plans_access_page.dart';

/// Return to the feature after signing in; do not silently retry its action.
Future<void> openAccessRequirement(
  BuildContext context,
  AuthSession session,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<Object?>(
      builder: (_) => session.isLoggedIn
          ? const PlansAccessPage()
          : const LoginPage(returnToPreviousPage: true),
    ),
  );
}
