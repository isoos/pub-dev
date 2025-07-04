// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:pub_dev/search/heap.dart';
import 'package:pub_dev/third_party/bit_array/bit_array.dart';

import 'text_utils.dart';

/// The weighted tokens used for the final search.
class TokenMatch {
  final Map<String, double> _tokenWeights = <String, double>{};

  Iterable<MapEntry<String, double>> get entries => _tokenWeights.entries;

  @visibleForTesting
  Map<String, double> get tokenWeights => _tokenWeights;

  void setValueMaxOf(String token, double weight) {
    final old = _tokenWeights[token] ?? 0.0;
    if (old < weight) {
      _tokenWeights[token] = weight;
    }
  }
}

/// Stores a token -> documentId inverted index with weights.
class TokenIndex<K> {
  final List<K> _ids;

  /// Maps token Strings to a weighted documents (addressed via indexes).
  final _inverseIds = <String, Map<int, double>>{};

  late final _length = _ids.length;

  late final _scorePool = ScorePool(_ids);

  TokenIndex(
    List<K> ids,
    List<String?> values, {
    bool skipDocumentWeight = false,
  }) : _ids = ids {
    assert(ids.length == values.length);
    final length = values.length;
    for (var i = 0; i < length; i++) {
      final text = values[i];

      if (text == null) {
        continue;
      }
      _build(i, text, skipDocumentWeight);
    }
  }

  TokenIndex.fromValues(
    List<K> ids,
    List<List<String>?> values, {
    bool skipDocumentWeight = false,
  }) : _ids = ids {
    assert(ids.length == values.length);
    final length = values.length;
    for (var i = 0; i < length; i++) {
      final parts = values[i];

      if (parts == null || parts.isEmpty) {
        continue;
      }
      for (final text in parts) {
        _build(i, text, skipDocumentWeight);
      }
    }
  }

  void _build(int i, String text, bool skipDocumentWeight) {
    final tokens = tokenize(text);
    if (tokens == null || tokens.isEmpty) {
      return;
    }
    // Document weight is a highly scaled-down proxy of the length.
    final dw = skipDocumentWeight ? 1.0 : 1 + math.log(1 + tokens.length) / 100;
    for (final e in tokens.entries) {
      final token = e.key;
      final weights = _inverseIds.putIfAbsent(token, () => {});
      weights[i] = math.max(weights[i] ?? 0.0, e.value / dw);
    }
  }

  factory TokenIndex.fromMap(Map<K, String> map) {
    final keys = map.keys.toList();
    final values = map.values.toList();
    return TokenIndex(keys, values);
  }

  /// Match the text against the corpus and return the tokens or
  /// their partial segments that have match.
  @visibleForTesting
  TokenMatch lookupTokens(String text) {
    final tokenMatch = TokenMatch();

    for (final word in splitForIndexing(text)) {
      final tokens = tokenize(word, isSplit: true) ?? {};

      final present =
          tokens.keys.where((token) => _inverseIds.containsKey(token)).toList();
      if (present.isEmpty) {
        return TokenMatch();
      }
      final bestTokenValue =
          present.map((token) => tokens[token]!).reduce(math.max);
      final minTokenValue = bestTokenValue * 0.7;
      for (final token in present) {
        final value = tokens[token]!;
        if (value >= minTokenValue) {
          tokenMatch.setValueMaxOf(token, value);
        }
      }
    }

    return tokenMatch;
  }

  /// Search the index for [words], providing the result [IndexedScore] values
  /// in the [fn] callback, reusing the score buffers between calls.
  R withSearchWords<R>(List<String> words, R Function(IndexedScore<K> score) fn,
      {double weight = 1.0}) {
    IndexedScore<K>? score;

    weight = math.pow(weight, 1 / words.length).toDouble();
    for (final w in words) {
      final s = _scorePool._acquire();
      searchAndAccumulate(w, score: s, weight: weight);
      if (score == null) {
        score = s;
      } else {
        score.multiplyAllFrom(s);
        _scorePool._release(s);
      }
    }
    score ??= _scorePool._acquire();
    final r = fn(score);
    _scorePool._release(score);
    return r;
  }

  /// Searches the index with [word] and stores the results in [score], using
  /// accumulation operation on the already existing values.
  void searchAndAccumulate(
    String word, {
    double weight = 1.0,
    required IndexedScore score,
  }) {
    assert(score.length == _length);
    final tokenMatch = lookupTokens(word);
    for (final entry in tokenMatch.entries) {
      final token = entry.key;
      final matchWeight = entry.value;
      final tokenWeight = _inverseIds[token]!;
      for (final e in tokenWeight.entries) {
        score.setValueMaxOf(e.key, matchWeight * e.value * weight);
      }
    }
  }
}

extension StringTokenIndexExt on TokenIndex<String> {
  /// Search the index for [text], with a (term-match / document coverage percent)
  /// scoring.
  @visibleForTesting
  Map<String, double> search(String text) {
    return withSearchWords(splitForQuery(text), (score) => score.toMap());
  }
}

