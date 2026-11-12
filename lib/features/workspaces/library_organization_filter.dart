import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'field_job_link_picker.dart';

class LibraryOrganizationFilter {
  const LibraryOrganizationFilter({
    this.project,
    this.projectName,
    this.team,
    this.teamName,
  });
  final int? project;
  final String? projectName;
  final int? team;
  final String? teamName;
  bool get active => project != null || team != null;
}

class LibraryOrganizationFilterNotifier
    extends Notifier<LibraryOrganizationFilter> {
  @override
  LibraryOrganizationFilter build() {
    ref.watch(workspaceProvider.select((s) => s.activeCompanyId));
    ref.watch(authSessionProvider.select((s) => s.token));
    return const LibraryOrganizationFilter();
  }

  void select({required bool team, int? id, String? name}) {
    state = LibraryOrganizationFilter(
      project: team ? state.project : id,
      projectName: team ? state.projectName : name,
      team: team ? id : state.team,
      teamName: team ? name : state.teamName,
    );
  }
}

final libraryOrganizationFilterProvider =
    NotifierProvider<
      LibraryOrganizationFilterNotifier,
      LibraryOrganizationFilter
    >(LibraryOrganizationFilterNotifier.new);

class LibraryOrganizationFilters extends ConsumerWidget {
  const LibraryOrganizationFilters({super.key});

  Future<void> choose(BuildContext context, WidgetRef ref, bool team) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    if (company == null) return;
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => FieldJobLinkPicker(
          company: company,
          project: !team,
          team: team,
          includeArchived: true,
        ),
      ),
    );
    if (!context.mounted ||
        selected == null ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final id = int.tryParse(selected['id'].toString());
    if (id == null) return;
    ref
        .read(libraryOrganizationFilterProvider.notifier)
        .select(team: team, id: id, name: selected['name']?.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryOrganizationFilterProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final team in [false, true])
                InputChip(
                  avatar: Icon(
                    team ? Icons.groups_outlined : Icons.folder_outlined,
                    size: 18,
                  ),
                  label: Text(
                    (team ? filter.teamName : filter.projectName) ??
                        (team ? 'All teams' : 'All projects'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => choose(context, ref, team),
                  onDeleted: (team ? filter.team : filter.project) == null
                      ? null
                      : () => ref
                            .read(libraryOrganizationFilterProvider.notifier)
                            .select(team: team),
                ),
            ],
          ),
          if (filter.active)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Cloud records only. Clear filters to see pending local records.',
                style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
              ),
            ),
        ],
      ),
    );
  }
}
