// Protects claim codes from being guessed. No Firebase imports: unit-tested in
// claimGuard.test.ts. A seat is claimed with a company code, employee number, name and a
// one-time code. Wrong guesses are counted per seat; after too many the seat is locked for a
// while, and a code expires if it is not used. Callers answer every refusal the same way, so
// nothing reveals whether a seat exists, is locked, or was close.

export const MAX_FAILED_CLAIMS = 5;
export const CLAIM_LOCK_MS = 30 * 60_000;
export const DEFAULT_CLAIM_CODE_VALID_DAYS = 30;

export function isLocked(lockedUntilMs: number | null | undefined, nowMs: number): boolean {
  return typeof lockedUntilMs === "number" && lockedUntilMs > nowMs;
}

/** Code older than the company's validity (0 days = never expires). Rows with no issue date are treated as valid. */
export function isExpired(issuedAtMs: number | null | undefined, nowMs: number, validDays: number): boolean {
  if (!(validDays > 0) || typeof issuedAtMs !== "number") return false;
  return nowMs - issuedAtMs > validDays * 86_400_000;
}

export function validDaysFrom(settings: Record<string, unknown>): number {
  const n = settings.claimCodeValidDays;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 && n <= 365 ? n : DEFAULT_CLAIM_CODE_VALID_DAYS;
}

/** After a wrong guess: the new failure count and, if the limit is reached, when the seat unlocks. */
export function afterFailure(failures: number, nowMs: number): { failures: number; lockedUntilMs: number | null } {
  const next = (Number.isFinite(failures) && failures > 0 ? Math.floor(failures) : 0) + 1;
  return next >= MAX_FAILED_CLAIMS ? { failures: 0, lockedUntilMs: nowMs + CLAIM_LOCK_MS } : { failures: next, lockedUntilMs: null };
}
