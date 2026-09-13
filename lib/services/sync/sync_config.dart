import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/migrations/migrate_life_event_occurred_on_keys.dart';
import 'package:spend_trends/migrations/migrate_special_categories.dart';
import 'package:spend_trends/migrations/seed_default_categories.dart';
import 'package:spend_trends/services/sync/powersync_schema.dart';
import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = ELogger('SpendTrendsSync');

/// FK graph for upload ordering (table → tables it references).
const _fkDependencies = <String, Set<String>>{
  'accounts': {},
  'category_groups': {},
  'categories': {'category_groups'},
  'sync_state': {},
  'simplefin_pulls': {},
  'simplefin_pull_accounts': {'simplefin_pulls'},
  'life_events': {},
  'housing_stays': {},
  'job_stays': {},
  'transactions': {'accounts', 'categories'},
  'categorization_rules': {'categories'},
};

/// Non-PK unique constraints for PostgREST `on_conflict`.
const _conflictColumns = <String, String>{
  'accounts': 'external_id',
  'transactions': 'account_id,external_id',
  'sync_state': 'key',
};

SyncConfig buildSpendTrendsSyncConfig(SharedPreferences preferences) {
  return DotEnvSyncBootstrap.build(
    preferences: preferences,
    appName: AppIdentity.syncAppName,
    powersyncPort: 8083,
    postgrestPort: 3006,
    schema: spendTrendsSchema,
    upload: UploadSettings(
      strategy: TieredBatchUploadStrategy(dependencies: _fkDependencies),
      conflictColumns: _conflictColumns,
    ),
    startupHooks: [
      seedDefaultCategoriesIfNeeded,
      migrateLifeEventOccurredOnKeys,
      ensureSpecialCategoriesMigrated,
    ],
    onSyncError: _log.warn,
  );
}
