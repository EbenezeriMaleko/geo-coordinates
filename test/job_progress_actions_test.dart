import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/workspaces/job_progress_actions.dart';

void main() {
  test(
    'assigned members can progress but cannot cancel or edit closed jobs',
    () {
      List<String> actions(
        String status, {
        bool writable = true,
        int? membership = 2,
      }) => permittedJobActions(
        status: status,
        writable: writable,
        manager: false,
        membership: membership,
        assignee: 2,
      );
      expect(actions('assigned'), ['in_progress']);
      expect(actions('in_progress'), ['completed']);
      expect(actions('draft'), isEmpty);
      expect(actions('completed'), isEmpty);
      expect(actions('cancelled'), isEmpty);
      expect(actions('assigned', writable: false), isEmpty);
      expect(actions('assigned', membership: 3), isEmpty);
      expect(actions('assigned', membership: null), isEmpty);
      expect(
        permittedJobActions(
          status: 'draft',
          writable: true,
          manager: true,
          membership: null,
          assignee: null,
        ),
        ['cancelled'],
      );
    },
  );

  test('team progress follows the server permissions', () {
    List<String> actions(
      String status, {
      required bool start,
      required bool complete,
    }) => permittedJobActions(
      status: status,
      writable: true,
      manager: false,
      membership: 7,
      assignee: null,
      teamAssigned: true,
      canStart: start,
      canComplete: complete,
    );
    expect(actions('assigned', start: true, complete: false), ['in_progress']);
    expect(actions('in_progress', start: true, complete: false), isEmpty);
    expect(actions('in_progress', start: true, complete: true), ['completed']);
    expect(
      permittedJobActions(
        status: 'assigned',
        writable: true,
        manager: false,
        membership: 7,
        assignee: null,
        teamAssigned: true,
      ),
      isEmpty,
    );
  });
}
