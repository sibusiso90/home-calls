import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/data/upload_file.dart';

/// Every endpoint in docs/api-contract.md. Screens depend on this interface
/// so tests can swap in a fake.
abstract interface class FadeCallApi {
  // Health and auth
  Future<Health> health();
  Future<Session> demoLogin({
    required Role role,
    required String name,
    required String phone,
    String? passcode,
  });
  Future<AppUser> me();

  // Reference data
  Future<List<Area>> areas();

  // Barber onboarding
  Future<Barber> myBarber();
  Future<VoiceNoteResult> uploadVoiceNote(UploadFile audio);
  Future<Barber> confirmProfile(BarberProfile profile);
  Future<PortfolioItem> addPortfolioItem({
    required UploadFile before,
    required UploadFile after,
  });
  Future<void> deletePortfolioItem(String id);
  Future<GradeResult> grade();

  // Client quote, match and book
  Future<List<Cut>> cuts();

  /// Quote from a [reference] photo, a catalog [cutId], or neither for a
  /// suggested cut.
  Future<Quote> createQuote({
    required UploadFile selfie,
    required String areaId,
    UploadFile? reference,
    String? cutId,
  });

  /// A new quote for a catalog cut with the same selfie as [quoteId].
  Future<Quote> requote(String quoteId, String cutId);
  Future<Quote> quote(String id);
  Future<List<BarberMatch>> matches(String quoteId);
  Future<Job> createJob({
    required String quoteId,
    required String barberId,
    required DateTime slotStart,
    required String address,
    required double lat,
    required double lng,
  });

  // Jobs
  Future<List<Job>> jobs();
  Future<Job> job(String id);
  Future<Job> confirmJob(String id);
  Future<Job> payDeposit(String id);

  Future<Job> cancelJob(String id, {required String reason});
  Future<Job> rescheduleJob(String id, {required DateTime slotStart});

  /// Free start times for a cut of [minutes]; [excludeJobId] is the booking
  /// being moved, so its own time counts as free.
  Future<List<DateTime>> barberSlots(
    String barberId, {
    int days = 7,
    int minutes = 45,
    String? excludeJobId,
  });

  // Notifications
  Future<NotificationInbox> notifications();
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();

  // Proof of job
  Future<Evidence> uploadProof({
    required String jobId,
    required bool after,
    required UploadFile photo,
    required CaptureMeta meta,
  });

  // Rating and disputes
  Future<void> rate(String jobId, {required int stars, String? comment});
  Future<Dispute> openDispute(String jobId, {UploadFile? audio, String? text});

  // Operator
  Future<OpsSummary> opsSummary();

  /// `status: null` lists every barber.
  Future<List<Barber>> opsBarbers({String? status = 'pending_approval'});
  Future<BarberDetail> opsBarber(String id);
  Future<void> approveBarber(String id, {required String reason});
  Future<void> rejectBarber(String id, {required String reason});

  /// `status: null` lists every job.
  Future<List<Job>> opsJobs({String? status = 'needs_review'});
  Future<void> opsVerdict(
    String jobId, {
    required bool pass,
    required String reason,
  });
  Future<Job> setConsentedDemo(String jobId, {required bool value});
  Future<List<Dispute>> opsDisputes();
  Future<void> resolveDispute(
    String id, {
    required DisputeOutcome outcome,
    required String reason,
  });
  Future<List<Payout>> payouts();

  /// Turns a contract media path (`/media/...`) into an absolute URL.
  String mediaUrl(String url);
}
