import 'dart:convert';

import 'package:fade_call/data/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the demo session and per-user consent flags.
abstract interface class SessionStore {
  Session? read();
  Future<void> write(Session? session);
  bool hasConsent(String key);
  Future<void> setConsent(String key);
}

final class PrefsSessionStore implements SessionStore {
  PrefsSessionStore._(this._prefs);

  static const _sessionKey = 'fadecall.session';
  static const _consentPrefix = 'fadecall.consent.';

  static Future<PrefsSessionStore> create() async => PrefsSessionStore._(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    ),
  );

  final SharedPreferencesWithCache _prefs;

  @override
  Session? read() {
    final raw = _prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      return Session.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Session? session) => session == null
      ? _prefs.remove(_sessionKey)
      : _prefs.setString(_sessionKey, jsonEncode(session.toJson()));

  @override
  bool hasConsent(String key) => _prefs.getBool('$_consentPrefix$key') ?? false;

  @override
  Future<void> setConsent(String key) =>
      _prefs.setBool('$_consentPrefix$key', true);
}

/// In-memory store for tests and as a fallback when storage is unavailable.
final class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  Session? _session;
  final _consents = <String>{};

  @override
  Session? read() => _session;

  @override
  Future<void> write(Session? session) async => _session = session;

  @override
  bool hasConsent(String key) => _consents.contains(key);

  @override
  Future<void> setConsent(String key) async => _consents.add(key);
}
