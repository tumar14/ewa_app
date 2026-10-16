// Role-based permission configuration stored at settings/permissions
// in Firestore. Admin always has full access and is not stored here.

// ── Feature catalogue ─────────────────────────────────────────────────────────

class FeatureDef {
  final String key;
  final String label;
  final String description;
  final List<String> actions; // subset of: view create edit delete approve

  const FeatureDef({
    required this.key,
    required this.label,
    required this.description,
    required this.actions,
  });
}

const featureCatalogue = [
  FeatureDef(
    key: 'drawRequests',
    label: 'Draw Requests',
    description: 'Wage advance requests submitted by workers',
    actions: ['view', 'create'],
  ),
  FeatureDef(
    key: 'approvals',
    label: 'Approvals',
    description: 'Review and approve or reject draw requests',
    actions: ['view', 'approve'],
  ),
  FeatureDef(
    key: 'workforce',
    label: 'Workforce',
    description: 'Employee profiles, hours, and session history',
    actions: ['view', 'create', 'edit', 'delete'],
  ),
  FeatureDef(
    key: 'payroll',
    label: 'Payroll Export',
    description: 'Generate and export payroll runs',
    actions: ['view', 'create'],
  ),
  FeatureDef(
    key: 'disbursements',
    label: 'Disbursements',
    description: 'Process approved wage advance payments',
    actions: ['view', 'approve'],
  ),
  FeatureDef(
    key: 'supervisorSignoff',
    label: 'Supervisor Sign-off',
    description: 'Review and approve daily attendance records',
    actions: ['view', 'approve'],
  ),
  FeatureDef(
    key: 'auditLog',
    label: 'Audit Log',
    description: 'Full activity and decision history',
    actions: ['view'],
  ),
  FeatureDef(
    key: 'reports',
    label: 'Reports',
    description: 'Attendance and payroll analytics',
    actions: ['view'],
  ),
  FeatureDef(
    key: 'settings',
    label: 'Settings',
    description: 'System configuration — draw caps, fees, payday rules',
    actions: ['view', 'edit'],
  ),
];

// ── Default permissions per role ──────────────────────────────────────────────

const _defaultWorker = {
  'drawRequests':      ['view', 'create'],
  'approvals':         <String>[],
  'workforce':         <String>[],
  'payroll':           <String>[],
  'disbursements':     <String>[],
  'supervisorSignoff': <String>[],
  'auditLog':          <String>[],
  'reports':           <String>[],
  'settings':          <String>[],
};

const _defaultSupervisor = {
  'drawRequests':      ['view', 'create'],
  'approvals':         ['view', 'approve'],
  'workforce':         ['view', 'edit'],
  'payroll':           ['view'],
  'disbursements':     ['view'],
  'supervisorSignoff': ['view', 'approve'],
  'auditLog':          ['view'],
  'reports':           ['view'],
  'settings':          ['view'],
};

// ── Model ─────────────────────────────────────────────────────────────────────

class AppPermissions {
  // roles['worker']['drawRequests'] = ['view', 'create']
  final Map<String, Map<String, List<String>>> roles;

  const AppPermissions({required this.roles});

  factory AppPermissions.defaults() => AppPermissions(roles: {
        'worker':     Map.from(_defaultWorker.map((k, v) => MapEntry(k, List<String>.from(v)))),
        'supervisor': Map.from(_defaultSupervisor.map((k, v) => MapEntry(k, List<String>.from(v)))),
      });

  factory AppPermissions.fromMap(Map<String, dynamic> map) {
    final roles = <String, Map<String, List<String>>>{};
    for (final entry in map.entries) {
      if (entry.key == 'admin') continue;
      if (entry.value is! Map) continue;
      roles[entry.key] = (entry.value as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, List<String>.from(v as List)));
    }
    return AppPermissions(roles: roles);
  }

  Map<String, dynamic> toMap() => {
        for (final entry in roles.entries)
          entry.key: entry.value.map((k, v) => MapEntry(k, v)),
      };

  /// Returns true if [role] can perform [action] on [feature].
  /// Admin always returns true.
  bool can(String role, String feature, String action) {
    if (role == 'admin') return true;
    return roles[role]?[feature]?.contains(action) ?? false;
  }

  AppPermissions withUpdate(String role, String feature, String action, bool granted) {
    final updated = Map<String, Map<String, List<String>>>.from(
      roles.map((r, fs) => MapEntry(r, Map<String, List<String>>.from(
        fs.map((f, acts) => MapEntry(f, List<String>.from(acts))),
      ))),
    );
    // Initialise role + feature if this is the first toggle for them
    updated.putIfAbsent(role,
        () => {for (final f in featureCatalogue) f.key: <String>[]});
    updated[role]!.putIfAbsent(feature, () => []);

    final actions = updated[role]![feature]!;
    if (granted) {
      if (!actions.contains(action)) actions.add(action);
    } else {
      actions.remove(action);
    }
    return AppPermissions(roles: updated);
  }
}
