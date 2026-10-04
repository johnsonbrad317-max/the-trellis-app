// Deno tests for rate_limit.ts. Run with:
//   deno test supabase/functions/_shared/rate_limit_test.ts
// (Executed under Node 24 type-stripping with `Deno.test` / `assertEquals`
// shimmed — see availability_test.ts. Not run under Deno itself.)

import { assertEquals } from 'jsr:@std/assert@1';
import { checkRateLimits, type RateLimit, rateLimitedResponse, type RpcClient } from './rate_limit.ts';

const limits: RateLimit[] = [
  { name: 'minute', limit: 6, windowSeconds: 60 },
  { name: 'hour', limit: 40, windowSeconds: 3600 },
];

type Reply = { data: unknown; error: { message?: string; code?: string } | null };

/// A fake database: replies come from `reply(key)` and every call is recorded.
function fakeClient(reply: (key: string) => Reply | Promise<Reply>) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const client: RpcClient = {
    async rpc(fn, args) {
      calls.push({ fn, args });
      return await reply(String(args.p_key));
    },
  };
  return { client, calls };
}

const ok = (): Reply => ({ data: [{ allowed: true, current_hits: 1, retry_after_seconds: 0 }], error: null });
const blocked = (seconds: number): Reply => ({
  data: [{ allowed: false, current_hits: 7, retry_after_seconds: seconds }],
  error: null,
});

Deno.test('allows when every window is within its limit, checking each in order', async () => {
  const { client, calls } = fakeClient(ok);
  assertEquals(await checkRateLimits(client, 'calendar-availability', 'u1', limits), { allowed: true });
  assertEquals(calls.map((c) => c.args.p_key), [
    'calendar-availability:u1:minute',
    'calendar-availability:u1:hour',
  ]);
  assertEquals(calls[0].fn, 'edge_rate_limit_hit');
  assertEquals(calls[0].args.p_limit, 6);
  assertEquals(calls[0].args.p_window_seconds, 60);
});

Deno.test('stops at the first exceeded window and reports its retry time', async () => {
  const { client, calls } = fakeClient((key) => (key.endsWith(':minute') ? blocked(23) : ok()));
  assertEquals(
    await checkRateLimits(client, 'calendar-availability', 'u1', limits),
    { allowed: false, retryAfterSeconds: 23 },
  );
  assertEquals(calls.length, 1, 'the hour window is not consulted once the minute is blocked');
});

Deno.test('the hour window can block on its own', async () => {
  const { client } = fakeClient((key) => (key.endsWith(':hour') ? blocked(1800) : ok()));
  assertEquals(
    await checkRateLimits(client, 'calendar-availability', 'u1', limits),
    { allowed: false, retryAfterSeconds: 1800 },
  );
});

Deno.test('users do not share a count', async () => {
  const { client, calls } = fakeClient(ok);
  await checkRateLimits(client, 's', 'alice', limits.slice(0, 1));
  await checkRateLimits(client, 's', 'bob', limits.slice(0, 1));
  assertEquals(calls.map((c) => c.args.p_key), ['s:alice:minute', 's:bob:minute']);
});

Deno.test('a single (non-array) row from the database is understood', async () => {
  const { client } = fakeClient(() => ({
    data: { allowed: false, current_hits: 9, retry_after_seconds: 5 },
    error: null,
  }));
  assertEquals(await checkRateLimits(client, 's', 'u', limits), { allowed: false, retryAfterSeconds: 5 });
});

Deno.test('a missing or nonsense retry time falls back to the window length', async () => {
  for (const retry of [undefined, null, 0, -4, 'soon', Number.NaN]) {
    const { client } = fakeClient(() => ({
      data: [{ allowed: false, current_hits: 9, retry_after_seconds: retry }],
      error: null,
    }));
    assertEquals(
      await checkRateLimits(client, 's', 'u', limits),
      { allowed: false, retryAfterSeconds: 60 },
    );
  }
});

Deno.test('fails open when the limiter errors, returns nothing, or throws', async () => {
  const cases: Array<() => Reply | Promise<Reply>> = [
    () => ({ data: null, error: { code: '42883', message: 'function does not exist' } }),
    () => ({ data: [], error: null }),
    () => ({ data: null, error: null }),
    () => {
      throw new Error('network down');
    },
  ];
  for (const reply of cases) {
    const { client } = fakeClient(reply);
    assertEquals(await checkRateLimits(client, 's', 'u', limits), { allowed: true });
  }
});

Deno.test('a row that does not say allowed=false is treated as allowed', async () => {
  const { client } = fakeClient(() => ({ data: [{ current_hits: 2 }], error: null }));
  assertEquals(await checkRateLimits(client, 's', 'u', limits), { allowed: true });
});

Deno.test('the 429 carries the standard error shape, retry time and header', async () => {
  const response = rateLimitedResponse(42, 'Slow down.');
  assertEquals(response.status, 429);
  assertEquals(response.headers.get('Retry-After'), '42');
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), '*');
  assertEquals(await response.json(), {
    error: 'Slow down.',
    code: 'rate_limited',
    retry_after_seconds: 42,
  });
});
