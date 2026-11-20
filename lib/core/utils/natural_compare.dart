final RegExp _chunkRe = RegExp(r'\d+|\D+');

bool _isDigits(String s) {
  if (s.isEmpty) return false;
  final u = s.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

/// مقارنة «طبيعية» للنصوص: الأرقام تُقارَن كقيم، فيأتي S2 قبل S10 (بدل S10 قبل S2).
/// غير حساسة لحالة الأحرف؛ وعند التعادل التام تُستعمل المقارنة الحرفية لضمان ترتيب ثابت.
int naturalCompare(String a, String b) {
  final ca = _chunkRe.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final cb = _chunkRe.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  final n = ca.length < cb.length ? ca.length : cb.length;

  for (var i = 0; i < n; i++) {
    final x = ca[i];
    final y = cb[i];
    int c;
    if (_isDigits(x) && _isDigits(y)) {
      final sx = x.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final sy = y.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      c = sx.length != sy.length
          ? sx.length.compareTo(sy.length)
          : sx.compareTo(sy);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  if (ca.length != cb.length) return ca.length.compareTo(cb.length);
  return a.compareTo(b);
}
