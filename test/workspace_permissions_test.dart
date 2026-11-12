import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';

void main() {
  test('workspace permissions require explicit boolean grants', () {
    expect(parseWorkspacePermissions(null), isEmpty);
    expect(parseWorkspacePermissions(['jobs.manage']), isEmpty);
    final permissions = parseWorkspacePermissions({
      'jobs.manage': true,
      'jobs.progress': false,
      'records.write': 'true',
      'jobs.review': 1,
      'jobs.submit': null,
    });
    expect(permissions['jobs.manage'], isTrue);
    expect(permissions['jobs.progress'], isFalse);
    expect(permissions['records.write'], isFalse);
    expect(permissions['jobs.review'], isFalse);
    expect(permissions['jobs.submit'], isFalse);
  });
}
