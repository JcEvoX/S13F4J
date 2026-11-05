/// 子序列模糊匹配打分：query 的每个字符按序出现在 text 中即匹配。
///
/// 连续命中、词首（`/` `.` `_` `-` 空格后）命中、起始位置靠前会加分；
/// 不匹配返回 null。大小写不敏感。
int? fuzzyScore(String query, String text) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  // 连续子串命中远胜于零散命中（贪心对齐可能错过更好的位置）。
  final exact = t.indexOf(q);
  if (exact >= 0) {
    final boundary = exact == 0 || '/._- '.contains(t[exact - 1]);
    return 100 + (boundary ? 10 : 0) - exact ~/ 4 - (t.length - q.length) ~/ 8;
  }
  var score = 0;
  var ti = 0;
  var previous = -2;
  for (var qi = 0; qi < q.length; qi++) {
    final found = t.indexOf(q[qi], ti);
    if (found < 0) return null;
    score += 1;
    if (found == previous + 1) score += 5;
    if (found == 0 || '/._- '.contains(t[found - 1])) score += 3;
    if (qi == 0) score -= found ~/ 4;
    previous = found;
    ti = found + 1;
  }
  // 越短的目标越贴近查询。
  score -= (t.length - q.length) ~/ 8;
  return score;
}
