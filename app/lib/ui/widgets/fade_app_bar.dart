import 'package:fade_call/core/theme.dart';
import 'package:fade_call/state/providers.dart';
import 'package:fade_call/ui/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows "Mock models" when the backend runs without a model API key.
class MockBadge extends ConsumerWidget {
  const MockBadge({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider).value;
    if (health == null || !health.isMock) return const SizedBox.shrink();
    return Tooltip(
      message:
          'The backend is running without a model API key. Results are mocked.',
      child: DecoratedBox(
        key: const ValueKey('mock-badge'),
        decoration: BoxDecoration(
          color: onDark ? Palette.brass : Palette.brassSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.brass),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.science_outlined,
                size: 14,
                color: Palette.charcoal,
              ),
              const SizedBox(width: 4),
              Text(
                'Mock models',
                style: context.text.labelSmall?.copyWith(
                  color: Palette.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App bar with the mock badge and an account menu.
class FadeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const FadeAppBar({required this.title, super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)?.user;
    return AppBar(
      title: Text(title),
      actions: [
        const Center(child: MockBadge()),
        ...actions,
        if (user != null) const NotificationBell(),
        if (user != null)
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: Palette.forest,
              child: Text(
                user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                style: context.text.labelLarge?.copyWith(color: Palette.cream),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: context.text.titleSmall),
                    Text(
                      '${user.role.label} · ${user.phone}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(sessionProvider.notifier).logout().ignore();
              }
            },
          ),
        const SizedBox(width: Gap.sm),
      ],
    );
  }
}
