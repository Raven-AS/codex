import 'package:flutter/material.dart';

import '../domain/discovery_models.dart';

class DiscoveryPhoto extends StatelessWidget {
  const DiscoveryPhoto({super.key, required this.url, this.size = 56});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = url == null ? null : Uri.tryParse(url!);
    final usable =
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.person_outline, size: size * .6),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: usable
            ? Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

Future<void> showLawyerSummary(
  BuildContext context,
  DiscoveredLawyer lawyer, {
  VoidCallback? onConnections,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Lawyer summary'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              lawyer.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DiscoveryPhoto(url: lawyer.profilePhoto, size: 80),
            const SizedBox(height: 16),
            if (lawyer.professionalTitle?.trim().isNotEmpty == true)
              Text(lawyer.professionalTitle!),
            if (lawyer.yearsOfExperience != null)
              Text('${lawyer.yearsOfExperience} years of experience'),
            const SizedBox(height: 16),
            Text(
              lawyer.bio?.trim().isNotEmpty == true
                  ? lawyer.bio!
                  : 'No biography provided.',
            ),
            const SizedBox(height: 16),
            Text(
              'Practice areas',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (lawyer.practiceAreas.isEmpty)
              const Text('No practice areas listed.')
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final name in lawyer.practiceAreas)
                    Chip(label: Text(name)),
                ],
              ),
            if (lawyer.updatedAt != null) ...[
              const SizedBox(height: 16),
              Text('Profile updated: ${lawyer.updatedAt}'),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (onConnections != null)
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onConnections();
          },
          child: const Text('Lawyer connections'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class DiscoveryCard extends StatelessWidget {
  const DiscoveryCard({super.key, required this.lawyer, this.onConnections});
  final DiscoveredLawyer lawyer;
  final VoidCallback? onConnections;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          showLawyerSummary(context, lawyer, onConnections: onConnections),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DiscoveryPhoto(url: lawyer.profilePhoto),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lawyer.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (lawyer.professionalTitle?.trim().isNotEmpty == true)
                        Text(lawyer.professionalTitle!),
                      if (lawyer.yearsOfExperience != null)
                        Text('${lawyer.yearsOfExperience} years of experience'),
                    ],
                  ),
                ),
              ],
            ),
            if (lawyer.bio?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(lawyer.bio!, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            if (lawyer.practiceAreas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final name in lawyer.practiceAreas.take(3))
                    Chip(label: Text(name)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => showLawyerSummary(
                context,
                lawyer,
                onConnections: onConnections,
              ),
              child: const Text('View summary'),
            ),
          ],
        ),
      ),
    ),
  );
}
