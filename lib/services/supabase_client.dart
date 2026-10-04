import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Trellis's live Supabase project. The publishable (anon) key is safe
/// to ship in a client binary by design — it's Row-Level Security, not
/// secrecy, that protects the data (see supabase/migrations/init_schema.sql
/// and 011_security_lockdown.sql).
const _supabaseUrl = 'https://qonsiliimbkcjmcnhonb.supabase.co';
const _supabasePublishableKey = 'sb_publishable_xFFRtWf7381K4gK9aFlXPQ_sKNaTr8q';

/// How long any single request to Supabase (database, auth, Edge Functions)
/// may wait for a response before it fails. Edge Functions bound their own
/// third-party calls (Resend, Cronofy, FCM) at ~10s, so 30s is a ceiling the
/// server should always beat — it exists so a dead connection can never leave
/// a screen spinning forever.
const supabaseRequestTimeout = Duration(seconds: 30);

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
    httpClient: _TimeoutClient(http.Client(), supabaseRequestTimeout),
  );
}

/// Shorthand used throughout the data layer instead of the longer
/// `Supabase.instance.client` at every call site.
SupabaseClient get supabase => Supabase.instance.client;

/// An HTTP client that gives up on a request that has had no response within
/// [timeout], surfacing a [TimeoutException] — which every caller already
/// treats like any other network failure (a notice and a Retry, never a hang).
class _TimeoutClient extends http.BaseClient {
  _TimeoutClient(this._inner, this.timeout);

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(timeout);

  @override
  void close() => _inner.close();
}
