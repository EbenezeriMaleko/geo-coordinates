import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

final memberSearchProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String search, int page})>((
      ref,
      query,
    ) async {
      ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      final response = await ApiClient.getJson(
        '/organization/member-options',
        bearerToken: session.token,
        queryParameters: {'search': query.search, 'page': query.page},
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to search company members.');
      }
      return Map<String, dynamic>.from(
        jsonDecode(response.body)['data'] as Map,
      );
    });

class TeamMemberPicker extends ConsumerStatefulWidget {
  const TeamMemberPicker({
    super.key,
    required this.team,
    required this.onAdded,
  });
  final int team;
  final VoidCallback onAdded;
  @override
  ConsumerState<TeamMemberPicker> createState() => _TeamMemberPickerState();
}

class _TeamMemberPickerState extends ConsumerState<TeamMemberPicker> {
  String search = '';
  int page = 1;
  bool busy = false;
  String? error;
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(workspaceProvider).activeCompanyId;
    final query = (search: search, page: page);
    final results = search.length >= 2
        ? ref.watch(memberSearchProvider(query))
        : null;
    return WorkspaceScaffold(
      company: true,
      appBar: AppBar(title: const Text('Add team member')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Company member',
                  hintText: 'Search name or email',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (value) => setState(() {
                  search = value.trim();
                  page = 1;
                }),
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
                textInputAction: TextInputAction.search,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: results == null
                  ? const Center(child: Text('No search results yet.'))
                  : results.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: TextButton(
                          onPressed: () =>
                              ref.invalidate(memberSearchProvider(query)),
                          child: const Text('Retry member search'),
                        ),
                      ),
                      data: (data) {
                        final members = (data['data'] as List)
                            .whereType<Map>()
                            .toList();
                        return Column(
                          children: [
                            Expanded(
                              child: members.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No matching company members.',
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: members.length,
                                      itemBuilder: (context, index) {
                                        final member = members[index];
                                        return ListTile(
                                          title: Text(
                                            member['name']?.toString() ?? '',
                                          ),
                                          subtitle: Text(
                                            member['email']?.toString() ?? '',
                                          ),
                                          trailing: IconButton(
                                            tooltip: 'Add member',
                                            icon: const Icon(
                                              Icons.person_add_outlined,
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      busy = true;
                                                      error = null;
                                                    });
                                                    try {
                                                      final token = ref
                                                          .read(
                                                            authSessionProvider,
                                                          )
                                                          .token;
                                                      if (company !=
                                                          ref
                                                              .read(
                                                                workspaceProvider,
                                                              )
                                                              .activeCompanyId) {
                                                        throw Exception(
                                                          'Workspace changed.',
                                                        );
                                                      }
                                                      final response =
                                                          await ApiClient.postJson(
                                                            '/organization/teams/${widget.team}/members',
                                                            bearerToken: token,
                                                            body: {
                                                              'membership_id':
                                                                  member['id'],
                                                            },
                                                          );
                                                      if (response.statusCode <
                                                              200 ||
                                                          response.statusCode >=
                                                              300) {
                                                        throw Exception(
                                                          'Unable to add this member. Check team access and retry.',
                                                        );
                                                      }
                                                      if (!mounted) return;
                                                      widget.onAdded();
                                                      Navigator.of(
                                                        this.context,
                                                      ).pop();
                                                    } catch (failure) {
                                                      if (mounted) {
                                                        setState(() {
                                                          busy = false;
                                                          error = failure
                                                              .toString()
                                                              .replaceFirst(
                                                                'Exception: ',
                                                                '',
                                                              );
                                                        });
                                                      }
                                                    }
                                                  },
                                          ),
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
                                Text('Page $page'),
                                IconButton(
                                  tooltip: 'Next page',
                                  onPressed:
                                      page <
                                          ((data['last_page'] as num?)
                                                  ?.toInt() ??
                                              1)
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
