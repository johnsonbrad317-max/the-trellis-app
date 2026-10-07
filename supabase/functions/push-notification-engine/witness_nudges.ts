// The Trellis — push-notification-engine: Witness nudges and the presence probe
// =============================================================================
// The parts of index.ts that decide WHAT is said and WHAT a reply from FCM
// means, kept free of network and database code so they can be tested on their
// own (witness_nudges_test.ts). index.ts does the I/O and calls these.
//
//   witness_nudge   one row in public.witness_nudges (026_witness_nudges.sql):
//                   a Runner has not started a Rule of Life, has gone quiet,
//                   or may have removed the app. Pushed to that row's Witness
//                   under their `quiet_runner_alerts` switch. First name only —
//                   never a rhythm's title.
//
//   presence_probe  once a day (pg_cron job trellis-presence-probe), a silent,
//                   data-only push to each Runner the app has not been opened
//                   by for two days. Nothing is shown on the phone. If FCM
//                   says the token no longer belongs to an installed app
//                   (UNREGISTERED, or INVALID_ARGUMENT about the token), the
//                   Runner is marked app-removed and each of their Witnesses
//                   gets an `app_removed` nudge.
//
// HOW FAST "APP REMOVED" IS NOTICED: not instantly. On iPhone, Apple tells FCM
// that an app was deleted only some time after the fact — often hours, and it
// can be a day or more — and the probe itself runs once a day for Runners not
// seen for two days. Expect a Witness to hear "may have stepped away" within a
// few days of the app being removed, not the moment it happens.
// =============================================================================

import { isPlainObject } from '../_shared/http.ts';

export const WITNESS_NUDGE_KINDS = ['rule_not_committed', 'quiet', 'app_removed'] as const;
export type WitnessNudgeKind = (typeof WITNESS_NUDGE_KINDS)[number];

export function isWitnessNudgeKind(value: unknown): value is WitnessNudgeKind {
  return typeof value === 'string' && (WITNESS_NUDGE_KINDS as readonly string[]).includes(value);
}

/// The Witness's switch for every witness_nudge, in profiles.notification_
/// preferences. Absent or true = deliver; only an explicit false mutes.
export const QUIET_RUNNER_ALERTS_PREFERENCE = 'quiet_runner_alerts';

