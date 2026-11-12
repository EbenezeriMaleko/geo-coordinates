import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_page_style.dart';
import 'workspace_provider.dart';

typedef JobLinkQuery = ({
  bool project,
  bool team,
  String status,
  int company,
  String search,
  int page,
});

final jobLinkOptionsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, JobLinkQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId != query.company ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Workspace changed. Reopen the selector.');
      }
      final response = await ApiClient.getJson(
        query.team
            ? '/organization/teams'
            : query.project
            ? '/organization/projects'
            : '/lands',
        bearerToken: session.token,
        queryParameters: {
          'search': query.search,
          'page': query.page,
          if (query.project || query.team) 'status': query.status,
        },
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to load choices. Check access and retry.');
      }
      final body = jsonDecode(response.body) as Map;
      final items = query.project || query.team
          ? (body['data'] as Map)['items'] as Map
          : {'data': body['data'], ...body['meta'] as Map};
      return Map<String, dynamic>.from(items);
    });

class FieldJobLinkPicker extends ConsumerStatefulWidget {
  const FieldJobLinkPicker({
    super.key,
    required this.company,
    required this.project,
    this.team = false,
    this.includeArchived = false,
  });
  final int company;
  final bool project;
  final bool team;
  final bool includeArchived;

  @override
  ConsumerState<FieldJobLinkPicker> createState() => _FieldJobLinkPickerState();
}

class _FieldJobLinkPickerState extends ConsumerState<FieldJobLinkPicker> {
  String search = '';
  int page = 1;
  Timer? debounce;

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final available =
        workspace.activeCompanyId == widget.company && !workspace.isLoading;
    final query = (
      project: widget.project,
      team: widget.team,
      status: widget.includeArchived ? 'all' : 'active',
      company: widget.company,
      search: search,
      page: page,
    );
    final options = available ? ref.watch(jobLinkOptionsProvider(query)) : null;
    return WorkspaceScaffold(
      company: true,
      appBar: AppBar(
        title: Text(
          widget.team
              ? 'Select team'
              : widget.project
              ? 'Select project'
              : 'Select record',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                enabled: available,
                decoration: InputDecoration(
                  hintText: widget.team
                      ? 'Search teams'
                      : widget.project
                      ? 'Search projects'
                      : 'Search records',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 350), () {
                    if (mounted) {
                      setState(() {
                        search = value.trim();
                        page = 1;
                      });
                    }
                  });
                },
              ),
            ),
            Expanded(
              child: options == null
                  ? const Center(
                      child: Text('Workspace changed. Reopen the selector.'),
                    )
                  : options.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(jobLinkOptionsProvider(query)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Unable to load choices. Retry'),
                        ),
                      ),
                      data: (data) {
                        final items = (data['data'] as List? ?? [])
                            .whereType<Map>()
                            .toList();
                        final last = (data['last_page'] as num?)?.toInt() ?? 1;
                        return Column(
                          children: [
                            Expanded(
                              child: items.isEmpty
                                  ? const Center(
                                      child: Text('No matching items.'),
                                    )
                                  : ListView.builder(
                                      itemCount: items.length,
                                      itemBuilder: (context, index) {
                                        final item = items[index];
                                        return ListTile(
                                          leading: Icon(
                                            widget.team
                                                ? Icons.groups_outlined
                                                : widget.project
                                                ? Icons.folder_outlined
                                                : Icons.map_outlined,
                                          ),
                                          title: Text(
                                            item['name']?.toString() ??
                                                'Unnamed',
                                          ),
                                          subtitle: item['archived_at'] != null
                                              ? const Text('Archived')
                                              : null,
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                          ),
                                          onTap: () {
                                            if (ref
                                                    .read(workspaceProvider)
                                                    .activeCompanyId !=
                                                widget.company) {
                                              return;
                                            }
                                            Navigator.pop(
                                              context,
                                              Map<String, dynamic>.from(item),
                                            );
                                          },
                                        );
                                      },
                                    ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous page',
                                  onPressed: page > 1
                                      ? () => setState(() => page--)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Flexible(child: Text('Page $page of $last')),
                                IconButton(
                                  tooltip: 'Next page',
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
            ),
          ],
        ),
      ),
    );
  }
}
