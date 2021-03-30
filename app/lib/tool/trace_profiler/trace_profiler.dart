// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';

/// Global aggregator object.
final traceAggregator = TraceDurationAggregator();

/// Interface for profiling selected parts of the code.
abstract class TraceProfiler {
  /// Traces a sync block.
  R trace<R>(R Function() fn);

  /// Traces an async block.
  Future<R> traceFuture<R>(Future<R> Function() fn);

  /// Traces an async stream.
  Stream<R> traceStream<R>(Stream<R> Function() fn);
}

/// The sampled [trace] and the [duration] it was running.
class TraceDuration {
  final Trace trace;
  final Duration duration;

  TraceDuration(this.trace, this.duration);
}

/// A [TraceProfiler] that does not have any tracing.
class PassThroughTraceProfiler implements TraceProfiler {
  @override
  R trace<R>(R Function() fn) => fn();

  @override
  Future<R> traceFuture<R>(Future<R> Function() fn) => fn();

  @override
  Stream<R> traceStream<R>(Stream<R> Function() fn) => fn();
}

abstract class _BaseTraceProfiler implements TraceProfiler {
  final _controller = StreamController<TraceDuration>.broadcast();

  @override
  R trace<R>(R Function() fn) {
    if (_controller.hasListener && shouldSelect()) {
      final trace = Trace.current(1);
      final sw = Stopwatch()..start();
      try {
        return fn();
      } finally {
        _emit(trace, sw.elapsed);
      }
    } else {
      return fn();
    }
  }

  @override
  Future<R> traceFuture<R>(Future<R> Function() fn) async {
    if (_controller.hasListener && shouldSelect()) {
      final trace = Trace.current(1);
      final sw = Stopwatch()..start();
      try {
        return await fn();
      } finally {
        _emit(trace, sw.elapsed);
      }
    } else {
      return await fn();
    }
  }

  @override
  Stream<R> traceStream<R>(Stream<R> Function() fn) async* {
    if (_controller.hasListener && shouldSelect()) {
      final trace = Trace.current(1);
      final sw = Stopwatch()..start();
      try {
        yield* fn();
      } finally {
        _emit(trace, sw.elapsed);
      }
    } else {
      yield* fn();
    }
  }

  Future<void> close() async {
    await _controller.close();
  }

  bool shouldSelect();

  Stream<TraceDuration> get stream => _controller.stream;

  void _emit(Trace trace, Duration duration) {
    _controller.add(TraceDuration(trace, duration)); // level = _emit + trace*
  }
}

/// A [TraceProfiler] that samples every N-th call.
class SamplingTraceProfiler extends _BaseTraceProfiler {
  final int _rate;
  int _current;

  SamplingTraceProfiler({@required int rate})
      : _rate = rate,
        _current = rate;

  @override
  bool shouldSelect() {
    _current--;
    if (_current == 0) {
      _current = _rate;
      return true;
    }
    return false;
  }
}

/// Tracks trace durations and aggregates in both top-down and bottom-up trees.
class TraceDurationAggregator {
  final _topDown = TraceTreeNode('topDown');
  final _bottomUp = TraceTreeNode('bottomUp');

  void add(TraceDuration td) {
    _topDown.addFrames(
        td.trace.frames.reversed.where(_includeFrame), td.duration);
    _bottomUp.addFrames(td.trace.frames.where(_includeFrame), td.duration);
  }

  bool _includeFrame(Frame frame) {
    return !frame.isCore &&
        !frame.library.startsWith('package:pub_dev/shared/datastore.dart') &&
        !frame.library.startsWith('package:stack_trace/') &&
        !frame.library.startsWith('package:retry/');
  }

  Map<String, dynamic> stats() => {
        'byCount': {
          ..._topDown.statByCount(),
          ..._bottomUp.statByCount(),
        },
        'byDuration': {
          ..._topDown.statByDuration(),
          ..._bottomUp.statByDuration(),
        },
      };

  String statsAsJson() {
    return JsonEncoder.withIndent('  ').convert(stats());
  }
}

/// The aggregated value of the measured stack frames.
class TraceTreeNode {
  /// The string representation of the stack frame.
  final String id;

  /// The number of instances this frame was counted in this position.
  int count = 0;

  /// The total duration this frame was counted in this position.
  Duration duration = Duration.zero;

  /// The children nodes (if there was any).
  List<TraceTreeNode> children;

  TraceTreeNode(this.id);

  void addFrames(Iterable<Frame> frames, Duration duration) {
    var node = this;
    node.count++;
    node.duration += duration;
    for (final frame in frames) {
      final childId = '${frame.member} in ${frame.location}';
      node.children ??= <TraceTreeNode>[];
      final child = node.children.firstWhere(
        (n) => n.id == childId,
        orElse: () {
          final c = TraceTreeNode(childId);
          node.children.add(c);
          return c;
        },
      );
      child.count++;
      child.duration += duration;
      node = child;
    }
  }

  /// Returns the sorted map of child nodes in decreasing order of [count].
  Map<String, dynamic> statByCount({bool complete = false}) {
    if (children == null || children.isEmpty) {
      return {id: count};
    } else {
      children.sort((a, b) => -a.count.compareTo(b.count));
      final map = <String, dynamic>{};
      final limit = complete ? 0 : count ~/ 100;
      var skipped = 0;
      for (final c in children) {
        if (c.count < limit) {
          skipped += c.count;
          continue;
        }
        map.addAll(c.statByCount());
      }
      if (skipped > 0) {
        map['skipped'] = skipped;
      }
      return {'[$count][$duration] $id': map};
    }
  }

  /// Returns the sorted map of child nodes in decreasing order of [duration].
  Map<String, dynamic> statByDuration({bool complete = false}) {
    if (children == null || children.isEmpty) {
      return {id: duration.toString()};
    } else {
      children.sort((a, b) => -a.duration.compareTo(b.duration));
      final map = <String, dynamic>{};
      final limit = complete ? Duration.zero : duration ~/ 100;
      var skipped = Duration.zero;
      for (final c in children) {
        if (c.duration < limit) {
          skipped += c.duration;
          continue;
        }
        map.addAll(c.statByDuration());
      }
      if (skipped > Duration.zero) {
        map['skipped'] = skipped.toString();
      }
      return {'[$duration][$count] $id': map};
    }
  }
}
