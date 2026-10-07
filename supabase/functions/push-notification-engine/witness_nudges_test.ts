// Deno tests for witness_nudges.ts. Run with:
//   deno test supabase/functions/push-notification-engine/witness_nudges_test.ts
// (Executed under Node 24 type-stripping with `Deno.test` / `assertEquals`
// shimmed, like _shared/rate_limit_test.ts. Not run under Deno itself.)

import { assertEquals } from 'jsr:@std/assert@1';
import {
  classifyFcmError,
  firstNameOf,
  isWitnessNudgeKind,
  type ProbeCandidate,
  type ProbeSendResult,
  presenceProbeMessage,
  QUIET_RUNNER_ALERTS_PREFERENCE,
  quietSpan,
  runPresenceProbe,
  trustTokenRejections,
  witnessNudgeCopy,
} from './witness_nudges.ts';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

Deno.test('the three kinds are known; anything else is not', () => {
  assertEquals(isWitnessNudgeKind('rule_not_committed'), true);
  assertEquals(isWitnessNudgeKind('quiet'), true);
  assertEquals(isWitnessNudgeKind('app_removed'), true);
  assertEquals(isWitnessNudgeKind('grace_nudge'), false);
  assertEquals(isWitnessNudgeKind(null), false);
});

Deno.test('the preference key is quiet_runner_alerts', () => {
  assertEquals(QUIET_RUNNER_ALERTS_PREFERENCE, 'quiet_runner_alerts');
});

Deno.test('first name only', () => {
  assertEquals(firstNameOf('Sarah Jane Smith'), 'Sarah');
  assertEquals(firstNameOf('  Tom\n'), 'Tom');
  assertEquals(firstNameOf(''), null);
  assertEquals(firstNameOf(null), null);
});

Deno.test('rule_not_committed copy', () => {
  assertEquals(witnessNudgeCopy('rule_not_committed', 'Sarah Smith', { days_paired: 3 }), {
    title: 'Rule of Life not started',
    body: "Sarah hasn't set up a Rule of Life yet. A quick text could help them get started.",
  });
});

Deno.test('quiet copy: two days, then a week', () => {
  assertEquals(witnessNudgeCopy('quiet', 'Sarah Smith', { days_quiet: 2 }), {
    title: 'Checking in on Sarah',
    body: "Sarah hasn't checked in for 2 days. Maybe send a word of encouragement?",
  });
  assertEquals(
    witnessNudgeCopy('quiet', 'Sarah Smith', { days_quiet: 7 }).body,
    "Sarah hasn't checked in for a week. Maybe send a word of encouragement?",
  );
});

Deno.test('quiet span uses the real count, and is safe with nonsense', () => {
  assertEquals(quietSpan(4), '4 days');
  assertEquals(quietSpan(7), 'a week');
  assertEquals(quietSpan(12), 'over a week');
  assertEquals(quietSpan(undefined), '2 days');
  assertEquals(quietSpan(-3), '2 days');
  assertEquals(quietSpan('9'), '2 days');
});

Deno.test('app_removed copy', () => {
  assertEquals(witnessNudgeCopy('app_removed', 'Sarah Smith', {}), {
    title: 'Sarah may have stepped away',
    body: "Sarah's phone isn't receiving The Trellis any more — they may have removed the app. Reach out?",
  });
});

Deno.test('without a name, every kind still reads naturally', () => {
  assertEquals(witnessNudgeCopy('quiet', null, { days_quiet: 2 }).title, 'Checking in on your Runner');
  assertEquals(witnessNudgeCopy('app_removed', null, null).title, 'A Runner may have stepped away');
  assertEquals(
    witnessNudgeCopy('rule_not_committed', null, null).body.startsWith('A Runner you walk with'),
    true,
  );
});

// ---------------------------------------------------------------------------
// FCM error replies
// ---------------------------------------------------------------------------

const fcmError = (status: string, details: unknown[], message = 'x') => ({
  error: { code: 0, status, message, details },
});
const fcmDetail = (errorCode: string) => ({
  '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
  errorCode,
});

Deno.test('UNREGISTERED means the token is gone', () => {
  assertEquals(
    classifyFcmError(404, fcmError('NOT_FOUND', [fcmDetail('UNREGISTERED')])),
    { fcmStatus: 'NOT_FOUND', tokenGone: true },
  );
});

Deno.test('a bare 404 (wrong project) is NOT a gone token', () => {
  assertEquals(classifyFcmError(404, fcmError('NOT_FOUND', [])), { fcmStatus: 'NOT_FOUND', tokenGone: false });
  assertEquals(classifyFcmError(404, null), { fcmStatus: '', tokenGone: false });
});

Deno.test('INVALID_ARGUMENT about the token is a gone token', () => {
  const byField = fcmError('INVALID_ARGUMENT', [
    fcmDetail('INVALID_ARGUMENT'),
    {
      '@type': 'type.googleapis.com/google.rpc.BadRequest',
      fieldViolations: [{ field: 'message.token', description: 'Invalid registration token' }],
    },
  ]);
  assertEquals(classifyFcmError(400, byField).tokenGone, true);

  const byMessage = fcmError(
    'INVALID_ARGUMENT',
    [fcmDetail('INVALID_ARGUMENT')],
    'The registration token is not a valid FCM registration token',
  );
  assertEquals(classifyFcmError(400, byMessage).tokenGone, true);
});

