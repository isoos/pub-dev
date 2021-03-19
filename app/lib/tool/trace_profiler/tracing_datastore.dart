// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:gcloud/common.dart';
import 'package:gcloud/datastore.dart';

import 'trace_profiler.dart';

/// Implementation of [Datastore] interface with tracing hooks.
class TracingDatastore implements Datastore {
  final Datastore _datastore;
  final TraceProfiler _tracer;
  TracingDatastore(this._datastore, this._tracer);

  @override
  Future<List<Key>> allocateIds(List<Key> keys) async {
    return await _tracer
        .traceFuture(() async => await _datastore.allocateIds(keys));
  }

  @override
  Future<Transaction> beginTransaction({bool crossEntityGroup = false}) async {
    return await _tracer.traceFuture(() async =>
        await _datastore.beginTransaction(crossEntityGroup: crossEntityGroup));
  }

  @override
  Future<CommitResult> commit({
    List<Entity> inserts,
    List<Entity> autoIdInserts,
    List<Key> deletes,
    Transaction transaction,
  }) async {
    return await _tracer.traceFuture(() async => await _datastore.commit(
          inserts: inserts,
          autoIdInserts: autoIdInserts,
          deletes: deletes,
          transaction: transaction,
        ));
  }

  @override
  Future<List<Entity>> lookup(List<Key> keys, {Transaction transaction}) async {
    return await _tracer.traceFuture(
        () async => await _datastore.lookup(keys, transaction: transaction));
  }

  @override
  Future<Page<Entity>> query(
    Query query, {
    Partition partition,
    Transaction transaction,
  }) async {
    return await _tracer.traceFuture(() async => await _datastore.query(
          query,
          partition: partition,
          transaction: transaction,
        ));
  }

  @override
  Future rollback(Transaction transaction) async {
    return await _tracer
        .traceFuture(() async => await _datastore.rollback(transaction));
  }
}
