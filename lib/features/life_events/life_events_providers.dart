import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/services/sqlite/life_events_repository.dart';

final lifeEventsProvider = FutureProvider<List<LifeEvent>>((ref) async {
  ref.watch(spendDataChangedProvider);
  final repository = await ref.watch(lifeEventsRepositoryProvider.future);
  return repository.listNewestFirst();
});