Deno.test('INVALID_ARGUMENT about our own message is NOT a gone token', () => {
  const payloadProblem = fcmError('INVALID_ARGUMENT', [
    fcmDetail('INVALID_ARGUMENT'),
    {
      '@type': 'type.googleapis.com/google.rpc.BadRequest',
      fieldViolations: [{ field: 'message.data[0].value', description: 'Invalid value' }],
    },
  ], 'Invalid value at message.data[0].value');
  assertEquals(classifyFcmError(400, payloadProblem), { fcmStatus: 'INVALID_ARGUMENT', tokenGone: false });
});

Deno.test('auth and quota failures are never a gone token', () => {
  assertEquals(classifyFcmError(401, fcmError('UNAUTHENTICATED', [])).tokenGone, false);
  assertEquals(classifyFcmError(403, fcmError('PERMISSION_DENIED', [fcmDetail('SENDER_ID_MISMATCH')])).tokenGone, false);
  assertEquals(classifyFcmError(429, fcmError('RESOURCE_EXHAUSTED', [fcmDetail('QUOTA_EXCEEDED')])).tokenGone, false);
});

// ---------------------------------------------------------------------------
// The probe
// ---------------------------------------------------------------------------

Deno.test('the probe message is data-only and silent', () => {
  const message = presenceProbeMessage('tok');
  assertEquals(message, {
    token: 'tok',
    data: { type: 'presence_probe' },
    android: { priority: 'normal' },
    apns: {
      headers: { 'apns-push-type': 'background', 'apns-priority': '5' },
      payload: { aps: { 'content-available': 1 } },
    },
  });
  assertEquals('notification' in message, false);
});

Deno.test('the safety catch', () => {
  assertEquals(trustTokenRejections(1, 1), true);
  assertEquals(trustTokenRejections(3, 3), true);
  assertEquals(trustTokenRejections(10, 5), true);
  assertEquals(trustTokenRejections(10, 6), false);
  assertEquals(trustTokenRejections(500, 400), false);
});

function candidates(count: number): ProbeCandidate[] {
  return Array.from({ length: count }, (_, index) => ({ profileId: `p${index}`, token: `t${index}` }));
}

Deno.test('only gone tokens are marked; timeouts and other errors are not', async () => {
  const replies: Record<string, ProbeSendResult> = {
    t0: { ok: true, tokenGone: false },
    t1: { ok: false, tokenGone: true, reason: 'HTTP 404 NOT_FOUND' },
    t2: { ok: false, tokenGone: false, reason: 'timeout' },
    t3: { ok: false, tokenGone: false, reason: 'HTTP 500 INTERNAL' },
  };
  const marked: ProbeCandidate[] = [];
  const summary = await runPresenceProbe(candidates(4), {
    send: (candidate) => Promise.resolve(replies[candidate.token]),
    markRemoved: (candidate) => {
      marked.push(candidate);
      return Promise.resolve(2);
    },
  });
  assertEquals(marked, [{ profileId: 'p1', token: 't1' }]);
  assertEquals(summary, {
    probed: 4,
    delivered: 1,
    tokensGone: 1,
    failed: 2,
    marked: 1,
    nudges: 2,
    markFailed: 0,
    distrusted: false,
  });
});

Deno.test('a wave of gone tokens marks nobody', async () => {
  let marks = 0;
  const summary = await runPresenceProbe(candidates(20), {
    send: () => Promise.resolve({ ok: false, tokenGone: true }),
    markRemoved: () => {
      marks += 1;
      return Promise.resolve(1);
    },
  });
  assertEquals(marks, 0);
  assertEquals(summary.distrusted, true);
  assertEquals(summary.tokensGone, 20);
});

Deno.test('a failed mark is counted and does not stop the others', async () => {
  const summary = await runPresenceProbe(candidates(3), {
    send: () => Promise.resolve({ ok: false, tokenGone: true }),
    markRemoved: (candidate) =>
      candidate.profileId === 'p1' ? Promise.reject(new Error('db down')) : Promise.resolve(1),
  });
  assertEquals(summary.marked, 2);
  assertEquals(summary.markFailed, 1);
  assertEquals(summary.nudges, 2);
});

Deno.test('sends a few at a time, and every candidate exactly once', async () => {
  let inFlight = 0;
  let peak = 0;
  const seen: string[] = [];
  await runPresenceProbe(candidates(60), {
    concurrency: 25,
    send: async (candidate) => {
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      seen.push(candidate.token);
      await new Promise((resolve) => setTimeout(resolve, 1));
      inFlight -= 1;
      return { ok: true, tokenGone: false };
    },
    markRemoved: () => Promise.resolve(0),
  });
  assertEquals(peak <= 25, true);
  assertEquals(new Set(seen).size, 60);
});
