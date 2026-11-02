import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:spend_trends/agent_api/agent_api_json.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/domain/accounts/owned_asset.dart';
import 'package:spend_trends/data/sync/spend_data_changed.dart';
import 'package:spend_trends/data/repositories/life_events_repository.dart';
import 'package:spend_trends/data/repositories/owned_assets_repository.dart';

/// Life events (jobs, homes, children) the projection plans with, and the
/// owned assets (homes) net worth tracks: the same data the Projections and
/// Banks screens edit.
class const AgentApiLifePlanRoutes({
  required final ProviderContainer container,
}) {
  void mount(Router router) {
    router
      ..get('/life-events', _lifeEvents)
      ..post('/life-events', _saveLifeEvent)
      ..delete('/life-events/<eventId>', _deleteLifeEvent)
      ..get('/owned-assets', _ownedAssets)
      ..post('/owned-assets/<assetId>/valuations', _addValuation)
      ..patch(
        '/owned-assets/<assetId>/valuations/<valuationId>',
        _changeValuation,
      );
  }

  Future<LifeEventsRepository> _lifeEventsRepository() =>
      container.read(lifeEventsRepositoryProvider.future);

  /// Newest first, each with its kind's `details` (the stored JSON).
  Future<Response> _lifeEvents(Request request) async {
    final events = await (await _lifeEventsRepository()).listNewestFirst();
    return jsonOk({'lifeEvents': events.map(_lifeEventJson).toList()});
  }

  /// `{id?, kind, title, startedOn, endedOn?, note?, details?}`. Without
  /// `id` it creates the event; with one it replaces that event. `details`
  /// is the kind's JSON as `GET /life-events` shows it; missing fields take
  /// their defaults.
  Future<Response> _saveLifeEvent(Request request) async {
    final body = await request.readJsonObject();
    final repository = await _lifeEventsRepository();
    final kind = LifeEventKind.values.byName(body.requiredString('kind'));
    final event = LifeEvent.fromStorage(
      id: body['id'] as String? ?? repository.newId(),
      kind: kind,
      title: body.requiredString('title'),
      startedOn: DateTime.parse(body.requiredString('startedOn')),
      endedOn: switch (body['endedOn']) {
        final String endedOn => DateTime.parse(endedOn),
        _ => null,
      },
      note: body['note'] as String?,
      details: body['details'] as Map<String, dynamic>? ?? const {},
    );
    await repository.upsert(event);
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({'lifeEvent': _lifeEventJson(event)});
  }

  Future<Response> _deleteLifeEvent(Request request, String eventId) async {
    await (await _lifeEventsRepository()).delete(eventId);
    container.read(spendDataChangedProvider.notifier).notify();
    return jsonOk({'deleted': eventId});
  }

  /// Each asset with `soldOn` and its valuations, newest first.
  Future<Response> _ownedAssets(Request request) async {
    final List<OwnedAssetWithValuations> ownedAssets =
        await (await container.read(ownedAssetsRepositoryProvider.future))
            .listWithValuations();
    return jsonOk({
      'ownedAssets': [
        for (final ownedAsset in ownedAssets)
          {
            'id': ownedAsset.asset.id,
            'name': ownedAsset.asset.name,
            'kind': ownedAsset.asset.kind.name,
            'soldOn': ownedAsset.asset.soldOn?.isoDate,
            'note': ownedAsset.asset.note,
            'valuations': [
              for (final valuation in ownedAsset.valuations)
                {
                  'id': valuation.id,
                  'valuedOn': valuation.valuedOn.isoDate,
                  'valueCents': valuation.valueCents,
                },
            ],
          },
      ],
    });
  }

  /// `{valueCents, valuedOn}`. A home counts as 0 from its `soldOn`, so
  /// only valuations before the sale show in net worth.
  Future<Response> _addValuation(Request request, String assetId) async {
    final body = await request.readJsonObject();
    final repository = await container.read(
      ownedAssetsRepositoryProvider.future,
    );
    await _requireAsset(repository, assetId);
    await repository.appendValuation(
      ownedAssetId: assetId,
      valueCents: _requiredCents(body),
      valuedOn: DateTime.parse(body.requiredString('valuedOn')).calendarDay,
    );
    container.read(spendDataChangedProvider.notifier).notify();
    return _ownedAssets(request);
  }

  /// `{valueCents?, valuedOn?}`.
  Future<Response> _changeValuation(
    Request request,
    String assetId,
    String valuationId,
  ) async {
    final body = await request.readJsonObject();
    final repository = await container.read(
      ownedAssetsRepositoryProvider.future,
    );
    final ownedAsset = await _requireAsset(repository, assetId);
    final OwnedAssetValuation? valuation = ownedAsset.valuations
        .where((candidate) => candidate.id == valuationId)
        .firstOrNull;
    if (valuation == null) {
      return jsonError('No valuation $valuationId on $assetId', status: 404);
    }
    await repository.updateValuation(
      OwnedAssetValuation(
        id: valuation.id,
        ownedAssetId: assetId,
        valueCents: body['valueCents'] == null
            ? valuation.valueCents
            : _requiredCents(body),
        valuedOn: switch (body['valuedOn']) {
          final String valuedOn => DateTime.parse(valuedOn).calendarDay,
          _ => valuation.valuedOn,
        },
      ),
    );
    container.read(spendDataChangedProvider.notifier).notify();
    return _ownedAssets(request);
  }

  static Future<OwnedAssetWithValuations> _requireAsset(
    OwnedAssetsRepository repository,
    String assetId,
  ) async =>
      (await repository.listWithValuations())
          .where((ownedAsset) => ownedAsset.asset.id == assetId)
          .firstOrNull ??
      (throw ArgumentError('No owned asset $assetId.'));

  static int _requiredCents(Map<String, dynamic> body) =>
      switch (body['valueCents']) {
        final int cents => cents,
        _ => throw ArgumentError('valueCents must be an integer.'),
      };

  static Map<String, Object?> _lifeEventJson(LifeEvent event) => {
    'id': event.id,
    'kind': event.kind.name,
    'title': event.title,
    'startedOn': event.startedOn.calendarDay.isoDate,
    'endedOn': event.endedOn?.calendarDay.isoDate,
    'note': event.note,
    'details': event.details,
  };
}
