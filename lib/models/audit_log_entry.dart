import 'package:cloud_firestore/cloud_firestore.dart';

/// A single audit_log entry written by Cloud Functions (functions/src/index.ts,
/// spec section 4: "full audit trail — every request, decision, and
/// disbursement logged with timestamp and approver identity"). Entries have
/// different shapes depending on `type`, so this model keeps the raw fields
/// and exposes normalized timestamp/actor/summary helpers instead of
/// forcing every action type into one rigid shape.
class AuditLogEntry {
  final String id;
  final String type;
  final Map<String, dynamic> data;

  AuditLogEntry({required this.id, required this.type, required this.data});

  factory AuditLogEntry.fromMap(String id, Map<String, dynamic> map) {
    return AuditLogEntry(id: id, type: map['type'] as String? ?? 'unknown', data: map);
  }

  /// Every write includes a common `timestamp` field; older entries (written
  /// before that field existed) fall back to their type-specific field.
  DateTime? get timestamp {
    final common = data['timestamp'];
    if (common is Timestamp) return common.toDate();
    for (final key in ['createdAt', 'deactivatedAt', 'decidedAt', 'disbursedAt']) {
      final ts = data[key];
      if (ts is Timestamp) return ts.toDate();
    }
    return null;
  }

  String? get actorId {
    for (final key in ['createdBy', 'deactivatedBy', 'decidedBy', 'disbursedBy', 'performedBy', 'changedBy', 'addedBy', 'signedBy']) {
      final v = data[key];
      if (v is String) return v;
    }
    return null;
  }

  String? get employeeId => data['employeeId'] as String?;

  String _money(String key) {
    final minor = data[key];
    return minor is num ? (minor / 100).toStringAsFixed(2) : '?';
  }

  String get summary {
    switch (type) {
      case 'employee_created':
        return 'Created employee ${data['name'] ?? employeeId} (${data['role'] ?? 'worker'})';
      case 'employee_deactivated':
        return 'Deactivated employee ${employeeId ?? ''}';
      case 'draw_request':
        return 'Draw of E${_money('amountMinor')} requested by ${employeeId ?? ''}';
      case 'draw_decision':
        final approved = data['approved'] == true;
        final by = data['auto'] == true ? ' (automatically, by company policy)' : '';
        return '${approved ? 'Approved' : 'Declined'}$by draw of E${_money('amountMinor')} for ${employeeId ?? ''}';
      case 'draw_first_approval':
        return 'First approval given for a draw of E${_money('amountMinor')} for ${employeeId ?? ''}; a second admin is needed';
      case 'settings_changed':
        final changes = (data['changes'] as List?) ?? const [];
        final fields = [for (final c in changes) if (c is Map) '${c['field']}'];
        return 'Changed settings: ${fields.isEmpty ? '(none)' : fields.join(', ')}';
      case 'employee_added':
        return 'Added employee ${data['name'] ?? ''} (${data['role'] ?? 'worker'})';
      case 'employee_changed':
        final changes = (data['changes'] as List?) ?? const [];
        final fields = [for (final c in changes) if (c is Map) '${c['field']}'];
        return 'Changed employee ${employeeId ?? ''}: ${fields.join(', ')}';
      case 'time_signoff':
        return 'Signed off ${data['count'] ?? 0} hour record(s)';
      case 'disbursement':
        return 'Disbursed E${_money('amountMinor')} to ${employeeId ?? ''} (${data['disbursementRef'] ?? ''})';
      case 'payroll_run':
        return 'Payroll run completed (${data['drawCount'] ?? 0} draws deducted)';
      case 'settlement_created':
        return 'Settlement created, E${_money('expectedMinor')} expected';
      case 'settlement_deductions_confirmed':
        return 'Payroll deductions confirmed at E${_money('confirmedMinor')}';
      case 'settlement_payment_recorded':
        return 'Payment of E${_money('amountMinor')} recorded (${data['providerTransactionId'] ?? ''})';
      case 'settlement_exception_resolved':
        return 'Settlement exception resolved: ${data['note'] ?? ''}';
      case 'settlement_cancelled':
        return 'Settlement cancelled: ${data['reason'] ?? ''}';
      default:
        return type;
    }
  }
}
