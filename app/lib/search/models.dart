// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import 'search_service.dart';

part 'models.g.dart';

@JsonSerializable()
class SearchSnapshot {
  DateTime updated;
  Map<String, PackageDocument> documents;

  SearchSnapshot._(this.updated, this.documents);

  factory SearchSnapshot() => SearchSnapshot._(DateTime.now().toUtc(), {});

  factory SearchSnapshot.fromJson(Map<String, dynamic> json) =>
      _$SearchSnapshotFromJson(json);

  void add(PackageDocument doc) {
    updated = DateTime.now().toUtc();
    documents[doc.package] = doc;
  }

  void remove(String packageName) {
    updated = DateTime.now().toUtc();
    documents.remove(packageName);
  }

  Map<String, dynamic> toJson() => _$SearchSnapshotToJson(this);
}

/// The parsed content of the `index.json` generated by dartdoc.
class DartdocIndex {
  final List<DartdocIndexEntry> entries;

  DartdocIndex(this.entries);

  factory DartdocIndex.parseJsonText(String content) {
    return DartdocIndex.fromJsonList(json.decode(content) as List);
  }

  factory DartdocIndex.fromJsonList(List jsonList) {
    final list = jsonList
        .map((item) => DartdocIndexEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return DartdocIndex(list);
  }

  String toJsonText() => json.encode(entries);
}

@JsonSerializable(includeIfNull: false)
class DartdocIndexEntry {
  final String name;
  final String qualifiedName;
  final String href;
  final String type;
  final int overriddenDepth;
  final String packageName;
  final DartdocIndexEntryEnclosedBy enclosedBy;

  DartdocIndexEntry({
    this.name,
    this.qualifiedName,
    this.href,
    this.type,
    this.overriddenDepth,
    this.packageName,
    this.enclosedBy,
  });

  factory DartdocIndexEntry.fromJson(Map<String, dynamic> json) =>
      _$DartdocIndexEntryFromJson(json);

  Map<String, dynamic> toJson() => _$DartdocIndexEntryToJson(this);
}

@JsonSerializable(includeIfNull: false)
class DartdocIndexEntryEnclosedBy {
  final String name;
  final String type;

  DartdocIndexEntryEnclosedBy({
    this.name,
    this.type,
  });

  factory DartdocIndexEntryEnclosedBy.fromJson(Map<String, dynamic> json) =>
      _$DartdocIndexEntryEnclosedByFromJson(json);

  Map<String, dynamic> toJson() => _$DartdocIndexEntryEnclosedByToJson(this);
}
