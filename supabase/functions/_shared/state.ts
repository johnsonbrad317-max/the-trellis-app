// Signed OAuth `state` values.
//
// state = "<nonce>.<base64url(HMAC-SHA256(CALENDAR_STATE_SECRET, nonce))>"
//
// The nonce is also a single-use row in calendar_oauth_states (which knows the
// user and provider), so a callback is accepted only if (1) the signature
// verifies, proving WE issued this state, and (2) the nonce is unused and
// unexpired. The user id is deliberately not in the state: it comes from the
// database row, never from the URL.

const encoder = new TextEncoder();

function toBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64Url(text: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(text)) return null;
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (text.length % 4)) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch (_) {
    return null;
  }
}

async function hmacKey(secret: string, usage: 'sign' | 'verify'): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    [usage],
  );
}

const NONCE_RE = /^[A-Za-z0-9]{16,128}$/;
// HMAC-SHA256 is 32 bytes = exactly 43 base64url characters (unpadded).
const SIGNATURE_RE = /^[A-Za-z0-9_-]{43}$/;

/// The state-signing secret is missing. Callers answer `not_configured`.
export class StateSecretMissingError extends Error {
  constructor() {
    super('CALENDAR_STATE_SECRET is not set');
    this.name = 'StateSecretMissingError';
  }
}

export function isStateSecretConfigured(): boolean {
  return Boolean(Deno.env.get('CALENDAR_STATE_SECRET'));
}

/// Throws StateSecretMissingError if CALENDAR_STATE_SECRET is not configured
/// (fails closed: with no secret nothing can be signed or verified).
function stateSecret(): string {
  const secret = Deno.env.get('CALENDAR_STATE_SECRET');
  if (!secret) throw new StateSecretMissingError();
  return secret;
}

export async function signState(nonce: string): Promise<string> {
  if (!NONCE_RE.test(nonce)) throw new RangeError('Nonce has an unexpected shape');
  const key = await hmacKey(stateSecret(), 'sign');
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(nonce)));
  return `${nonce}.${toBase64Url(sig)}`;
}

/// Returns the nonce if the state is well-formed and its signature verifies,
/// otherwise null. (crypto.subtle.verify compares in constant time.) Pure
/// computation — no network call — so it is safe to run on any unauthenticated
/// request before anything else happens. Throws only StateSecretMissingError.
export async function verifyState(state: unknown): Promise<string | null> {
  const secret = stateSecret();
  if (typeof state !== 'string' || state.length > 512) return null;
  const parts = state.split('.');
  if (parts.length !== 2) return null;
  const [nonce, sigText] = parts;
  if (!NONCE_RE.test(nonce) || !SIGNATURE_RE.test(sigText)) return null;
  const sig = fromBase64Url(sigText);
  if (!sig || sig.length !== 32) return null;

  try {
    const key = await hmacKey(secret, 'verify');
    const ok = await crypto.subtle.verify('HMAC', key, sig, encoder.encode(nonce));
    return ok ? nonce : null;
  } catch (_) {
    return null;
  }
}