abstract class _AllocationPool<T> {
  final _pool = <T>[];

  /// Creates a ready-to-use item for the pool.
  final T Function() _allocate;

  /// Resets a previously used item to its initial state.
  final void Function(T) _reset;

  _AllocationPool(this._allocate, this._reset);

  T _acquire() {
    final T t;
    if (_pool.isNotEmpty) {
      t = _pool.removeLast();
      _reset(t);
    } else {
      t = _allocate();
    }
    return t;
  }

  void _release(T item) {
    _pool.add(item);
  }

  /// Executes [fn] and provides a pool item in the callback.
  /// The item will be released to the pool after [fn] completes.
  R withPoolItem<R>({
    required R Function(T array) fn,
  }) {
    final item = _acquire();
    final r = fn(item);
    _release(item);
    return r;
  }

  /// Executes [fn] and provides a getter function that can be used to
  /// acquire new pool items while the [fn] is being executed. The
  /// acquired items will be released back to the pool after [fn] completes.
  R withItemGetter<R>(R Function(T Function() itemFn) fn) {
    List<T>? items;
    T itemFn() {
      items ??= <T>[];
      final item = _acquire();
      items!.add(item);
      return item;
    }

    final r = fn(itemFn);

    if (items != null) {
      for (final item in items!) {
        _release(item);
      }
    }
    return r;
  }
}

/// A reusable pool for [IndexedScore] instances to spare some memory allocation.
class ScorePool<K> extends _AllocationPool<IndexedScore<K>> {
  ScorePool(List<K> keys)
      : super(
          () => IndexedScore(keys),
          // sets all values to 0.0
          (score) => score._values
              .setAll(0, Iterable.generate(score.length, (_) => 0.0)),
        );
}

/// A reusable pool for [BitArray] instances to spare some memory allocation.
class BitArrayPool extends _AllocationPool<BitArray> {
  BitArrayPool(int length)
      : super(
          // sets all bits to 1
          () => BitArray(length)..setRange(0, length),
          // sets all bits to 1
          (array) => array.setRange(0, length),
        );
}

/// Mutable score list that can accessed via integer index.
class IndexedScore<K> {
  final List<K> _keys;
  final List<double> _values;

  IndexedScore._(this._keys, this._values);

  factory IndexedScore(List<K> keys, [double value = 0.0]) =>
      IndexedScore._(keys, List<double>.filled(keys.length, value));

  factory IndexedScore.fromMap(Map<K, double> values) =>
      IndexedScore._(values.keys.toList(), values.values.toList());

  List<K> get keys => _keys;
  late final length = _values.length;

  int positiveCount() {
    var count = 0;
    for (var i = 0; i < length; i++) {
      if (isPositive(i)) count++;
    }
    return count;
  }

  bool isPositive(int index) {
    return _values[index] > 0.0;
  }

  bool isNotPositive(int index) {
    return _values[index] <= 0.0;
  }

  double getValue(int index) {
    return _values[index];
  }

  void setValue(int index, double value) {
    _values[index] = value;
  }

  void setValueMaxOf(int index, double value) {
    _values[index] = math.max(_values[index], value);
  }

  /// Sets the positions greater than or equal to [start] and less than [end],
  /// to [fillValue].
  void fillRange(int start, int end, double fillValue) {
    assert(start <= end);
    if (start == end) return;
    _values.fillRange(start, end, fillValue);
  }

  void multiplyAllFrom(IndexedScore other) {
    multiplyAllFromValues(other._values);
  }

  void multiplyAllFromValues(List<double> values) {
    assert(_values.length == values.length);
    for (var i = 0; i < _values.length; i++) {
      if (_values[i] == 0.0) continue;
      final v = values[i];
      _values[i] = v == 0.0 ? 0.0 : _values[i] * v;
    }
  }

  /// Returns a list where each index describes whether the position in the
  /// current [IndexedScore] is positive. The current instance changes are
  /// not reflected in the returned list, it won't change after it was created.
  List<bool> toIndexedPositiveList() {
    final list = List.filled(_values.length, false);
    for (var i = 0; i < _values.length; i++) {
      final v = _values[i];
      if (v > 0.0) {
        list[i] = true;
      }
    }
    return list;
  }

  Map<K, double> top(int count, {double? minValue}) {
    minValue ??= 0.0;
    final heap = Heap<int>((a, b) => -_values[a].compareTo(_values[b]));
    for (var i = 0; i < length; i++) {
      final v = _values[i];
      if (v < minValue) continue;
      heap.collect(i);
    }
    return Map.fromEntries(heap
        .getAndRemoveTopK(count)
        .map((i) => MapEntry(_keys[i], _values[i])));
  }

  Map<K, double> toMap() {
    final map = <K, double>{};
    for (var i = 0; i < _values.length; i++) {
      final v = _values[i];
      if (v > 0.0) {
        map[_keys[i]] = v;
      }
    }
    return map;
  }
}
