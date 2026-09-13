import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/banks/banks_net_worth_pane.dart';
import 'package:spend_trends/features/banks/banks_pull_feed.dart';
import 'package:spend_trends/features/banks/banks_pull_review_pane.dart';
import 'package:spend_trends/features/banks/banks_source_section.dart';
import 'package:spend_trends/features/owned_assets/owned_asset_detail_pane.dart';
import 'package:spend_trends/features/activity/transactions_list_provider.dart';
import 'package:spend_trends/features/owned_assets/owned_assets_providers.dart';
import 'package:spend_trends/providers/spend_data_changed.dart';
import 'package:spend_trends/widgets/app_browse_split_shell.dart';
import 'package:spend_trends/widgets/sync_status_nav_button.dart';

import 'connection_status.dart';

/// Everyday SimpleFIN connect / accounts / sync.
class const BanksScreen() extends ConsumerStatefulWidget {
  @override
  ConsumerState<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState() extends ConsumerState<BanksScreen> {
  String? _selectedAccountId;
  String? _selectedOwnedAssetId;
  String? _selectedPullTransactionId;

  static const _horizontalPadding = EdgeInsets.fromLTRB(
    ELayout.spaceLg,
    ELayout.spaceMd,
    ELayout.spaceLg,
    32,
  );

  @override
  Widget build(BuildContext context) {
    final connectionAsync = ref.watch(connectionStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Banks',
        leading: SyncStatusNavButton(),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        bottom: false,
        child: connectionAsync.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              '$error',
              style: EText.body.medium.copyWith(color: EColors.danger),
            ),
          ),
          data: (status) {
            final BankTransaction? selectedPullTransaction =
                _pullTransactionById(_selectedPullTransactionId);
            final scroll = CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: _horizontalPadding,
                  sliver: SliverToBoxAdapter(
                    child: BanksSourceSection(
                      selectedAccountId: _selectedAccountId,
                      selectedOwnedAssetId: _selectedOwnedAssetId,
                      onAccountSelected: (accountId) {
                        if (!AppBrowseSplitShell.isSplit(context)) return;
                        setState(() {
                          _selectedAccountId = accountId;
                          _selectedOwnedAssetId = null;
                          _selectedPullTransactionId = null;
                        });
                      },
                      onOwnedAssetSelected: (ownedAssetId) {
                        if (!AppBrowseSplitShell.isSplit(context)) return;
                        setState(() {
                          _selectedOwnedAssetId = ownedAssetId;
                          _selectedAccountId = null;
                          _selectedPullTransactionId = null;
                        });
                      },
                    ),
                  ),
                ),
                if (status.isConnected) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: ELayout.spaceXl),
                  ),
                  SliverPadding(
                    padding: _horizontalPadding,
                    sliver: SliverToBoxAdapter(
                      child: BanksPullFeed(
                        selectedTransactionId: _selectedPullTransactionId,
                        onPullTransactionSelected: _selectPullTransaction,
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: context.overlaidTabBarInset),
                ),
              ],
            );
            if (!status.isConnected) return scroll;
            return AppBrowseSplitShell(
              left: scroll,
              right: _rightPane(
                accounts: status.accounts,
                selectedPullTransaction: selectedPullTransaction,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _rightPane({
    required List<Account> accounts,
    required BankTransaction? selectedPullTransaction,
  }) {
    if (selectedPullTransaction != null) {
      return BanksPullReviewPane(
        transaction: selectedPullTransaction,
        onCategorized: () {
          setState(() => _selectedPullTransactionId = null);
          ref.read(spendDataChangedProvider.notifier).notify();
        },
      );
    }
    if (_selectedOwnedAssetId != null) {
      return OwnedAssetDetailPane(ownedAssetId: _selectedOwnedAssetId!);
    }
    return BanksNetWorthPane(
      accounts: accounts,
      ownedAssets: ref.watch(ownedAssetsListProvider).asData?.value ?? const [],
      selectedAccountId: _selectedAccountId,
    );
  }

  void _selectPullTransaction(BankTransaction transaction) {
    if (!AppBrowseSplitShell.isSplit(context)) return;
    setState(() {
      _selectedPullTransactionId = transaction.id;
      _selectedAccountId = null;
      _selectedOwnedAssetId = null;
    });
  }

  BankTransaction? _pullTransactionById(String? transactionId) {
    if (transactionId == null) return null;
    final transactions =
        ref.watch(transactionsListProvider).asData?.value ?? const [];
    for (final transaction in transactions) {
      if (transaction.id == transactionId) return transaction;
    }
    return null;
  }
}
