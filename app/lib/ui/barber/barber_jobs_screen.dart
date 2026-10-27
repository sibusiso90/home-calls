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

class BarberJobsScreen extends ConsumerWidget {
  const BarberJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    final barber = ref.watch(myBarberProvider).value;
    final requests = barber?.status == BarberStatus.approved
        ? ref.watch(requestsProvider).value ?? const <HomeCallRequest>[]
        : const <HomeCallRequest>[];
    final banner = switch (barber?.status) {
      BarberStatus.onboarding => const Callout(
        icon: Icons.badge_outlined,
        title: 'Finish getting verified',
        text:
            'Record your voice profile and add 5 before/after pairs to be graded.',
      ),
      BarberStatus.pendingApproval => Callout.warning(
        context,
        'You will start getting bookings once an operator approves you.',
        title: 'Awaiting approval',
      ),
      _ => null,
    };

    return Scaffold(
      appBar: const FadeAppBar(title: 'Jobs'),
      body: AsyncView(
        value: jobs,
        onRetry: () => ref.invalidate(jobsProvider),
        loadingMessage: 'Loading your jobs…',
        builder: (list) => PageList(
          onRefresh: () {
            ref.invalidate(requestsProvider);
            return ref.refresh(jobsProvider.future);
          },
          children: [
            if (requests.isNotEmpty) ...[
              SectionHeader(title: 'New requests (${requests.length})'),
              for (final r in requests) ...[
                BarberRequestCard(request: r),
                const SizedBox(height: Gap.sm + 4),
              ],
              const SectionHeader(title: 'Your jobs'),
            ],
            if (banner != null) ...[
              banner,
              if (barber?.status == BarberStatus.onboarding)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go(Routes.barberProfile),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Continue onboarding'),
                  ),
                ),
              const SizedBox(height: Gap.md),
            ],
            if (list.isEmpty && requests.isEmpty)
              const MessageView(
                icon: Icons.event_available_outlined,
                title: 'No jobs yet',
                message:
                    'When a client asks for you, or for any barber nearby, the request shows up here.',
              )
            else
              for (final job in list) ...[
                JobListCard(
                  job: job,
                  counterpart: job.client.name,
                  onTap: () => context.go(Routes.barberJob(job.id)),
                ),
                const SizedBox(height: Gap.sm + 4),
              ],
          ],
        ),
      ),
    );
  }
}
