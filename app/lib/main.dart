import 'package:fade_call/app.dart';
import 'package:fade_call/data/session_store.dart';
import 'package:fade_call/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SessionStore store;
  try {
    store = await PrefsSessionStore.create();
  } on Object {
    // Private browsing can block storage; keep the session in memory.
    store = MemorySessionStore();
  }

  runApp(
    ProviderScope(
      // Model calls are slow and not idempotent; screens offer "Try again".
      retry: (_, _) => null,
      overrides: [sessionStoreProvider.overrideWithValue(store)],
      child: const FadeCallApp(),
    ),
  );
}
