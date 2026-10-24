import 'dart:convert';

import 'package:spend_trends/domain/canceling_merchant_pairs.dart';
import 'package:spend_trends/domain/category.dart';
import 'package:spend_trends/domain/special_category.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/services/llm/category_suggest_prompt.dart';
import 'package:spend_trends/services/llm/llm_errors.dart';
import 'package:spend_trends/services/sqlite/accounts_repository.dart';
import 'package:spend_trends/services/sqlite/categories_repository.dart';
import 'package:spend_trends/services/sqlite/transactions_repository.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:http/http.dart' as http;

const _logger = ELogger('SuggestMerchantCategories');

class const CategorySuggestion({
  required final String merchant,
  required final String categoryName,

  /// Null when this suggestion would create a new category on accept.
  final String? categoryId,

  /// Amounts of uncategorized transactions for [merchant], newest first.
  final List<int> transactionAmountCents = const [],
}) {
  bool get createsCategory => categoryId == null;

  int get totalAmountCents =>
      transactionAmountCents.fold<int>(0, (sum, amount) => sum + amount);

  CategorySuggestion withCategoryId(String categoryId) => CategorySuggestion(
    merchant: merchant,
    categoryId: categoryId,
    categoryName: categoryName,
    transactionAmountCents: transactionAmountCents,
  );

  CategorySuggestion withTransactionAmounts(List<int> amounts) =>
      CategorySuggestion(
        merchant: merchant,
        categoryId: categoryId,
        categoryName: categoryName,
        transactionAmountCents: amounts,
      );
}

