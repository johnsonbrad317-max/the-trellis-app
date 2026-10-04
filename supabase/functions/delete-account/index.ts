// The Trellis — delete-account
// =============================================================================
// Backs the Delete Account & Data button (lib/widgets/settings_drawer.dart).
// Deleting an auth.users row needs the service-role key — never shipped to
// any client — so this has to happen server-side, invoked via
// `supabase.functions.invoke('delete-account')`, which the Supabase Flutter
// SDK automatically attaches the caller's own JWT to.
//
// Order matters here, and it's enforced by this function's own control
// flow rather than left to the client: every active Witness is notified
// BEFORE the delete happens, so an app crash or a lost connection mid-flow
// can only ever result in a still-live account (safe to retry), never a
// deleted account whose Witness was never told.
//
// What can NOT stop the deletion (Apple requires that deletion actually
// happens on request): a slow, failing or unconfigured push engine, a failed
// profile/pairing lookup, or a slow Cronofy. Each of those courtesy steps is
// best effort and strictly time-boxed (8 s per call, 12 s for all of it, run
// side by side), then the account is deleted regardless.
//
// Contract with the app (lib/models/runner_profile.dart → deleteAccount):
//   200 { "deleted": true }           the account is gone
//   non-200 { "error", "code" }       it is NOT gone; safe to retry
//
// Secrets:
//   PUSH_ENGINE_WEBHOOK_SECRET   same value the push engine checks; without it
//                                Witnesses are simply not notified.
//   CRONOFY_CLIENT_ID, CRONOFY_CLIENT_SECRET, CRONOFY_DATA_CENTER
//                                optional — only used to revoke the user's
//                                calendar grants at Cronofy before their stored
//                                tokens are deleted with the account.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by the platform for every Edge Function.
//
// Deploy (JWT verification ON — the default):
//   supabase functions deploy delete-account
// =============================================================================

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { authenticate } from '../_shared/auth.ts';
import { revokeToken } from '../_shared/cronofy.ts';
import {
  describeError,
  discardBody,
  errorResponse,
  fetchWithTimeout,
  guarded,
  handlePreflight,
  isUuid,
  jsonResponse,
  methodNotAllowed,
} from '../_shared/http.ts';

/// How long any single best-effort courtesy call (push engine, Cronofy revoke)
/// may take.
const COURTESY_TIMEOUT_MS = 8_000;
/// Hard ceiling on ALL the courtesy work together (lookups included); when it
/// runs out the deletion goes ahead without waiting any longer.
const COURTESY_BUDGET_MS = 12_000;
/// The delete itself cascades through the user's rows; give it room.
const DELETE_TIMEOUT_MS = 25_000;
/// Nobody has anywhere near this many Witnesses; it only bounds the fan-out.
const MAX_WITNESSES = 25;

/// Tells each active Witness, through the same engine the database triggers
/// use. Never throws; failures are logged and otherwise ignored.
async function notifyWitnesses(
  supabaseUrl: string,
  userId: string,
  runnerName: string,
  witnessIds: string[],
): Promise<void> {
  if (witnessIds.length === 0) return;

  // The engine authenticates callers by shared secret (the anon key is public
  // and proves nothing). Without it every call would be a guaranteed 401, so
  // don't make them.
  const pushSecret = Deno.env.get('PUSH_ENGINE_WEBHOOK_SECRET');
  if (!pushSecret) {
    console.error('delete-account: PUSH_ENGINE_WEBHOOK_SECRET is not set; Witnesses will not be notified.');
    return;
  }

  const outcomes = await Promise.all(witnessIds.map(async (witnessId) => {
    try {
      const response = await fetchWithTimeout(
        `${supabaseUrl}/functions/v1/push-notification-engine`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-trellis-webhook-secret': pushSecret,
          },
          body: JSON.stringify({
            event_type: 'account_deleted',
            table: 'profiles',
            record: { runner_id: userId, witness_id: witnessId, runner_name: runnerName },
          }),
        },
        COURTESY_TIMEOUT_MS,
        'push engine',
      );
      await discardBody(response);
      return response.ok ? 'ok' : `HTTP ${response.status}`;
    } catch (error) {
      return error instanceof Error ? error.name : 'error';
    }
  }));

  const failed = outcomes.filter((outcome) => outcome !== 'ok');
  if (failed.length > 0) {
    // Deliberately not fatal — a lost notification is not a reason to refuse
    // an account-deletion request.
    console.error(
      `delete-account: ${failed.length} of ${outcomes.length} Witness deletion notices failed:`,
      [...new Set(failed)].join(', '),
    );
  }
}

