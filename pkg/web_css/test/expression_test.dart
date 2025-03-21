// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:csslib/parser.dart';
import 'package:csslib/visitor.dart';
import 'package:test/test.dart';

void main() {
  group('build + check rules', () {
    final file = File('../../static/css/style.css');

    setUpAll(() async {
      if (!file.existsSync()) {
        final pr = await Process.run('/bin/sh', ['build.sh']);
        if (pr.exitCode != 0) {
          throw Exception('Build process failed. ${pr.stdout}');
        }
      }
    });

    test('Check if all expressions are referenced in source files.', () async {
      final visitor = await _visitCssFile(file.path, checked: true);

      // Sanity checks
      expect(visitor.elements, isNotEmpty);
      expect(visitor.ids, isNotEmpty);
      expect(visitor.classes, isNotEmpty);
      expect(visitor.classes, contains('-pub-tag-badge'));
      expect(visitor.selectors, isNotEmpty);

      final expressions = visitor.expressions;

      // These expressions are extracted from the CSS file, but they won't be
      // referenced in the sources.
      // CSS functions
      expressions.removeAll(<String>[
        'first-child',
        'focus-within',
        'keyframes',
        'last-child',
        'nth-child',
        '-webkit-search-cancel-button',
      ]);
      // composite patterns
      expressions.removeWhere((e) => e.startsWith('home-block-'));
      expressions.removeWhere(
          (e) => e.startsWith('detail-tab-') && e.endsWith('-content'));
      expressions.removeWhere((e) => e.startsWith('package-badge-'));
      expressions.removeWhere((e) => e.startsWith('pub-toc-node-'));
      // downloads chart color classes
      expressions.removeWhere((e) => e.startsWith('downloads-chart'));
      // shared CSS file (with dartdoc)
      expressions.removeAll([
        'cookie-notice-container',
        'cookie-notice-button',
      ]);
      // test-only style
      expressions.remove('-pub-ongoing-screenshot');
      // markdown alert classes
      expressions.removeAll([
        'markdown-alert-note',
        'markdown-alert-tip',
        'markdown-alert-important',
        'markdown-alert-warning',
        'markdown-alert-caution',
        'markdown-alert-title',
      ]);

      // remove third-party css expressions
      final thirdPartyCss = [
        '../../third_party/css/github-markdown.css',
        '../../third_party/highlight/github.css',
        '../../third_party/highlight/github-dark.css',
      ];
      for (final path in thirdPartyCss) {
        expressions.removeAll((await _visitCssFile(path)).expressions);
      }

      final files = <File>[
        ...await Directory('../../app/lib/frontend/templates')
            .list(recursive: true)
            .where((f) => f is File)
            .cast<File>()
            .toList(),
        File('../../app/lib/frontend/dom/dom.dart'),
        File('../../app/lib/frontend/dom/material.dart'),
        File('../../app/lib/shared/markdown.dart'),
        ...await Directory('../web_app/lib')
            .list(recursive: true)
            .where((f) => f is File)
            .cast<File>()
            .toList()
      ];

      for (final file in files) {
        if (expressions.isEmpty) break;
        final content = await file.readAsString();
        final matched = expressions.where(content.contains).toList();
        expressions.removeAll(matched);
      }

      expect(expressions, isEmpty);
    });
  });
}

Future<_Visitor> _visitCssFile(
  String path, {
  bool checked = false,
}) async {
  final file = File(path);
  final styles = parse(
    await file.readAsString(),
    options: PreprocessorOptions(
      throwOnWarnings: checked,
      throwOnErrors: checked,
      checked: checked,
    ),
  );
  final visitor = _Visitor();
  styles.visit(visitor);
  return visitor;
}

class _Visitor extends Visitor {
  final ids = <String>{};
  final elements = <String>{};
  final classes = <String>{};
  final selectors = <String>{};

  Set<String> get expressions => <String>{
        ...elements,
        ...ids,
        ...classes,
        ...selectors,
      };

  @override
  void visitSelector(Selector node) {
    selectors
        .addAll(node.simpleSelectorSequences.map((e) => e.simpleSelector.name));
    super.visitSelector(node);
  }

  @override
  void visitClassSelector(ClassSelector node) {
    classes.add(node.name);
    super.visitClassSelector(node);
  }

  @override
  void visitIdSelector(IdSelector node) {
    ids.add(node.name);
    super.visitIdSelector(node);
  }

  @override
  void visitElementSelector(ElementSelector node) {
    elements.add(node.name);
    super.visitElementSelector(node);
  }
}
