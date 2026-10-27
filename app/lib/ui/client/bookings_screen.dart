import 'package:fade_call/core/theme.dart';
import 'package:fade_call/data/models/models.dart';
import 'package:fade_call/router.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/common.dart';
import 'package:fade_call/ui/widgets/fade_app_bar.dart';
import 'package:fade_call/ui/widgets/job_widgets.dart';
import 'package:fade_call/ui/widgets/request_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    // Open requests first, then any that ended without a booking in the last day.
    final requests = [
      for (final r
          in ref.watch(requestsProvider).value ?? const <HomeCallRequest>[])
        if (r.isOpen ||
            (r.jobId == null &&
                DateTime.now().difference(r.createdAt ?? DateTime(0)).inHours <
                    24))
          r,
    ];
    return Scaffold(
      appBar: const FadeAppBar(title: 'My bookings'),
      body: AsyncView(
        value: jobs,
        onRetry: () => ref.invalidate(jobsProvider),
        loadingMessage: 'Loading your bookings…',
        isEmpty: (list) => list.isEmpty && requests.isEmpty,
        empty: MessageView(
          icon: Icons.calendar_month_outlined,
          title: 'No bookings yet',
          message: 'Get a quote to see verified barbers near you.',
          action: FilledButton(
            onPressed: () => context.go(Routes.clientQuote),
            child: const Text('Get a quote'),
          ),
        ),
        builder: (list) => PageList(
          onRefresh: () {
            ref.invalidate(requestsProvider);
            return ref.refresh(jobsProvider.future);
          },
          children: [
            if (requests.isNotEmpty) ...[
              const SectionHeader(title: 'Requests'),
              for (final r in requests) ...[
                ClientRequestCard(request: r),
                const SizedBox(height: Gap.sm + 4),
              ],
              if (list.isNotEmpty) const SectionHeader(title: 'Bookings'),
            ],
            for (final job in list) ...[
              JobListCard(
                job: job,
                counterpart: job.barber.name,
                onTap: () => context.go(Routes.clientJob(job.id)),
              ),
              const SizedBox(height: Gap.sm + 4),
            ],
          ],
        ),
      ),
    );
  }
}
