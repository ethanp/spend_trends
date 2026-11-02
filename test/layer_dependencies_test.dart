import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `ui` and `agent_api` → `use_cases` → `domain`; anything but `domain` may
/// use `data`. See README "Code layout".
class const LayerRule({
  required final String layer,
  required final List<String> forbiddenLayers,
  required final List<String> forbiddenPackages,
}) {
  static const _widgetPackages = [
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'package:flutter/cupertino.dart',
    'package:ethan_ui/',
  ];

  static const all = [
    LayerRule(
      layer: 'domain',
      forbiddenLayers: ['use_cases', 'data', 'ui', 'agent_api'],
      forbiddenPackages: [
        'package:flutter/',
        'dart:ui',
        'package:flutter_riverpod/',
        'package:ethan_ui/',
        'package:ethan_sync/',
        'package:powersync/',
        'package:http/',
      ],
    ),
    LayerRule(
      layer: 'use_cases',
      forbiddenLayers: ['ui', 'agent_api'],
      forbiddenPackages: _widgetPackages,
    ),
    LayerRule(
      layer: 'data',
      forbiddenLayers: ['use_cases', 'ui', 'agent_api'],
      forbiddenPackages: _widgetPackages,
    ),
    LayerRule(
      layer: 'agent_api',
      forbiddenLayers: ['ui'],
      forbiddenPackages: _widgetPackages,
    ),
  ];

  static final _importPattern = RegExp(
    r'''^(?:import|export) '([^']+)'.*;''',
    multiLine: true,
  );

  List<String> get violations {
    final List<String> found = [];
    final Iterable<File> layerFiles = Directory('lib/$layer')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in layerFiles) {
      for (final match in _importPattern.allMatches(file.readAsStringSync())) {
        final String uri = _asPackageUri(file, match.group(1)!);
        final bool crossesLayer = forbiddenLayers.any(
          (forbiddenLayer) =>
              uri.startsWith('package:spend_trends/$forbiddenLayer/'),
        );
        if (crossesLayer || forbiddenPackages.any(uri.startsWith)) {
          found.add('${file.path} → $uri');
        }
      }
    }
    return found;
  }

  static String _asPackageUri(File file, String uri) {
    if (uri.contains(':')) return uri;
    final String libRelative = file.uri
        .resolve(uri)
        .path
        .replaceFirst('lib/', '');
    return 'package:spend_trends/$libRelative';
  }
}

void main() {
  for (final rule in LayerRule.all) {
    test('${rule.layer} imports only what its layer may depend on', () {
      expect(rule.violations, isEmpty);
    });
  }
}
