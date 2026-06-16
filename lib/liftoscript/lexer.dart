/// Liftoscript lexer — kaynak metni token'lara böler.
library;

enum TokKind {
  number,
  weight, // 100lb / 45kg
  percentage, // 80%
  keyword, // tanımlayıcı (binding/fonksiyon/anahtar kelime)
  stateKeyword, // "state"
  variable, // var.xxx
  plus, // + -
  times, // * / %
  cmp, // > >= < <= == !=
  andOr, // && ||
  not, // !
  assign, // =
  incAssign, // += -= *= /=
  lparen, rparen,
  lbrace, rbrace,
  lbracket, rbracket,
  comma,
  colon,
  question,
  dot,
  star, // * (wildcard / arrindex bağlamında)
  eof,
}

class Token {
  final TokKind kind;
  final String text;
  final int pos;
  // sayı/ağırlık/yüzde için çözümlenmiş değerler
  final double? number;
  final String? unit;
  const Token(this.kind, this.text, this.pos, {this.number, this.unit});
  @override
  String toString() => '${kind.name}("$text")';
}

class LexException implements Exception {
  final String message;
  final int pos;
  LexException(this.message, this.pos);
  @override
  String toString() => 'LexException@$pos: $message';
}

class Lexer {
  final String src;
  int _i = 0;
  Lexer(this.src);

  bool get _eof => _i >= src.length;
  String get _c => src[_i];

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isAlpha(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  }

  static bool _isIdentChar(String c) => _isAlpha(c) || _isDigit(c) || c == '_';

  List<Token> tokenize() {
    final out = <Token>[];
    while (true) {
      final t = _next();
      out.add(t);
      if (t.kind == TokKind.eof) break;
    }
    return out;
  }

  Token _next() {
    _skipTrivia();
    if (_eof) return Token(TokKind.eof, '', _i);
    final start = _i;
    final c = _c;

    // sayı / ağırlık / yüzde
    if (_isDigit(c) || (c == '.' && _i + 1 < src.length && _isDigit(src[_i + 1]))) {
      return _number(start);
    }

    // var.xxx
    if (c == 'v' && src.startsWith('var.', _i)) {
      _i += 4;
      final nameStart = _i;
      while (!_eof && _isIdentChar(_c)) {
        _i++;
      }
      return Token(TokKind.variable, src.substring(nameStart, _i), start);
    }

    // tanımlayıcı / anahtar kelime / state
    if (_isAlpha(c)) {
      while (!_eof && _isIdentChar(_c)) {
        _i++;
      }
      final word = src.substring(start, _i);
      if (word == 'state') return Token(TokKind.stateKeyword, word, start);
      return Token(TokKind.keyword, word, start);
    }

    // operatörler / noktalama
    switch (c) {
      case '+':
      case '-':
        if (_peek(1) == '=') {
          _i += 2;
          return Token(TokKind.incAssign, '$c=', start);
        }
        _i++;
        return Token(TokKind.plus, c, start);
      case '*':
      case '/':
        if (_peek(1) == '=') {
          _i += 2;
          return Token(TokKind.incAssign, '$c=', start);
        }
        _i++;
        // '*' arrindex/wildcard veya çarpma; parser bağlama göre yorumlar.
        return Token(c == '*' ? TokKind.star : TokKind.times, c, start);
      case '%':
        _i++;
        return Token(TokKind.times, c, start);
      case '>':
      case '<':
        if (_peek(1) == '=') {
          _i += 2;
          return Token(TokKind.cmp, '$c=', start);
        }
        _i++;
        return Token(TokKind.cmp, c, start);
      case '=':
        if (_peek(1) == '=') {
          _i += 2;
          return Token(TokKind.cmp, '==', start);
        }
        _i++;
        return Token(TokKind.assign, '=', start);
      case '!':
        if (_peek(1) == '=') {
          _i += 2;
          return Token(TokKind.cmp, '!=', start);
        }
        _i++;
        return Token(TokKind.not, '!', start);
      case '&':
        if (_peek(1) == '&') {
          _i += 2;
          return Token(TokKind.andOr, '&&', start);
        }
        break;
      case '|':
        if (_peek(1) == '|') {
          _i += 2;
          return Token(TokKind.andOr, '||', start);
        }
        break;
      case '(':
        _i++;
        return Token(TokKind.lparen, c, start);
      case ')':
        _i++;
        return Token(TokKind.rparen, c, start);
      case '{':
        _i++;
        return Token(TokKind.lbrace, c, start);
      case '}':
        _i++;
        return Token(TokKind.rbrace, c, start);
      case '[':
        _i++;
        return Token(TokKind.lbracket, c, start);
      case ']':
        _i++;
        return Token(TokKind.rbracket, c, start);
      case ',':
        _i++;
        return Token(TokKind.comma, c, start);
      case ':':
        _i++;
        return Token(TokKind.colon, c, start);
      case '?':
        _i++;
        return Token(TokKind.question, c, start);
      case '.':
        _i++;
        return Token(TokKind.dot, c, start);
    }
    throw LexException('Beklenmeyen karakter "$c"', _i);
  }

  Token _number(int start) {
    while (!_eof && (_isDigit(_c) || _c == '.')) {
      _i++;
    }
    final numText = src.substring(start, _i);
    final value = double.parse(numText);
    // yüzde?
    if (!_eof && _c == '%') {
      _i++;
      return Token(TokKind.percentage, '$numText%', start, number: value);
    }
    // ağırlık birimi?
    if (src.startsWith('lb', _i)) {
      _i += 2;
      return Token(TokKind.weight, '${numText}lb', start, number: value, unit: 'lb');
    }
    if (src.startsWith('kg', _i)) {
      _i += 2;
      return Token(TokKind.weight, '${numText}kg', start, number: value, unit: 'kg');
    }
    return Token(TokKind.number, numText, start, number: value);
  }

  String? _peek(int n) => _i + n < src.length ? src[_i + n] : null;

  void _skipTrivia() {
    while (!_eof) {
      final c = _c;
      // boşluk
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ';') {
        _i++;
        continue;
      }
      // satır yorumu
      if (c == '/' && _peek(1) == '/') {
        while (!_eof && _c != '\n') {
          _i++;
        }
        continue;
      }
      // blok işaretleri {~ ~} (grammar'da @skip)
      if (c == '{' && _peek(1) == '~') {
        _i += 2;
        continue;
      }
      if (c == '~' && _peek(1) == '}') {
        _i += 2;
        continue;
      }
      break;
    }
  }
}
