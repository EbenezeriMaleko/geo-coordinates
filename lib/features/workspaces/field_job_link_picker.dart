import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_page_style.dart';
import 'workspace_provider.dart';

const Color _accent = Color(0xFF245B83); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _greySoft = Color(0xFFF1F3F5);

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

  // ── UI helpers ────────────────────────────────────────────────

  dynamic get _icon => widget.team
      ? HugeIcons.strokeRoundedUserGroup
      : widget.project
      ? HugeIcons.strokeRoundedFolder01
      : HugeIcons.strokeRoundedLocation01;

  String get _noun => widget.team
      ? 'teams'
      : widget.project
      ? 'projects'
      : 'records';

  Widget _itemCard(Map item, int company) {
    final archived = item['archived_at'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (ref.read(workspaceProvider).activeCompanyId != company) {
              return;
            }
            Navigator.pop(context, Map<String, dynamic>.from(item));
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: archived ? 0.05 : 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: _icon,
                    color: archived ? Colors.black38 : _accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name']?.toString() ?? 'Unnamed',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: archived ? Colors.black54 : Colors.black87,
                        ),
                      ),
                      if (archived) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _greySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Archived',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: Colors.black26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: HugeIcon(
            icon: search.isNotEmpty ? HugeIcons.strokeRoundedSearch01 : _icon,
            color: _accent,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No matching items',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    ),
  );

  Widget _pager(int last) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: page > 1 ? () => setState(() => page--) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              Flexible(
                child: Text(
                  'Page $page of $last',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: page < last ? () => setState(() => page++) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final baseTheme = Theme.of(context);
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

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: Text(
            widget.team
                ? 'Select team'
                : widget.project
                ? 'Select project'
                : 'Select record',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: TextField(
                    enabled: available,
                    decoration: InputDecoration(
                      hintText: 'Search $_noun',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: Colors.black45,
                      ),
                      filled: true,
                      fillColor: _fieldFill,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(14),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedSearch01,
                          color: Colors.black45,
                          size: 20,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _cardBorder),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: _accent,
                          width: 1.6,
                        ),
                      ),
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
                const Divider(height: 1, color: _cardBorder),
                Expanded(
                  child: options == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedShield01,
                                  color: Colors.black26,
                                  size: 40,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Workspace changed. Reopen the selector.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : options.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, _) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HugeIcon(
                                    icon: HugeIcons.strokeRoundedWifiOff01,
                                    color: Colors.black26,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Unable to load choices',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                    onPressed: () => ref.invalidate(
                                      jobLinkOptionsProvider(query),
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          data: (data) {
                            final items = (data['data'] as List? ?? [])
                                .whereType<Map>()
                                .toList();
                            final last =
                                (data['last_page'] as num?)?.toInt() ?? 1;
                            return Column(
                              children: [
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      24,
                                    ),
                                    children: [
                                      if (items.isEmpty)
                                        _emptyState()
                                      else
                                        for (final item in items)
                                          _itemCard(item, widget.company),
                                    ],
                                  ),
                                ),
                                if (last > 1) _pager(last),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}