// Kept for backwards compatibility: the CORS + JSON helpers now live in
// ./http.ts together with the rest of the shared HTTP plumbing (error shape,
// body limits, timeouts). Import from './http.ts' in new code.

export { corsHeaders, handlePreflight, jsonResponse } from './http.ts';
