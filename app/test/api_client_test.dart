import 'dart:convert';
import 'dart:typed_data';

import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/http_fade_call_api.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

void main() {
  test('sends bearer token and parses the response', () async {
    late http.Request seen;
    final api = HttpFadeCallApi(
      baseUrl: 'http://api.test',
      token: () => 'tok-1',
      client: MockClient((r) async {
        seen = r;
        return _json(barberJson, 200);
      }),
    );
    final b = await api.myBarber();
    expect(b.name, 'Thabo M');
    expect(seen.url.toString(), 'http://api.test/barbers/me');
    expect(seen.headers['Authorization'], 'Bearer tok-1');
  });

  test('maps the error envelope to ApiException', () async {
    var expired = false;
    final api = HttpFadeCallApi(
      baseUrl: 'http://api.test',
      token: () => 't',
      onUnauthorized: () => expired = true,
      client: MockClient(
        (r) async => _json(
          jsonEncode({
            'error': {'code': 'verdict_required', 'message': 'Not verified'},
          }),
          409,
        ),
      ),
    );
    await expectLater(
      api.rate('j-1', stars: 5),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'verdict_required')
            .having((e) => e.message, 'message', 'Not verified')
            .having((e) => e.isVerdictRequired, 'isVerdictRequired', isTrue),
      ),
    );
    expect(expired, isFalse);
  });

  test('401 triggers onUnauthorized', () async {
    var expired = false;
    final api = HttpFadeCallApi(
      baseUrl: 'http://api.test',
      token: () => 't',
      onUnauthorized: () => expired = true,
      client: MockClient(
        (r) async => _json(
          '{"error": {"code": "unauthorized", "message": "Sign in again"}}',
          401,
        ),
      ),
    );
    await expectLater(api.jobs(), throwsA(isA<ApiException>()));
    expect(expired, isTrue);
  });

  test('proof upload sends capture metadata as multipart fields', () async {
    late String body;
    final api = HttpFadeCallApi(
      baseUrl: 'http://api.test',
      token: () => 't',
      client: MockClient((r) async {
        body = r.body;
        expect(r.url.path, '/jobs/j-1/proof/after');
        return _json(evidenceNeedsReviewJson, 200);
      }),
    );
    final e = await api.uploadProof(
      jobId: 'j-1',
      after: true,
      photo: UploadFile(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'after.jpg',
        mimeType: 'image/jpeg',
      ),
      meta: CaptureMeta(
        capturedAt: DateTime(2026, 10, 28, 16, 48),
        mode: CaptureMode.uploadFallback,
      ),
    );
    expect(e.verdict, Verdict.needsReview);
    expect(body, contains('name="capture_mode"\r\n\r\nupload_fallback'));
    expect(body, contains('name="captured_at"'));
    expect(body, isNot(contains('name="lat"')));
    expect(body, contains('filename="after.jpg"'));
  });

  test('mediaUrl resolves relative signed paths against the base', () {
    final api = HttpFadeCallApi(baseUrl: 'http://api.test', token: () => null);
    expect(
      api.mediaUrl('/media/k?exp=1&sig=a'),
      'http://api.test/media/k?exp=1&sig=a',
    );
    expect(api.mediaUrl('https://cdn/x'), 'https://cdn/x');
  });
}

http.Response _json(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json'},
);
