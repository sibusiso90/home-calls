import 'dart:async';
import 'dart:convert';

import 'package:fade_call/data/api_exception.dart';
import 'package:fade_call/data/fade_call_api.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// [FadeCallApi] over HTTP, mapping the error envelope to [ApiException].
final class HttpFadeCallApi implements FadeCallApi {
  HttpFadeCallApi({
    required String baseUrl,
    required this._token,
    this._onUnauthorized,
    http.Client? client,
  }) : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _client = client ?? http.Client();

  final Uri _base;
  final String? Function() _token;
  final void Function()? _onUnauthorized;
  final http.Client _client;

  /// Model calls can take ~30 s; leave headroom.
  static const _timeout = Duration(seconds: 90);

  Uri _uri(String path, [Map<String, String>? query]) {
    final resolved = _base.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
    return query == null || query.isEmpty
        ? resolved
        : resolved.replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = false}) => {
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (_token() case final t?) 'Authorization': 'Bearer $t',
  };

  Future<Object?> _send(Future<http.BaseResponse> Function() request) async {
    final http.Response response;
    try {
      final raw = await request().timeout(_timeout);
      response = switch (raw) {
        final http.Response r => r,
        final http.StreamedResponse s => await http.Response.fromStream(s),
        _ => throw StateError('Unexpected response type'),
      };
    } on TimeoutException {
      throw const ApiException.network(
        'This is taking longer than expected. Please try again.',
      );
    } on http.ClientException catch (e) {
      throw ApiException.network(
        e.message.isEmpty ? null : "We couldn't reach Fade Call. ${e.message}",
      );
    }

    // Always UTF-8: the backend sends JSON and reasons contain en dashes etc.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final body = text.isEmpty ? null : _decode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    final error = switch (body) {
      {'error': {'code': final String code, 'message': final String message}} =>
        ApiException(code, message, statusCode: response.statusCode),
      {'detail': final Object detail} => ApiException(
        _codeFor(response.statusCode),
        '$detail',
        statusCode: response.statusCode,
      ),
      _ => ApiException(
        _codeFor(response.statusCode),
        'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      ),
    };
    if (error.isUnauthorized) _onUnauthorized?.call();
    throw error;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String _codeFor(int status) => switch (status) {
    401 => 'unauthorized',
    403 => 'forbidden',
    404 => 'not_found',
    409 => 'conflict',
    422 => 'validation',
    502 => 'model_error',
    _ => 'error',
  };

  Future<Object?> _get(String path, [Map<String, String>? query]) =>
      _send(() => _client.get(_uri(path, query), headers: _headers()));

  Future<Object?> _post(String path, [Object? body]) => _send(
    () => _client.post(
      _uri(path),
      headers: _headers(json: true),
      body: body == null ? null : jsonEncode(body),
    ),
  );

  Future<Object?> _put(String path, Object body) => _send(
    () => _client.put(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    ),
  );

  Future<Object?> _delete(String path) =>
      _send(() => _client.delete(_uri(path), headers: _headers()));

  Future<Object?> _multipart(
    String path, {
    Map<String, UploadFile> files = const {},
    Map<String, String> fields = const {},
  }) => _send(() {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers())
      ..fields.addAll(fields);
    for (final MapEntry(:key, :value) in files.entries) {
      request.files.add(
        http.MultipartFile.fromBytes(
          key,
          value.bytes,
          filename: value.filename,
          contentType: MediaType.parse(value.mimeType),
        ),
      );
    }
    return _client.send(request);
  });

  static Json _obj(Object? body) => (body! as Map).cast<String, dynamic>();

  static List<T> _list<T>(Object? body, T Function(Json) parse) =>
      ((body as List?) ?? const [])
          .map((e) => parse((e as Map).cast<String, dynamic>()))
          .toList();

  @override
  String mediaUrl(String url) =>
      url.startsWith('http') ? url : _uri(url).toString();

  @override
  Future<Health> health() async => Health.fromJson(_obj(await _get('/health')));

  @override
  Future<Session> demoLogin({
    required Role role,
    required String name,
    required String phone,
    String? passcode,
  }) async => Session.fromJson(
    _obj(
      await _post('/auth/demo-login', {
        'role': role.name,
        'name': name,
        'phone': phone,
        'passcode': passcode,
      }),
    ),
  );

  @override
  Future<AppUser> me() async => AppUser.fromJson(_obj(await _get('/me')));

  @override
  Future<List<Area>> areas() async =>
      _list(await _get('/areas'), Area.fromJson);

  @override
  Future<Barber> myBarber() async =>
      Barber.fromJson(_obj(await _get('/barbers/me')));

  @override
  Future<VoiceNoteResult> uploadVoiceNote(UploadFile audio) async =>
      VoiceNoteResult.fromJson(
        _obj(
          await _multipart('/barbers/me/voice-note', files: {'audio': audio}),
        ),
      );

  @override
  Future<Barber> confirmProfile(BarberProfile profile) async => Barber.fromJson(
    _obj(await _put('/barbers/me/profile', profile.toJson())),
  );

  @override
  Future<PortfolioItem> addPortfolioItem({
    required UploadFile before,
    required UploadFile after,
  }) async => PortfolioItem.fromJson(
    _obj(
      await _multipart(
        '/barbers/me/portfolio',
        files: {'before': before, 'after': after},
      ),
    ),
  );

  @override
  Future<void> deletePortfolioItem(String id) =>
      _delete('/barbers/me/portfolio/${Uri.encodeComponent(id)}');

  @override
  Future<GradeResult> grade() async =>
      GradeResult.fromJson(_obj(await _post('/barbers/me/grade')));

  @override
  Future<List<Cut>> cuts() async => _list(await _get('/cuts'), Cut.fromJson);

  @override
  Future<Quote> createQuote({
    required UploadFile selfie,
    required String areaId,
    UploadFile? reference,
    String? cutId,
  }) async => Quote.fromJson(
    _obj(
      await _multipart(
        '/quotes',
        files: {'selfie': selfie, 'reference': ?reference},
        fields: {'area_id': areaId, 'cut_id': ?cutId},
      ),
    ),
  );

  @override
  Future<Quote> requote(String quoteId, String cutId) async => Quote.fromJson(
    _obj(
      await _post('/quotes/${Uri.encodeComponent(quoteId)}/requote', {
        'cut_id': cutId,
      }),
    ),
  );

  @override
  Future<HomeCallRequest> createRequest({
    required String quoteId,
    required DateTime day,
    required List<TimeWindow> windows,
    required String address,
    required double lat,
    required double lng,
    String? barberId,
  }) async => HomeCallRequest.fromJson(
    _obj(
      await _post('/requests', {
        'quote_id': quoteId,
        'day': _date(day),
        'windows': [for (final w in windows) w.name],
        'address': address,
        'lat': lat,
        'lng': lng,
        'barber_id': barberId,
      }),
    ),
  );

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<HomeCallRequest>> requests() async =>
      _list(await _get('/requests'), HomeCallRequest.fromJson);

  @override
  Future<HomeCallRequest> request(String id) async => HomeCallRequest.fromJson(
    _obj(await _get('/requests/${Uri.encodeComponent(id)}')),
  );

  @override
  Future<Job> acceptRequest(String id, {required DateTime slotStart}) async =>
      Job.fromJson(
        _obj(
          await _post('/requests/${Uri.encodeComponent(id)}/accept', {
            'slot_start': isoWithOffset(slotStart),
          }),
        ),
      );

  @override
  Future<void> declineRequest(String id) async {
    await _post('/requests/${Uri.encodeComponent(id)}/decline');
  }

  @override
  Future<HomeCallRequest> cancelRequest(String id) async =>
      HomeCallRequest.fromJson(
        _obj(await _post('/requests/${Uri.encodeComponent(id)}/cancel')),
      );

  @override
  Future<Quote> quote(String id) async =>
      Quote.fromJson(_obj(await _get('/quotes/${Uri.encodeComponent(id)}')));

  @override
  Future<List<BarberMatch>> matches(String quoteId) async => _list(
    await _get('/quotes/${Uri.encodeComponent(quoteId)}/matches'),
    BarberMatch.fromJson,
  );

  @override
  Future<Job> createJob({
    required String quoteId,
    required String barberId,
    required DateTime slotStart,
    required String address,
    required double lat,
    required double lng,
  }) async => Job.fromJson(
    _obj(
      await _post('/jobs', {
        'quote_id': quoteId,
        'barber_id': barberId,
        'slot_start': isoWithOffset(slotStart),
        'address': address,
        'lat': lat,
        'lng': lng,
      }),
    ),
  );

  @override
  Future<List<Job>> jobs() async => _list(await _get('/jobs'), Job.fromJson);

  @override
  Future<Job> job(String id) async =>
      Job.fromJson(_obj(await _get('/jobs/${Uri.encodeComponent(id)}')));

  @override
  Future<Job> confirmJob(String id) async => Job.fromJson(
    _obj(await _post('/jobs/${Uri.encodeComponent(id)}/confirm')),
  );

  @override
  Future<Job> payDeposit(String id) async => Job.fromJson(
    _obj(await _post('/jobs/${Uri.encodeComponent(id)}/pay-deposit')),
  );

  @override
  Future<Job> cancelJob(String id, {required String reason}) async =>
      Job.fromJson(
        _obj(
          await _post('/jobs/${Uri.encodeComponent(id)}/cancel', {
            'reason': reason,
          }),
        ),
      );

  @override
  Future<Job> rescheduleJob(String id, {required DateTime slotStart}) async =>
      Job.fromJson(
        _obj(
          await _post('/jobs/${Uri.encodeComponent(id)}/reschedule', {
            'slot_start': isoWithOffset(slotStart),
          }),
        ),
      );

  @override
  Future<List<DateTime>> barberSlots(
    String barberId, {
    int days = 7,
    int minutes = 45,
    String? excludeJobId,
  }) async {
    final body = _obj(
      await _get('/barbers/${Uri.encodeComponent(barberId)}/slots', {
        'days': '$days',
        'minutes': '$minutes',
        'exclude_job_id': ?excludeJobId,
      }),
    );
    return body.strings('slots').map(DateTime.parse).toList();
  }

  @override
  Future<NotificationInbox> notifications() async =>
      NotificationInbox.fromJson(_obj(await _get('/notifications')));

  @override
  Future<void> markNotificationRead(String id) =>
      _post('/notifications/${Uri.encodeComponent(id)}/read');

  @override
  Future<void> markAllNotificationsRead() => _post('/notifications/read-all');

  @override
  Future<Evidence> uploadProof({
    required String jobId,
    required bool after,
    required UploadFile photo,
    required CaptureMeta meta,
  }) async => Evidence.fromJson(
    _obj(
      await _multipart(
        '/jobs/${Uri.encodeComponent(jobId)}/proof/${after ? 'after' : 'before'}',
        files: {'photo': photo},
        fields: {
          'captured_at': isoWithOffset(meta.capturedAt),
          'capture_mode': meta.mode.wire,
          if (meta.lat case final lat?) 'lat': '$lat',
          if (meta.lng case final lng?) 'lng': '$lng',
          if (meta.accuracyM case final acc?)
            'accuracy_m': acc.toStringAsFixed(1),
        },
      ),
    ),
  );

  @override
  Future<void> rate(String jobId, {required int stars, String? comment}) =>
      _post('/jobs/${Uri.encodeComponent(jobId)}/rating', {
        'stars': stars,
        'comment': comment,
      });

  @override
  Future<Dispute> openDispute(
    String jobId, {
    UploadFile? audio,
    String? text,
  }) async => Dispute.fromJson(
    _obj(
      await _multipart(
        '/jobs/${Uri.encodeComponent(jobId)}/dispute',
        files: {'audio': ?audio},
        fields: {if (text != null && text.isNotEmpty) 'text': text},
      ),
    ),
  );

  @override
  Future<OpsSummary> opsSummary() async =>
      OpsSummary.fromJson(_obj(await _get('/ops/summary')));

  @override
  Future<List<Barber>> opsBarbers({
    String? status = 'pending_approval',
  }) async =>
      _list(await _get('/ops/barbers', {'status': ?status}), Barber.fromJson);

  @override
  Future<BarberDetail> opsBarber(String id) async => BarberDetail.fromJson(
    _obj(await _get('/ops/barbers/${Uri.encodeComponent(id)}')),
  );

  @override
  Future<void> approveBarber(String id, {required String reason}) => _post(
    '/ops/barbers/${Uri.encodeComponent(id)}/approve',
    {'reason': reason},
  );

  @override
  Future<void> rejectBarber(String id, {required String reason}) => _post(
    '/ops/barbers/${Uri.encodeComponent(id)}/reject',
    {'reason': reason},
  );

  @override
  Future<List<Job>> opsJobs({String? status = 'needs_review'}) async =>
      _list(await _get('/ops/jobs', {'status': ?status}), Job.fromJson);

  @override
  Future<void> opsVerdict(
    String jobId, {
    required bool pass,
    required String reason,
  }) => _post('/ops/jobs/${Uri.encodeComponent(jobId)}/verdict', {
    'verdict': pass ? 'pass' : 'fail',
    'reason': reason,
  });

  @override
  Future<Job> setConsentedDemo(String jobId, {required bool value}) async =>
      Job.fromJson(
        _obj(
          await _post(
            '/ops/jobs/${Uri.encodeComponent(jobId)}/consented-demo',
            {'consented_demo': value},
          ),
        ),
      );

  @override
  Future<List<Dispute>> opsDisputes() async =>
      _list(await _get('/ops/disputes'), Dispute.fromJson);

  @override
  Future<void> resolveDispute(
    String id, {
    required DisputeOutcome outcome,
    required String reason,
  }) => _post('/ops/disputes/${Uri.encodeComponent(id)}/resolve', {
    'outcome': outcome.wire,
    'reason': reason,
  });

  @override
  Future<List<Payout>> payouts() async =>
      _list(await _get('/ops/payouts'), Payout.fromJson);
}
