import 'package:intl/intl.dart';
import '../utils/currency_formatter.dart';

/// One company's row in the platform admin's overview. Counts and one money
/// figure for the whole company; never a person's name or an individual amount.
class CompanyOverview {
  final String companyId;
  final String name;
  final String shortCode;
  final String currency;
  final bool active;
  final int employees;
  final int activeEmployees;
  final int activeWorkers;
  final int advancesThisCycle;
  final int pendingApproval;
  final int awaitingPayout;
  final int openSettlements;
  final int owedMinor;

  const CompanyOverview({
    required this.companyId,
    required this.name,
    required this.shortCode,
    required this.currency,
    required this.active,
    required this.employees,
    required this.activeEmployees,
    required this.activeWorkers,
    required this.advancesThisCycle,
    required this.pendingApproval,
    required this.awaitingPayout,
    required this.openSettlements,
    required this.owedMinor,
  });

  factory CompanyOverview.fromMap(Map<dynamic, dynamic> m) {
    int n(String key) {
      final v = m[key];
      return v is num ? v.toInt() : 0;
    }

    return CompanyOverview(
      companyId: m['companyId'] is String ? m['companyId'] as String : '',
      name: m['name'] as String? ?? '',
      shortCode: m['shortCode'] as String? ?? '',
      currency: m['currency'] as String? ?? '',
      active: m['active'] as bool? ?? true,
      employees: n('employees'),
      activeEmployees: n('activeEmployees'),
      activeWorkers: n('activeWorkers'),
      advancesThisCycle: n('advancesThisCycle'),
      pendingApproval: n('pendingApproval'),
      awaitingPayout: n('awaitingPayout'),
      openSettlements: n('openSettlements'),
      owedMinor: n('owedMinor'),
    );
  }

  /// "E 125.00" for lilangeni, "ZAR 125.00" for any other currency.
  String get owedDisplay {
    if (currency.isEmpty || currency == 'SZL') return CurrencyFormatter.formatMinor(owedMinor);
    return '$currency ${NumberFormat('#,##0.00').format(owedMinor / 100)}';
  }
}

class OverviewTotals {
  final int companies;
  final int activeCompanies;
  final int activeEmployees;
  final int activeWorkers;
  final int advancesThisCycle;
  final int pendingApproval;
  final int awaitingPayout;
  final int openSettlements;

  const OverviewTotals({
    required this.companies,
    required this.activeCompanies,
    required this.activeEmployees,
    required this.activeWorkers,
    required this.advancesThisCycle,
    required this.pendingApproval,
    required this.awaitingPayout,
    required this.openSettlements,
  });

  factory OverviewTotals.fromMap(Map<dynamic, dynamic> m) {
    int n(String key) {
      final v = m[key];
      return v is num ? v.toInt() : 0;
    }

    return OverviewTotals(
      companies: n('companies'),
      activeCompanies: n('activeCompanies'),
      activeEmployees: n('activeEmployees'),
      activeWorkers: n('activeWorkers'),
      advancesThisCycle: n('advancesThisCycle'),
      pendingApproval: n('pendingApproval'),
      awaitingPayout: n('awaitingPayout'),
      openSettlements: n('openSettlements'),
    );
  }
}

class PlatformOverview {
  final DateTime generatedAt;
  final bool truncated;
  final OverviewTotals totals;
  final List<CompanyOverview> companies;

  const PlatformOverview({
    required this.generatedAt,
    required this.truncated,
    required this.totals,
    required this.companies,
  });

  factory PlatformOverview.fromMap(Map<dynamic, dynamic> m) {
    return PlatformOverview(
      generatedAt: DateTime.fromMillisecondsSinceEpoch(m['generatedAtMs'] is num ? (m['generatedAtMs'] as num).toInt() : 0),
      truncated: m['truncated'] as bool? ?? false,
      totals: OverviewTotals.fromMap((m['totals'] as Map?) ?? const {}),
      companies: [
        for (final c in (m['companies'] as List?) ?? const [])
          CompanyOverview.fromMap(c as Map),
      ],
    );
  }
}
