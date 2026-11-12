import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';

typedef ReviewHistoryQuery = ({int company, int job, int page});

final reviewHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ReviewHistoryQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId != query.company ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Workspace changed. Reopen the review.');
      }
      final response = await ApiClient.getJson(
        '/field-jobs/${query.job}/review',
        bearerToken: session.token,
        queryParameters: {'history_page': query.page},
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to load review history.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['history'] is! Map) {
        throw Exception('Review history is unavailable on this server.');
      }
      return Map<String, dynamic>.from(body['history'] as Map);
    });

class JobReviewHistory extends ConsumerStatefulWidget {
  const JobReviewHistory({super.key, required this.company, required this.job});
  final int company;
  final int job;

  @override
  ConsumerState<JobReviewHistory> createState() => _JobReviewHistoryState();
}

class _JobReviewHistoryState extends ConsumerState<JobReviewHistory> {
  bool expanded = false;
  int page = 1;

  @override
  void didUpdateWidget(covariant JobReviewHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company != widget.company || oldWidget.job != widget.job) {
      page = 1;
    }
  }

  String actionLabel(String? action) => switch (action) {
    'submit' => 'Submitted for review',
    'approved' => 'Approved',
    'changes_requested' => 'Changes requested',
    'reopen' => 'Reopened for corrections',
    _ => 'Review updated',
  };

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final available =
        workspace.activeCompanyId == widget.company && !workspace.isLoading;
    final query = (company: widget.company, job: widget.job, page: page);
    final history = expanded && available
        ? ref.watch(reviewHistoryProvider(query))
        : null;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: const Text('Review history'),
      onExpansionChanged: (value) => setState(() => expanded = value),
      children: [
        if (!available)
          const Text('Workspace changed. Reopen the review.')
        else if (history != null)
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => TextButton.icon(
              onPressed: () => ref.invalidate(reviewHistoryProvider(query)),
              icon: const Icon(Icons.refresh),
              label: const Text('Unable to load history. Retry'),
            ),
            data: (data) {
              final events = (data['data'] as List? ?? []).whereType<Map>();
              final last = (data['last_page'] as num?)?.toInt() ?? 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No review history yet.'),
                    ),
                  for (final event in events) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actionLabel(event['action']?.toString()),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event['actor']?.toString() ?? 'Unavailable account',
                          ),
                          if (DateTime.tryParse(
                                event['created_at']?.toString() ?? '',
                              )
                              case final DateTime date)
                            Text(
                              '${MaterialLocalizations.of(context).formatMediumDate(date.toLocal())}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date.toLocal()))}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (event['note']?.toString().trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            Text(event['note'].toString()),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous history page',
                        onPressed: page > 1
                            ? () => setState(() => page--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Flexible(child: Text('Page $page of $last')),
                      IconButton(
                        tooltip: 'Next history page',
                        onPressed: page < last
                            ? () => setState(() => page++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
