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
// The person's prayer photos (private `prayer-photos` storage bucket, folder
// `<user id>/` — migration 021) are removed here too, because deleting the
// account's database rows does not delete files in storage.
//
// What can NOT stop the deletion (Apple requires that deletion actually
// happens on request): a slow, failing or unconfigured push engine, a failed
// profile/pairing lookup, or a storage problem while removing photos. Each of
// those courtesy steps is best effort and strictly time-boxed
// (8 s per call, 12 s for all of it, run side by side), then the account is
// deleted regardless. (If photo removal fails, the files are left behind with
// no owner; 021's verification block has the query that finds them.)
//
// Contract with the app (lib/models/runner_profile.dart → deleteAccount):
//   200 { "deleted": true }           the account is gone
//   non-200 { "error", "code" }       it is NOT gone; safe to retry
//
// Secrets:
//   PUSH_ENGINE_WEBHOOK_SECRET   same value the push engine checks; without it
//                                Witnesses are simply not notified.
// (Calendar busy blocks — migration 025 — are plain rows that cascade away
// with the profile; there is no third-party grant to revoke any more.)
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically by the platform for every Edge Function.
//
// Deploy (JWT verification ON — the default):
//   supabase functions deploy delete-account
// =============================================================================

import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { authenticate } from '../_shared/auth.ts';
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

/// How long any single best-effort courtesy call (push engine, photo removal)
/// may take.
const COURTESY_TIMEOUT_MS = 8_000;
/// Hard ceiling on ALL the courtesy work together (lookups included); when it
/// runs out the deletion goes ahead without waiting any longer.
const COURTESY_BUDGET_MS = 12_000;
/// The delete itself cascades through the user's rows; give it room.
const DELETE_TIMEOUT_MS = 25_000;
/// Nobody has anywhere near this many Witnesses; it only bounds the fan-out.
const MAX_WITNESSES = 25;
/// Where prayer photos live (migration 021): `<user id>/<prayer item id>.jpg`.
const PHOTO_BUCKET = 'prayer-photos';
/// Photos are listed and removed this many at a time...
const PHOTO_PAGE_SIZE = 100;
/// ...for at most this many pages (1,000 photos), which only bounds the loop.
const PHOTO_MAX_PAGES = 10;

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

/// The kind of failure only ("StorageApiError", "TimeoutError") — never its
/// message, which can quote a path.
function errorClass(error: unknown): string {
  const name = (error as { name?: unknown } | null)?.name;
  return typeof name === 'string' && /^[A-Za-z]{1,40}$/.test(name) ? name : 'error';
}

/// Removes every object in the user's own folder of the prayer-photos bucket
/// (service role, so storage policies don't apply). Lists the whole folder
/// first, a page at a time, then removes in batches. Never throws: any storage
/// failure is logged by error class only and the rest is skipped.
async function removePrayerPhotos(admin: SupabaseClient, userId: string): Promise<void> {
  try {
    const bucket = admin.storage.from(PHOTO_BUCKET);

    const paths: string[] = [];
    for (let page = 0; page < PHOTO_MAX_PAGES; page++) {
      const { data, error } = await bucket.list(userId, {
        limit: PHOTO_PAGE_SIZE,
        offset: page * PHOTO_PAGE_SIZE,
        sortBy: { column: 'name', order: 'asc' },
      });
      if (error) {
        // Includes "bucket not found" on a project without migration 021 —
        // nothing to remove there.
        console.error('delete-account: could not list prayer photos (continuing):', errorClass(error));
        break;
      }
      const entries = (Array.isArray(data) ? data : []) as Array<{ name?: unknown; id?: unknown }>;
      for (const entry of entries) {
        // A null id is a sub-folder placeholder, not a file; the app never
        // creates one, and there is nothing to remove for it.
        if (typeof entry.name === 'string' && entry.name.length > 0 && entry.id !== null) {
          paths.push(`${userId}/${entry.name}`);
        }
      }
      if (entries.length < PHOTO_PAGE_SIZE) break;
    }

    let failedBatches = 0;
    let lastFailure = '';
    for (let start = 0; start < paths.length; start += PHOTO_PAGE_SIZE) {
      const { error } = await bucket.remove(paths.slice(start, start + PHOTO_PAGE_SIZE));
      if (error) {
        failedBatches++;
        lastFailure = errorClass(error);
      }
    }
    if (failedBatches > 0) {
      console.error(
        `delete-account: ${failedBatches} prayer photo removal batch(es) failed (continuing):`,
        lastFailure,
      );
    }
  } catch (error) {
    console.error('delete-account: prayer photo cleanup failed (continuing):', errorClass(error));
  }
}

/// Notify the Witnesses and remove prayer photos, side by side. Resolves
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

    const results = await Promise.allSettled([
      notify,
      removePrayerPhotos(admin, userId),
    ]);
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
