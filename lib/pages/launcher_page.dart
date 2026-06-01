import 'package:flutter/material.dart';

import '../state/photo_booth_config.dart';

class LauncherPage extends StatelessWidget {
  const LauncherPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    final List<_LauncherAction> actions = <_LauncherAction>[
      const _LauncherAction('Enter Booth', '/booth', Icons.photo_camera_front),
      const _LauncherAction('Settings', '/settings', Icons.settings),
      const _LauncherAction('Crop', '/crop', Icons.crop),
      const _LauncherAction('Frames', '/frames', Icons.border_style),
      const _LauncherAction('Filters', '/filters', Icons.auto_fix_high),
      const _LauncherAction(
          'Session Re-Print', '/session-reprint', Icons.print),
      const _LauncherAction('Uploads', '/uploads', Icons.cloud_upload),
      const _LauncherAction('Setup Wizard', '/wizard', Icons.auto_awesome),
      const _LauncherAction(
          'Custom Appearance', '/appearance', Icons.palette_outlined),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF0F2940), Color(0xFF1E4A73)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0x33F1C24C),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('Luminash Booth Prototype'),
                        ),
                        const Spacer(),
                        Text(
                          'Photo booth launcher for event workflow.',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Quick access to booth capture, frame presets, filters, crop tuning, and setup pages.',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            _InfoChip(
                              icon: Icons.filter_alt,
                              label: config.filter.label,
                            ),
                            _InfoChip(
                              icon: Icons.border_outer,
                              label: config.frame.name,
                            ),
                            _InfoChip(
                              icon: Icons.timer,
                              label: '${config.countdownSeconds}s countdown',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: ListView.separated(
                  itemCount: actions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final _LauncherAction action = actions[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2),
                          child: Icon(action.icon,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        title: Text(action.label),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () =>
                            Navigator.of(context).pushNamed(action.route),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LauncherAction {
  const _LauncherAction(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
