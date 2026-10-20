// Who may sign off an hours record. No Firebase imports: unit-tested in signoffRules.test.ts.

export type SignOffResult = { ok: true } | { ok: false; reason: string };

export function canSignOff(args: {
  uid: string;
  employeeId: string;
  editedBy: string | null;
  voided: boolean;
  reviewed: boolean;
  separate: boolean;
}): SignOffResult {
  if (args.voided) return { ok: false, reason: "This record is void." };
  if (args.reviewed) return { ok: false, reason: "Already signed off." };
  if (args.uid === args.employeeId) return { ok: false, reason: "You cannot sign off your own hours." };
  if (args.separate && args.editedBy === args.uid) {
    return { ok: false, reason: "You entered or uploaded this record, so someone else must sign it off." };
  }
  return { ok: true };
}
