// Which changes to an employee record are worth an audit entry. No Firebase imports:
// unit-tested in employeeChanges.test.ts. Account numbers are never copied into the log; a
// payout change is recorded as "changed" only.

type Obj = Record<string, unknown>;

const WATCHED = ["hourlyRate", "role", "active", "employeeNumber", "name", "department", "lastWorkingDay"] as const;

function plain(v: unknown): unknown {
  if (v && typeof v === "object" && "toMillis" in v && typeof (v as { toMillis: unknown }).toMillis === "function") {
    return (v as { toMillis: () => number }).toMillis();
  }
  return v === undefined ? null : v;
}

export function changedEmployeeFields(before: Obj, after: Obj): {
  changes: Array<{ field: string; from: unknown; to: unknown }>;
  payoutChanged: boolean;
} {
  const changes: Array<{ field: string; from: unknown; to: unknown }> = [];
  for (const field of WATCHED) {
    const from = plain(before[field]);
    const to = plain(after[field]);
    if (JSON.stringify(from) !== JSON.stringify(to)) changes.push({ field, from, to });
  }
  const payoutChanged =
    JSON.stringify(plain(before.disbursementMethod)) !== JSON.stringify(plain(after.disbursementMethod)) ||
    JSON.stringify(plain(before.disbursementDetails)) !== JSON.stringify(plain(after.disbursementDetails));
  return { changes, payoutChanged };
}
