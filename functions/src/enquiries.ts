import { createHash } from "node:crypto";
import { Timestamp } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { db } from "./common";
import { ENQUIRY_LIMIT_PER_HOUR, hourBucket, validateEnquiry } from "./enquiryRules";

const MAX_BODY_BYTES = 8 * 1024;

/**
 * Receives the public website's employer-registration and contact forms.
 * It only stores a record for the platform admin to read: it never creates a
 * company, an account or any role. Clients cannot read or write
 * public_enquiries directly (see firestore.rules).
 *
 * Abuse controls: strict validation, a hidden honeypot field, a small body
 * limit, and a per-source hourly limit. The source is stored only as a salted
 * hash, never as a raw IP address.
 */
export const submitEnquiry = onRequest({ cors: true, maxInstances: 5 }, async (req, res) => {
  res.set("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "Use POST." });
    return;
  }
  const length = Number(req.get("content-length") ?? 0);
  if (length > MAX_BODY_BYTES) {
    res.status(413).json({ ok: false, error: "Request too large." });
    return;
  }

  const result = validateEnquiry(req.body);
  if (result.ok === "spam") {
    // Look successful so bots learn nothing, but store nothing.
    res.status(200).json({ ok: true });
    return;
  }
  if (!result.ok) {
    res.status(400).json({ ok: false, error: result.error });
    return;
  }

  const nowMs = Date.now();
  const ip = (req.get("x-forwarded-for") ?? req.ip ?? "unknown").split(",")[0].trim();
  const source = createHash("sha256").update(`hola-manje:${ip}`).digest("hex").slice(0, 32);
  const limitRef = db.collection("enquiry_rate_limits").doc(`${source}_${hourBucket(nowMs)}`);
  const enquiryRef = db.collection("public_enquiries").doc();

  const allowed = await db.runTransaction(async (tx) => {
    const count = ((await tx.get(limitRef)).data()?.count as number | undefined) ?? 0;
    if (count >= ENQUIRY_LIMIT_PER_HOUR) return false;
    tx.set(limitRef, { count: count + 1, expiresAt: Timestamp.fromMillis(nowMs + 2 * 3_600_000) });
    tx.set(enquiryRef, {
      type: result.enquiry.type,
      ...result.enquiry.fields,
      status: "new",
      source,
      createdAt: Timestamp.fromMillis(nowMs),
    });
    return true;
  });

  if (!allowed) {
    res.status(429).json({ ok: false, error: "Too many submissions. Please try again later." });
    return;
  }
  res.status(200).json({ ok: true, reference: enquiryRef.id.slice(0, 8).toUpperCase() });
});