class SuggestMerchantCategories({
  required final String proxyUrl,
  required final String appName,
  required final String appSecret,
  required final String clientId,
  required final AccountsRepository _accountsRepository,
  required final CategoriesRepository _categoriesRepository,
  required final TransactionsRepository _transactionsRepository,
  http.Client? httpClient,
}) {
  final http.Client _httpClient = httpClient ?? http.Client();
  final _prompt = const CategorySuggestPrompt();

  Future<List<CategorySuggestion>> forUncategorizedMerchants({
    int limit = 40,
  }) async {
    final categories = await _categoriesRepository.listActive();
    final suggestableCategories = [
      for (final category in categories)
        if (!category.isCatchAll) category,
    ];
    final categoryByName = {
      for (final category in suggestableCategories)
        CategoryName(category.name).normalized: category,
    };

    final merchants = await _uncategorizedMerchants(limit: limit);
    if (merchants.isEmpty) return const [];

    final response = await _requestCategorySuggestions(
      categories: suggestableCategories,
      merchants: merchants,
    );
    _ensureSuccessfulChatResponse(response);

    final parsed = _parseSuggestions(response.body, categoryByName);
    return _attachTransactionAmounts(parsed);
  }

  Future<List<CategorySuggestion>> _attachTransactionAmounts(
    List<CategorySuggestion> suggestions,
  ) async {
    if (suggestions.isEmpty) return suggestions;
    final amountsByMerchant = <String, List<int>>{};
    for (final transaction in await _uncategorizedCandidates()) {
      amountsByMerchant
          .putIfAbsent(transaction.normalizedMerchant, () => [])
          .add(transaction.amountCents);
    }
    return [
      for (final suggestion in suggestions)
        suggestion.withTransactionAmounts(
          amountsByMerchant[suggestion.merchant] ?? const [],
        ),
    ];
  }

  /// Creates any new categories, returning suggestions with concrete ids.
  Future<List<CategorySuggestion>> createMissingCategories(
    List<CategorySuggestion> suggestions,
  ) async {
    final active = await _categoriesRepository.listActive();
    final byName = <String, SpendCategory>{
      for (final category in active)
        CategoryName(category.name).normalized: category,
    };
    final resolved = <CategorySuggestion>[];
    for (final suggestion in suggestions) {
      if (suggestion.categoryId != null) {
        resolved.add(suggestion);
        continue;
      }
      final key = CategoryName(suggestion.categoryName).normalized;
      final existing = byName[key];
      if (existing != null) {
        resolved.add(suggestion.withCategoryId(existing.id));
        continue;
      }
      final created = await _categoriesRepository.createCategory(
        name: suggestion.categoryName,
      );
      byName[key] = created;
      resolved.add(suggestion.withCategoryId(created.id));
    }
    return resolved;
  }

  Future<List<String>> _uncategorizedMerchants({required int limit}) async {
    final merchants = <String>{};
    for (final transaction in await _uncategorizedCandidates()) {
      merchants.add(transaction.normalizedMerchant);
      if (merchants.length >= limit) break;
    }
    return merchants.toList();
  }

  /// Uncategorized txns after dropping same-day canceling pairs.
  Future<List<BankTransaction>> _uncategorizedCandidates({
    int limit = 500,
  }) async {
    final investmentAccountIds = {
      for (final account in await _accountsRepository.listAccounts())
        if (account.isInvestment) account.id,
    };
    final withoutNoise = CancelingMerchantPairs.excludingCancelingPairs(
      await _transactionsRepository.listAll(limit: limit),
      investmentAccountIds: investmentAccountIds,
    );
    return [
      for (final transaction in withoutNoise)
        if (transaction.isUncategorized &&
            transaction.normalizedMerchant.isNotEmpty)
          transaction,
    ];
  }

  Future<http.Response> _requestCategorySuggestions({
    required List<SpendCategory> categories,
    required List<String> merchants,
  }) {
    return _postChatCompletions([
      {'role': 'system', 'content': _prompt.buildSystemPrompt()},
      {
        'role': 'user',
        'content': _prompt.buildUserPrompt(
          categoryNames: categories.map((category) => category.name).toList(),
          merchants: merchants,
        ),
      },
    ]);
  }

  void _ensureSuccessfulChatResponse(http.Response response) {
    if (response.statusCode == 429) throw RateLimitedException();
    if (response.statusCode == 401) {
      throw LlmException('LLM authentication failed.');
    }
    if (response.statusCode != 200) {
      throw LlmException(
        'Category suggestion failed (${response.statusCode}).',
      );
    }
  }

  Future<http.Response> _postChatCompletions(
    List<Map<String, String>> messages,
  ) async {
    final url = Uri.parse('$proxyUrl/v1/chat/completions');
    _logger.log('Calling LLM proxy at $url');
    return _httpClient
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'X-App-Name': appName,
            'X-App-Token': appSecret,
            'X-Client-ID': clientId,
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'messages': messages,
            'response_format': {'type': 'json_object'},
            'max_tokens': 1500,
          }),
        )
        .timeout(const Duration(seconds: 60));
  }

  List<CategorySuggestion> _parseSuggestions(
    String body,
    Map<String, SpendCategory> categoryByName,
  ) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String?;
    if (content == null || content.isEmpty) {
      throw LlmException('Empty LLM response.');
    }
    final payload = jsonDecode(content) as Map<String, dynamic>;
    final suggestions = payload['suggestions'] as List<dynamic>? ?? [];
    final results = <CategorySuggestion>[];
    for (final item in suggestions.whereType<Map<String, dynamic>>()) {
      final merchant = (item['merchant'] as String? ?? '').toUpperCase();
      final categoryName = (item['category'] as String? ?? '').trim();
      if (merchant.isEmpty || categoryName.isEmpty) continue;
      if (CategoryName(categoryName).isCatchAll) continue;

      final existing = categoryByName[CategoryName(categoryName).normalized];
      if (existing != null) {
        results.add(
          CategorySuggestion(
            merchant: merchant,
            categoryId: existing.id,
            categoryName: existing.name,
          ),
        );
        continue;
      }

      if (!_isPlausibleNewCategoryName(categoryName)) continue;
      results.add(
        CategorySuggestion(
          merchant: merchant,
          categoryName: _titleCaseCategoryName(categoryName),
        ),
      );
    }
    return results;
  }

  static bool _isPlausibleNewCategoryName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (SpecialCategory.isReservedName(trimmed)) return false;
    if (CategoryName(trimmed).isCatchAll) return false;
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length > 4) return false;
    if (trimmed.length > 40) return false;
    return true;
  }

  static String _titleCaseCategoryName(String name) {
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          final lower = word.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  void close() => _httpClient.close();
}
