import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app code does not import package src entrypoints', () async {
    final libRoot = Directory('lib');
    final testRoot = Directory('test');
    final offendingImports = <String>[];

    for (final root in [libRoot, testRoot]) {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        if (entity.path.endsWith('test/package_boundary_test.dart')) {
          continue;
        }
        final contents = await entity.readAsString();
        final trimmed = contents.trimLeft();
        final isShimExport =
            trimmed.startsWith("export 'package:crypto_core/src/") ||
            trimmed.startsWith("export 'package:chat_core/src/");
        if (isShimExport) {
          continue;
        }
        if (contents.contains("package:crypto_core/src/") ||
            contents.contains("package:chat_core/src/")) {
          offendingImports.add(entity.path);
        }
      }
    }

    expect(
      offendingImports,
      isEmpty,
      reason: 'App/test code must go through public package APIs or shims only.',
    );
  });
}
