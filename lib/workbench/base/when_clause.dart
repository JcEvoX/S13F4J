/// `when` 子句：菜单、视图、命令的可见性 / 可用性条件。
///
/// 语法：`key` · `!expr` · `a && b` · `a || b` · `key == v` · `key != v` ·
/// `key > n`（`>=` `<` `<=`）· 括号。值可以是 `'带引号字符串'`、`true` / `false`、数字或裸词。
/// 裸 `key` 为真当且仅当值非 null、非 false、非空串、非 0。
class WhenClause {
  WhenClause._(this.source, this._root);

  /// 解析；空串 / null 表示「恒为真」。语法错误抛 [FormatException]。
  factory WhenClause.parse(String? source) {
    final text = (source ?? '').trim();
    if (text.isEmpty) return WhenClause._('', const _True());
    final parser = _Parser(_tokenize(text));
    final node = parser.parseOr();
    parser.expectEnd();
    return WhenClause._(text, node);
  }

  /// 解析失败时返回「恒为假」，避免一个坏 manifest 让菜单到处显示。
  factory WhenClause.tryParse(String? source) {
    try {
      return WhenClause.parse(source);
    } on FormatException {
      return WhenClause._(source ?? '', const _False());
    }
  }

  final String source;
  final _Node _root;

  bool evaluate(Map<String, Object?> context) => _root.eval(context);

  /// 子句引用到的全部 key（用于上下文变化时的精确刷新）。
  Set<String> get keys {
    final out = <String>{};
    _root.collect(out);
    return out;
  }

  @override
  String toString() => source;
}

bool _truthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) return value.isNotEmpty;
  if (value is num) return value != 0;
  return true;
}

abstract class _Node {
  const _Node();
  bool eval(Map<String, Object?> ctx);
  void collect(Set<String> out) {}
}

class _True extends _Node {
  const _True();
  @override
  bool eval(Map<String, Object?> ctx) => true;
}

class _False extends _Node {
  const _False();
  @override
  bool eval(Map<String, Object?> ctx) => false;
}

class _Key extends _Node {
  const _Key(this.key);
  final String key;
  @override
  bool eval(Map<String, Object?> ctx) => _truthy(ctx[key]);
  @override
  void collect(Set<String> out) => out.add(key);
}

class _Not extends _Node {
  const _Not(this.inner);
  final _Node inner;
  @override
  bool eval(Map<String, Object?> ctx) => !inner.eval(ctx);
  @override
  void collect(Set<String> out) => inner.collect(out);
}

class _And extends _Node {
  const _And(this.left, this.right);
  final _Node left;
  final _Node right;
  @override
  bool eval(Map<String, Object?> ctx) => left.eval(ctx) && right.eval(ctx);
  @override
  void collect(Set<String> out) {
    left.collect(out);
    right.collect(out);
  }
}

class _Or extends _Node {
  const _Or(this.left, this.right);
  final _Node left;
  final _Node right;
  @override
  bool eval(Map<String, Object?> ctx) => left.eval(ctx) || right.eval(ctx);
  @override
  void collect(Set<String> out) {
    left.collect(out);
    right.collect(out);
  }
}

class _Compare extends _Node {
  const _Compare(this.key, this.op, this.literal);
  final String key;
  final String op;
  final Object? literal;

  @override
  bool eval(Map<String, Object?> ctx) {
    final value = ctx[key];
    switch (op) {
      case '==':
        return _equals(value, literal);
      case '!=':
        return !_equals(value, literal);
    }
    final left = value is num ? value : num.tryParse('$value');
    final right = literal is num ? literal as num : num.tryParse('$literal');
    if (left == null || right == null) return false;
    switch (op) {
      case '>':
        return left > right;
      case '>=':
        return left >= right;
      case '<':
        return left < right;
      case '<=':
        return left <= right;
    }
    return false;
  }

  static bool _equals(Object? value, Object? literal) {
    if (literal is bool) return _truthy(value) == literal;
    if (value == null) return literal == null || literal == '';
    if (literal is num) {
      final n = value is num ? value : num.tryParse('$value');
      return n == literal;
    }
    return '$value' == '$literal';
  }

  @override
  void collect(Set<String> out) => out.add(key);
}

enum _T { ident, string, op, lparen, rparen, end }

class _Token {
  const _Token(this.type, this.text);
  final _T type;
  final String text;
}

List<_Token> _tokenize(String input) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < input.length) {
    final c = input[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '(') {
      tokens.add(const _Token(_T.lparen, '('));
      i++;
    } else if (c == ')') {
      tokens.add(const _Token(_T.rparen, ')'));
      i++;
    } else if (c == "'" || c == '"') {
      final end = input.indexOf(c, i + 1);
      if (end < 0) throw FormatException('字符串未闭合: $input');
      tokens.add(_Token(_T.string, input.substring(i + 1, end)));
      i = end + 1;
    } else if (input.startsWith('&&', i) ||
        input.startsWith('||', i) ||
        input.startsWith('==', i) ||
        input.startsWith('!=', i) ||
        input.startsWith('>=', i) ||
        input.startsWith('<=', i)) {
      tokens.add(_Token(_T.op, input.substring(i, i + 2)));
      i += 2;
    } else if (c == '!' || c == '>' || c == '<') {
      tokens.add(_Token(_T.op, c));
      i++;
    } else {
      final start = i;
      while (i < input.length &&
          !' ()!=<>&|\'"'.contains(input[i])) {
        i++;
      }
      if (i == start) throw FormatException('无法解析的字符 "$c": $input');
      tokens.add(_Token(_T.ident, input.substring(start, i)));
    }
  }
  tokens.add(const _Token(_T.end, ''));
  return tokens;
}

class _Parser {
  _Parser(this._tokens);

  final List<_Token> _tokens;
  int _pos = 0;

  _Token get _peek => _tokens[_pos];

  _Token _next() => _tokens[_pos++];

  void expectEnd() {
    if (_peek.type != _T.end) {
      throw FormatException('多余的内容: "${_peek.text}"');
    }
  }

  _Node parseOr() {
    var node = parseAnd();
    while (_peek.type == _T.op && _peek.text == '||') {
      _next();
      node = _Or(node, parseAnd());
    }
    return node;
  }

  _Node parseAnd() {
    var node = parseUnary();
    while (_peek.type == _T.op && _peek.text == '&&') {
      _next();
      node = _And(node, parseUnary());
    }
    return node;
  }

  _Node parseUnary() {
    if (_peek.type == _T.op && _peek.text == '!') {
      _next();
      return _Not(parseUnary());
    }
    return parsePrimary();
  }

  _Node parsePrimary() {
    final token = _next();
    if (token.type == _T.lparen) {
      final node = parseOr();
      if (_next().type != _T.rparen) {
        throw const FormatException('缺少 )');
      }
      return node;
    }
    if (token.type != _T.ident) {
      throw FormatException('期望 key，实际是 "${token.text}"');
    }
    const compareOps = {'==', '!=', '>', '>=', '<', '<='};
    if (_peek.type == _T.op && compareOps.contains(_peek.text)) {
      final op = _next().text;
      final valueToken = _next();
      if (valueToken.type != _T.ident && valueToken.type != _T.string) {
        throw FormatException('比较缺少右值: "${token.text} $op"');
      }
      return _Compare(token.text, op, _literal(valueToken));
    }
    if (token.text == 'true') return const _True();
    if (token.text == 'false') return const _False();
    return _Key(token.text);
  }

  Object? _literal(_Token token) {
    if (token.type == _T.string) return token.text;
    switch (token.text) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    return num.tryParse(token.text) ?? token.text;
  }
}