/// Revokes the user's calendar grants at Cronofy while we still hold the
/// tokens (the tokens themselves are purged from Vault by the cascade when the
/// account is deleted). Never throws.
async function revokeCalendarGrants(admin: SupabaseClient, userId: string): Promise<void> {
  try {
    const { data, error } = await admin.rpc('calendar_read_tokens', { p_user_id: userId });
    if (error) {
      // Includes "function does not exist" on a project without the calendar
      // migration — nothing to revoke there.
      console.error('delete-account: could not read calendar connections (skipping revoke):', describeError(error));
      return;
    }
    const rows = (Array.isArray(data) ? data : []) as Array<{ refresh_token?: unknown; access_token?: unknown }>;
    const tokens = rows
      .map((row) => (typeof row.refresh_token === 'string' && row.refresh_token
        ? row.refresh_token
        : typeof row.access_token === 'string' && row.access_token
        ? row.access_token
        : null))
      .filter((token): token is string => token !== null)
      .slice(0, 3);
    if (tokens.length === 0) return;

    const deadlineMs = Date.now() + COURTESY_TIMEOUT_MS;
    const results = await Promise.allSettled(
      tokens.map((token) => revokeToken(token, { timeoutMs: COURTESY_TIMEOUT_MS, deadlineMs })),
    );
    const failed = results.filter((result) => result.status === 'rejected');
    if (failed.length > 0) {
      console.error(
        `delete-account: ${failed.length} of ${results.length} calendar revocations failed (continuing):`,
        [...new Set(failed.map((result) => describeError((result as PromiseRejectedResult).reason)))].join('; '),
      );
    }
  } catch (error) {
    console.error('delete-account: calendar revoke step failed (continuing):', describeError(error));
  }
}

/// Notify the Witnesses and revoke calendar grants, side by side. Resolves
/// 'done' whatever happens inside — it never rejects.
async function courtesySteps(admin: SupabaseClient, supabaseUrl: string, userId: string): Promise<'done'> {
  try {
    const notify = (async () => {
      // service-role reads, so this still works even if a future RLS change
      // narrows a plain user's own read access.
      const [profile, pairings] = await Promise.all([
        admin.from('profiles').select('name').eq('id', userId).maybeSingle(),
        admin
          .from('witness_pairings')
          .select('witness_id')
          .eq('runner_id', userId)
          .eq('status', 'active')
          .limit(MAX_WITNESSES),
      ]);
      if (profile.error) console.error('delete-account: profile lookup failed:', describeError(profile.error));
      if (pairings.error) {
        console.error(
          'delete-account: pairing lookup failed; Witnesses will not be notified:',
          describeError(pairings.error),
        );
      }
      const name = profile.data?.name;
      const runnerName = typeof name === 'string' && name.trim().length > 0
        ? name.trim().slice(0, 60)
        : 'A Runner you walk with';
      const witnessIds = ((pairings.data ?? []) as Array<{ witness_id: unknown }>)
        .map((pairing) => pairing.witness_id)
        .filter(isUuid);
      await notifyWitnesses(supabaseUrl, userId, runnerName, witnessIds);
    })();

    const results = await Promise.allSettled([notify, revokeCalendarGrants(admin, userId)]);
    for (const result of results) {
      if (result.status === 'rejected') {
        console.error('delete-account: a courtesy step failed (continuing):', describeError(result.reason));
      }
    }
  } catch (error) {
    console.error('delete-account: a courtesy step failed (continuing):', describeError(error));
  }
  return 'done';
}

async function handle(req: Request): Promise<Response> {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return methodNotAllowed('POST, OPTIONS');

  // Who is asking — from their own verified session. The request body is
  // never read: there is nothing in it this function would trust.
  const caller = await authenticate(req, { adminTimeoutMs: DELETE_TIMEOUT_MS });
  if (caller instanceof Response) return caller;
  const { userId, admin } = caller;

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';

  // ---- Courtesy steps: best effort, time-boxed, never fatal -------------------
  // Whatever happens in here (slow push engine, slow Cronofy, slow lookups),
  // the deletion below starts no later than COURTESY_BUDGET_MS from now.
  let timer: ReturnType<typeof setTimeout> | undefined;
  const budget = new Promise<'timeout'>((resolve) => {
    timer = setTimeout(() => resolve('timeout'), COURTESY_BUDGET_MS);
  });
  const outcome = await Promise.race([courtesySteps(admin, supabaseUrl, userId), budget]);
  clearTimeout(timer);
  if (outcome === 'timeout') {
    console.error('delete-account: courtesy steps ran out of time; continuing with the deletion.');
  }

  // ---- The deletion itself ------------------------------------------------------
  try {
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error('delete-account: deleteUser failed:', describeError(deleteError));
      return errorResponse(500, 'delete_failed', 'We could not delete your account right now. Please try again.');
    }
  } catch (error) {
    console.error('delete-account: deleteUser threw:', describeError(error));
    return errorResponse(500, 'delete_failed', 'We could not delete your account right now. Please try again.');
  }

  return jsonResponse(200, { deleted: true });
}

Deno.serve(guarded('delete-account', handle));