/// A single clean line of bounded length (index.ts's `clean`, repeated here so
/// this file has no dependency on the I/O module).
function oneLine(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null;
  // deno-lint-ignore no-control-regex
  const text = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  if (text.length === 0) return null;
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

/// The first word of a person's name, or null when there is none.
export function firstNameOf(name: unknown): string | null {
  const full = oneLine(name, 200);
  if (!full) return null;
  return oneLine(full.split(/\s+/)[0], 40);
}

/// "2 days", "5 days", "a week", "over a week" — how long a Runner has been
/// quiet. The generator first announces at two days and again at seven, but a
/// Runner whose rhythms were not due for a while can be first noticed later,
/// so the real count is used rather than a fixed "2 days".
export function quietSpan(daysQuiet: unknown): string {
  const days = typeof daysQuiet === 'number' && Number.isInteger(daysQuiet) && daysQuiet >= 2
    ? daysQuiet
    : 2;
  if (days < 7) return `${days} days`;
  if (days === 7) return 'a week';
  return 'over a week';
}

/// Title and body for one witness_nudge row.
export function witnessNudgeCopy(
  kind: WitnessNudgeKind,
  runnerName: string | null,
  detail: unknown,
): { title: string; body: string } {
  const first = firstNameOf(runnerName);
  switch (kind) {
    case 'rule_not_committed':
      return {
        title: 'Rule of Life not started',
        body: `${first ?? 'A Runner you walk with'} hasn't set up a Rule of Life yet. ` +
          'A quick text could help them get started.',
      };
    case 'quiet': {
      const span = quietSpan(isPlainObject(detail) ? detail.days_quiet : null);
      return {
        title: first ? `Checking in on ${first}` : 'Checking in on your Runner',
        body: `${first ?? 'A Runner you walk with'} hasn't checked in for ${span}. ` +
          'Maybe send a word of encouragement?',
      };
    }
    case 'app_removed':
      return {
        title: first ? `${first} may have stepped away` : 'A Runner may have stepped away',
        body: first
          ? `${first}'s phone isn't receiving The Trellis any more — they may have removed the app. Reach out?`
          : "The phone of a Runner you walk with isn't receiving The Trellis any more — they may have " +
            'removed the app. Reach out?',
      };
  }
}

// ---------------------------------------------------------------------------
// What an FCM error reply means
// ---------------------------------------------------------------------------

export interface FcmErrorInfo {
  /// FCM's short status word (NOT_FOUND, INVALID_ARGUMENT, ...) — safe to log.
  fcmStatus: string;
  /// True only when FCM says this device token is gone for good: the app was
  /// removed from the phone, or the token is not a token at all. Never true for
  /// a problem with our own credentials, project or message.
  tokenGone: boolean;
}

/// Reads an FCM HTTP v1 error body (already parsed JSON, or null). The body is
/// only inspected, never returned or logged — it can describe the token.
///
///   UNREGISTERED      details[].errorCode on an HTTP 404: the app instance is
///                     gone (uninstalled, or the token expired). Token gone.
///   INVALID_ARGUMENT  usually OUR message is malformed — then NOT token gone.
///                     Only when FCM points at the token itself (a BadRequest
///                     field violation on `message.token`, or its message
///                     about "registration token") is it token gone.
/// A bare HTTP 404 without the UNREGISTERED code (a wrong project id, say) is
/// deliberately NOT token gone: that would mark everybody as app-removed.
export function classifyFcmError(httpStatus: number, body: unknown): FcmErrorInfo {
  const error = isPlainObject(body) && isPlainObject(body.error) ? body.error : null;
  const fcmStatus = error && typeof error.status === 'string' ? error.status.slice(0, 40) : '';
  const details = error && Array.isArray(error.details) ? error.details.filter(isPlainObject) : [];

  const errorCodes = details
    .map((detail) => detail.errorCode)
    .filter((code): code is string => typeof code === 'string');

  if (errorCodes.includes('UNREGISTERED')) {
    return { fcmStatus: fcmStatus || 'UNREGISTERED', tokenGone: true };
  }

  const invalidArgument = httpStatus === 400 &&
    (fcmStatus === 'INVALID_ARGUMENT' || errorCodes.includes('INVALID_ARGUMENT'));
  if (invalidArgument) {
    const aboutToken = details.some((detail) =>
      Array.isArray(detail.fieldViolations) &&
      detail.fieldViolations.some((violation) => isPlainObject(violation) && violation.field === 'message.token')
    ) || (typeof error?.message === 'string' && /registration token/i.test(error.message));
    return { fcmStatus, tokenGone: aboutToken };
  }

  return { fcmStatus, tokenGone: false };
}

// ---------------------------------------------------------------------------
// The presence probe
// ---------------------------------------------------------------------------

/// Most Runners probed in one run (presence_probe_candidates also caps it).
export const PRESENCE_PROBE_LIMIT = 500;
/// Sends in flight at once.
export const PRESENCE_PROBE_CONCURRENCY = 25;

/// The FCM v1 `message` for a probe: data only, no `notification`, so nothing
/// is ever displayed. On iPhone it is a background ("content-available") push
/// at low priority; on Android a normal-priority data message. The app ignores
/// it (lib/services/push_notifications.dart).
export function presenceProbeMessage(token: string): Record<string, unknown> {
  return {
    token,
    data: { type: 'presence_probe' },
    android: { priority: 'normal' },
    apns: {
      headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    },
  };
}

/// Up to this many "token gone" answers in one run are always believed.
const ALWAYS_TRUSTED_REJECTIONS = 3;

/// A safety catch: if MORE than half of a run's probes come back "token gone"
/// (and more than a handful), something is wrong on our side — a changed
/// Firebase project, an APNs key problem — not a wave of uninstalls. Then
/// nobody is marked and no Witness is told; the run's log says why.
export function trustTokenRejections(probed: number, gone: number): boolean {
  if (gone <= ALWAYS_TRUSTED_REJECTIONS) return true;
  return gone * 2 <= probed;
}

export interface ProbeCandidate {
  profileId: string;
  token: string;
}

export interface ProbeSendResult {
  ok: boolean;
  tokenGone: boolean;
  /// Log-safe reason for a failure.
  reason?: string;
}

export interface ProbeDeps {
  /// Sends one probe. Must not throw.
  send(candidate: ProbeCandidate): Promise<ProbeSendResult>;
  /// Marks one Runner app-removed and writes their Witnesses' nudges; returns
  /// how many nudges were written. May throw (counted as a failure).
  markRemoved(candidate: ProbeCandidate): Promise<number>;
  concurrency?: number;
}

export interface ProbeSummary {
  probed: number;
  delivered: number;
  tokensGone: number;
  /// Other failures (timeouts, FCM errors that say nothing about the token).
  failed: number;
  marked: number;
  nudges: number;
  markFailed: number;
  /// True when the safety catch above refused to mark anyone.
  distrusted: boolean;
}

/// Sends every probe (a few at a time), then marks the Runners whose token is
/// gone — unless the safety catch says not to.
export async function runPresenceProbe(candidates: ProbeCandidate[], deps: ProbeDeps): Promise<ProbeSummary> {
  const concurrency = Math.max(1, deps.concurrency ?? PRESENCE_PROBE_CONCURRENCY);
  const results: Array<{ candidate: ProbeCandidate; result: ProbeSendResult }> = [];
  for (let start = 0; start < candidates.length; start += concurrency) {
    const batch = candidates.slice(start, start + concurrency);
    const sent = await Promise.all(batch.map((candidate) => deps.send(candidate)));
    batch.forEach((candidate, index) => results.push({ candidate, result: sent[index] }));
  }

  const gone = results.filter(({ result }) => !result.ok && result.tokenGone);
  const summary: ProbeSummary = {
    probed: results.length,
    delivered: results.filter(({ result }) => result.ok).length,
    tokensGone: gone.length,
    failed: results.filter(({ result }) => !result.ok && !result.tokenGone).length,
    marked: 0,
    nudges: 0,
    markFailed: 0,
    distrusted: !trustTokenRejections(results.length, gone.length),
  };
  if (summary.distrusted) return summary;

  for (const { candidate } of gone) {
    try {
      const nudges = await deps.markRemoved(candidate);
      summary.marked += 1;
      summary.nudges += nudges;
    } catch (_) {
      summary.markFailed += 1;
    }
  }
  return summary;
}
