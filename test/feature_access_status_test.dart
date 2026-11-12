import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/subscriptions/feature_access_section.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';

void main() {
  test('server availability and company access are not reported as paid locks', () {
    expect(FeatureAccessSection.status(const FeatureDecision(allowed: true, name: 'Map')), 'Available');
    expect(FeatureAccessSection.status(const FeatureDecision(allowed: false, name: 'Map', reason: 'subscription_required')), 'Plan access required');
    expect(FeatureAccessSection.status(const FeatureDecision(allowed: false, name: 'Jobs', reason: 'feature_unavailable')), 'Not available yet');
    expect(FeatureAccessSection.status(const FeatureDecision(allowed: false, name: 'Jobs', reason: 'company_workspace_required')), 'Company workspace required');
    expect(FeatureAccessSection.status(const FeatureDecision(allowed: false, name: 'Jobs', reason: 'company_subscription_expired')), 'Company plan ended');
  });
}
