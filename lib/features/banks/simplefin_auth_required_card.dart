import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/services/simplefin/simplefin_client.dart';
import 'package:spend_trends/services/simplefin/simplefin_models.dart';
import 'package:url_launcher/url_launcher.dart';

final acknowledgedSimpleFinAuthBanksProvider =
    NotifierProvider<AcknowledgedSimpleFinAuthBanks, Set<String>>(
      AcknowledgedSimpleFinAuthBanks.new,
    );

class AcknowledgedSimpleFinAuthBanks() extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void acknowledge(Iterable<String> bankNames) {
    state = {...state, for (final name in bankNames) name.toLowerCase()};
  }
}

/// One card for every bank SimpleFIN refused to sign in to.
class const SimpleFinAuthRequiredCard({
  required final List<SimpleFinError> errors,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acknowledged = ref.watch(acknowledgedSimpleFinAuthBanksProvider);
    final names = [
      for (final name in SimpleFinAuthConnections.fromErrors(errors).names)
        if (!acknowledged.contains(name.toLowerCase())) name,
    ];
    if (names.isEmpty) return const SizedBox.shrink();
    return EErrorCard(
      title: 'Auth required',
      body: _credentialsBody(names),
      actions: [
        TextButton(
          onPressed: () => ref
              .read(acknowledgedSimpleFinAuthBanksProvider.notifier)
              .acknowledge(names),
          child: const Text('Acknowledge'),
        ),
        TextButton(
          onPressed: () {
            launchUrl(
              Uri.parse(simpleFinBridgeUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          child: const Text('Open SimpleFIN'),
        ),
      ],
    );
  }

  Widget _credentialsBody(List<String> names) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SimpleFIN requires you to fix your credentials for:',
          style: EText.body.medium,
        ),
        const SizedBox(height: ELayout.spaceXs),
        for (var index = 0; index < names.length; index++)
          Text('${index + 1}. ${names[index]}', style: EText.body.medium),
        const SizedBox(height: ELayout.spaceSm),
        Text(
          'After you fix them, press Pull bank transactions again.',
          style: EText.body.medium,
        ),
      ],
    );
  }
}
