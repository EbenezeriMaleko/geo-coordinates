import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../workspaces/workspace_provider.dart';

final subscriptionOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isLoggedIn || !session.isVerified) {
        throw Exception('Sign in with a verified account to view plan access.');
      }
      if (workspace.isLoading) {
        throw Exception('Workspaces are loading. Please refresh shortly.');
      }
      final response = await ApiClient.getJson(
        '/billing',
        bearerToken: session.token,
        queryParameters: workspace.activeCompanyId == null
            ? null
            : {'company_id': workspace.activeCompanyId},
        tag: 'subscription_overview',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Unable to load plan access. Please try again.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! Map) {
        throw Exception('The server returned an unexpected response.');
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      final company = data['company'];
      final responseCompanyId = company is Map
          ? int.tryParse('${company['id']}')
          : null;
      if (responseCompanyId != workspace.activeCompanyId) {
        throw Exception(
          'The server returned billing for another workspace. Refresh and try again.',
        );
      }
      return data;
    });
