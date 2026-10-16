const _defaultDepartments = [
  'Cutting', 'Sewing', 'Finishing', 'Quality Control',
  'Packing', 'Warehouse', 'Maintenance', 'Security',
  'Administration', 'Management',
];

const _defaultRoles = ['worker', 'supervisor'];

/// Converts a role key to a human-readable label.
/// 'worker' → 'Worker', 'line_leader' → 'Line Leader'
String roleLabel(String role) {
  if (role.isEmpty) return role;
  return role
      .split(RegExp(r'[_\s]+'))
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

class OrgConfig {
  final List<String> departments;
  final List<String> roles; // non-admin roles, in display order

  const OrgConfig({
    required this.departments,
    required this.roles,
  });

  factory OrgConfig.defaults() => const OrgConfig(
        departments: _defaultDepartments,
        roles: _defaultRoles,
      );

  factory OrgConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return OrgConfig.defaults();
    final depts = map['departments'];
    final roles = map['roles'];
    return OrgConfig(
      departments: depts != null
          ? List<String>.from(depts as List)
          : _defaultDepartments,
      roles: roles != null
          ? List<String>.from(roles as List)
          : _defaultRoles,
    );
  }

  Map<String, dynamic> toMap() => {
        'departments': departments,
        'roles': roles,
      };
}
