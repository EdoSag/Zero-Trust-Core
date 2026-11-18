/// A set of half-open minute ranges `[start, end)`, kept sorted and merged.
class Intervals {
  Intervals();

  Intervals.from(Intervals other)
      : _starts = List.of(other._starts),
        _ends = List.of(other._ends);

  List<int> _starts = [];
  List<int> _ends = [];

  int get length => _starts.length;

  /// Index of the first range that ends after [minute].
  int _firstEndingAfter(int minute) {
    var lo = 0;
    var hi = _ends.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_ends[mid] > minute) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Adds `[start, end)`, joining ranges it overlaps or touches.
  void add(int start, int end) {
    if (end <= start) return;
    // Ranges that end before `start` stay; ones touching it are merged.
    var i = 0;
    while (i < _starts.length && _ends[i] < start) {
      i++;
    }
    var j = i;
    var s = start;
    var e = end;
    while (j < _starts.length && _starts[j] <= e) {
      if (_starts[j] < s) s = _starts[j];
      if (_ends[j] > e) e = _ends[j];
      j++;
    }
    _starts.replaceRange(i, j, [s]);
    _ends.replaceRange(i, j, [e]);
  }

  /// Whether nothing in the set overlaps `[start, end)`.
  bool isFree(int start, int end) {
    if (end <= start) return true;
    final i = _firstEndingAfter(start);
    return i >= _starts.length || _starts[i] >= end;
  }

  /// The parts of `[from, to)` that nothing in the set covers, in order.
  List<(int, int)> gaps(int from, int to) {
    final out = <(int, int)>[];
    if (to <= from) return out;
    var cursor = from;
    for (var i = _firstEndingAfter(from); i < _starts.length; i++) {
      if (_starts[i] >= to) break;
      if (_starts[i] > cursor) out.add((cursor, _starts[i]));
      if (_ends[i] > cursor) cursor = _ends[i];
      if (cursor >= to) break;
    }
    if (cursor < to) out.add((cursor, to));
    return out;
  }
}
