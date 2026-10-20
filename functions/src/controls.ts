// Internal controls around advances: who may approve, who may pay, and when an advance
// must wait. No Firebase imports: unit-tested in controls.test.ts. The point of each rule is
// that one person acting alone (or a made-up employee) cannot move money.

export const DEFAULT_PLATFORM_DRAW_CEILING = 0.5;
export const MAX_REQUESTS_PER_HOUR = 6;

export interface Controls {
  /** An advance above this needs two different admins to approve it. null = never. */
  dualApprovalAboveMinor: number | null;
  /** The person who records the payment must not be one of those who approved it. */
  separatePayer: boolean;
  /** A new employee cannot draw for this many days after being added. 0 = no wait. */
  newEmployeeWaitDays: number;
  /** Advances pause this many days before an employee's last working day. 0 = no pause. */
  pauseDrawsDaysBeforeExit: number;
  /** After payout details change, no payment to that employee for this many hours. */
  payoutCoolingHours: number;
  /** Only someone other than the person who entered an hour record may sign it off. */
  separateSignOff: boolean;
}

export const DEFAULT_CONTROLS: Controls = {
  dualApprovalAboveMinor: null,
  separatePayer: true,
  newEmployeeWaitDays: 0,
  pauseDrawsDaysBeforeExit: 7,
  payoutCoolingHours: 48,
  separateSignOff: true,
};

const wholeInRange = (raw: unknown, min: number, max: number, fallback: number): number => {
  const n = typeof raw === "number" && Number.isFinite(raw) ? Math.round(raw) : NaN;
  return n >= min && n <= max ? n : fallback;
};

export function parseControls(settings: Record<string, unknown>): Controls {
  const dual = settings.dualApprovalAboveMinor;
  return {
    dualApprovalAboveMinor:
      typeof dual === "number" && Number.isFinite(dual) && dual > 0 ? Math.round(dual) : null,
    separatePayer: settings.separatePayer !== false,
    newEmployeeWaitDays: wholeInRange(settings.newEmployeeWaitDays, 0, 90, DEFAULT_CONTROLS.newEmployeeWaitDays),
    pauseDrawsDaysBeforeExit: wholeInRange(settings.pauseDrawsDaysBeforeExit, 0, 90, DEFAULT_CONTROLS.pauseDrawsDaysBeforeExit),
    payoutCoolingHours: wholeInRange(settings.payoutCoolingHours, 0, 720, DEFAULT_CONTROLS.payoutCoolingHours),
    separateSignOff: settings.separateSignOff !== false,
  };
}

/** Does this amount need a second admin? */
export function needsSecondApproval(controls: Controls, amountMinor: number): boolean {
  return controls.dualApprovalAboveMinor !== null && amountMinor > controls.dualApprovalAboveMinor;
}

export type DecideResult =
  | { ok: true; outcome: "reject" | "first_approval" | "final_approval" }
  | { ok: false; reason: string };

/** What happens when `uid` approves or declines an advance. */
export function decide(args: {
  uid: string;
  employeeId: string;
  amountMinor: number;
  approve: boolean;
  firstApprovalBy: string | null;
  controls: Controls;
}): DecideResult {
  if (args.uid === args.employeeId) {
    return { ok: false, reason: "You cannot approve or decline your own advance. Another admin must do it." };
  }
  if (!args.approve) return { ok: true, outcome: "reject" };
  if (!needsSecondApproval(args.controls, args.amountMinor)) return { ok: true, outcome: "final_approval" };
  if (!args.firstApprovalBy) return { ok: true, outcome: "first_approval" };
  if (args.firstApprovalBy === args.uid) {
    return { ok: false, reason: "This advance needs a second approval from a different admin." };
  }
  return { ok: true, outcome: "final_approval" };
}

/** Whether a policy may approve by itself: never above the two-person threshold. */
export function autoApprovalAllowed(controls: Controls, amountMinor: number): boolean {
  return !needsSecondApproval(controls, amountMinor);
}

// A bank or mobile-money transaction id: letters, digits and a few separators.
const PAYMENT_REF = /^[A-Za-z0-9][A-Za-z0-9 ._\-/]{3,59}$/;

export function validatePaymentReference(raw: unknown): string | null {
  if (typeof raw !== "string") return "Enter the bank or mobile-money reference for this payment.";
  const ref = raw.trim().replace(/\s+/g, " ");
  if (!PAYMENT_REF.test(ref)) {
    return "The payment reference must be 4 to 60 characters: letters, numbers and . _ - / only.";
  }
  if (/^DISP-/i.test(ref)) return "Enter the reference from the bank or mobile-money payment, not an app-generated one.";
  return null;
}

export type PayResult = { ok: true } | { ok: false; reason: string };

/** Whether `uid` may record the payment for this advance. */
export function canRecordPayment(args: {
  uid: string;
  employeeId: string;
  decidedBy: string | null;
  firstApprovalBy: string | null;
  payoutChangedAtMs: number | null;
  nowMs: number;
  controls: Controls;
}): PayResult {
  if (args.uid === args.employeeId) {
    return { ok: false, reason: "You cannot record the payment of your own advance. Another admin must do it." };
  }
  if (args.controls.separatePayer) {
    const approvers = [args.decidedBy, args.firstApprovalBy].filter((x): x is string => !!x && x !== "policy");
    if (approvers.includes(args.uid)) {
      return { ok: false, reason: "A different admin must record the payment from the one who approved it." };
    }
  }
  if (args.payoutChangedAtMs !== null && args.controls.payoutCoolingHours > 0) {
    const until = args.payoutChangedAtMs + args.controls.payoutCoolingHours * 3_600_000;
    if (args.nowMs < until) {
      return {
        ok: false,
        reason: `This employee's payout details were changed recently. Payment is held until ${new Date(until).toISOString().slice(0, 16).replace("T", " ")} UTC so the change can be checked with them.`,
      };
    }
  }
  return { ok: true };
}

/** Why an employee cannot ask for an advance right now, or null if they can. */
export function drawBlockedReason(args: {
  nowMs: number;
  createdAtMs: number | null;
  lastWorkingDayMs: number | null;
  controls: Controls;
}): string | null {
  const { nowMs, createdAtMs, lastWorkingDayMs, controls } = args;
  if (controls.newEmployeeWaitDays > 0 && createdAtMs !== null) {
    const from = createdAtMs + controls.newEmployeeWaitDays * 86_400_000;
    if (nowMs < from) {
      return `New employees can ask for an advance after ${controls.newEmployeeWaitDays} days. You can from ${new Date(from).toISOString().slice(0, 10)}.`;
    }
  }
  if (lastWorkingDayMs !== null && controls.pauseDrawsDaysBeforeExit > 0) {
    const pausedFrom = lastWorkingDayMs - controls.pauseDrawsDaysBeforeExit * 86_400_000;
    if (nowMs >= pausedFrom) {
      return "Advances are paused because your last working day is close. Your final pay will be settled by HR.";
    }
  }
  return null;
}

/** The highest share of earned wages any company may set (a platform-wide ceiling). */
export function clampDrawPercent(percent: number, ceiling: number): number {
  const c = Number.isFinite(ceiling) && ceiling > 0 && ceiling <= 1 ? ceiling : DEFAULT_PLATFORM_DRAW_CEILING;
  if (!Number.isFinite(percent) || percent <= 0) return 0;
  return Math.min(percent, c);
}

export function withinRequestRate(countThisHour: number): boolean {
  return countThisHour < MAX_REQUESTS_PER_HOUR;
}
