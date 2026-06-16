/// Liftoscript Pratt (recursive-descent) parser.
library;

import 'ast.dart';
import 'lexer.dart';

class ParseException implements Exception {
  final String message;
  final int pos;
  ParseException(this.message, this.pos);
  @override
  String toString() => 'ParseException@$pos: $message';
}

/// Bağlama gücü (yüksek = sıkı bağlanır).
class _Bp {
  static const ternary = 2;
  static const andOr = 3;
  static const cmp = 4;
  static const plus = 5;
  static const times = 6;
  // unary = 7 (prefix), postfix (call/index) = 8
}

class Parser {
  final List<Token> _toks;
  int _p = 0;
  Parser(String src) : _toks = Lexer(src).tokenize();

  Token get _cur => _toks[_p];
  Token _advance() => _toks[_p++];
  bool _is(TokKind k) => _cur.kind == k;

  Token _expect(TokKind k, String what) {
    if (!_is(k)) {
      throw ParseException('$what bekleniyordu, "${_cur.text}" bulundu', _cur.pos);
    }
    return _advance();
  }

  ProgramNode parseProgram() {
    final body = <Node>[];
    while (!_is(TokKind.eof)) {
      body.add(_parseExpr(0));
    }
    return ProgramNode(body, 0);
  }

  /// minBp: bu seviyenin altındaki operatörlerde dur.
  Node _parseExpr(int minBp) {
    var left = _parsePrefix();

    while (true) {
      final t = _cur;
      // atama (en düşük öncelik, sağ-ilişkili)
      if ((t.kind == TokKind.assign || t.kind == TokKind.incAssign) && minBp <= 1) {
        if (!_isLValue(left)) {
          throw ParseException('Atama hedefi geçersiz', t.pos);
        }
        final op = _advance().text;
        final value = _parseExpr(1); // sağ-ilişkili
        left = AssignNode(left, op, value, t.pos);
        continue;
      }
      // ternary
      if (t.kind == TokKind.question && minBp <= _Bp.ternary) {
        _advance();
        final ifTrue = _parseExpr(0);
        _expect(TokKind.colon, '":"');
        final ifFalse = _parseExpr(_Bp.ternary);
        left = TernaryNode(left, ifTrue, ifFalse, t.pos);
        continue;
      }
      final bp = _infixBp(t);
      if (bp == 0 || bp < minBp) break;
      final opTok = _advance();
      final op = opTok.kind == TokKind.star ? '*' : opTok.text;
      // sol-ilişkili: sağ tarafı bp+1 ile parse et
      final right = _parseExpr(bp + 1);
      left = BinaryNode(op, left, right, opTok.pos);
    }
    return left;
  }

  int _infixBp(Token t) {
    switch (t.kind) {
      case TokKind.andOr:
        return _Bp.andOr;
      case TokKind.cmp:
        return _Bp.cmp;
      case TokKind.plus:
        return _Bp.plus;
      case TokKind.times:
      case TokKind.star: // çarpma olarak
        return _Bp.times;
      default:
        return 0;
    }
  }

  Node _parsePrefix() {
    final t = _cur;
    switch (t.kind) {
      case TokKind.not:
        _advance();
        return UnaryNode('!', _parseExpr(7), t.pos);
      case TokKind.plus: // unary + / -
        _advance();
        return UnaryNode(t.text, _parseExpr(7), t.pos);
      default:
        return _parsePostfix(_parsePrimary());
    }
  }

  Node _parsePostfix(Node node) {
    // Şu an postfix yalnız primary içinde ele alınıyor (call/index),
    // ek postfix gerekmez.
    return node;
  }

  Node _parsePrimary() {
    final t = _cur;
    switch (t.kind) {
      case TokKind.number:
        _advance();
        return NumberNode(t.number!, t.pos);
      case TokKind.weight:
        _advance();
        return WeightNode(t.number!, t.unit!, t.pos);
      case TokKind.percentage:
        _advance();
        return PercentageNode(t.number!, t.pos);
      case TokKind.lparen:
        _advance();
        final e = _parseExpr(0);
        _expect(TokKind.rparen, '")"');
        return e;
      case TokKind.lbrace:
        return _parseBlock();
      case TokKind.variable:
        _advance();
        return LocalVarNode(t.text, t.pos);
      case TokKind.stateKeyword:
        return _parseState();
      case TokKind.keyword:
        return _parseKeyword();
      default:
        throw ParseException('Beklenmeyen "${t.text}"', t.pos);
    }
  }

  BlockNode _parseBlock() {
    final start = _expect(TokKind.lbrace, '"{"').pos;
    final body = <Node>[];
    while (!_is(TokKind.rbrace) && !_is(TokKind.eof)) {
      body.add(_parseExpr(0));
    }
    _expect(TokKind.rbrace, '"}"');
    return BlockNode(body, start);
  }

  Node _parseState() {
    final start = _expect(TokKind.stateKeyword, '"state"').pos;
    Node? indexExpr;
    if (_is(TokKind.lbracket)) {
      _advance();
      indexExpr = _parseExpr(0);
      _expect(TokKind.rbracket, '"]"');
    }
    _expect(TokKind.dot, '"."');
    final key = _expect(TokKind.keyword, 'state anahtarı').text;
    return StateVarNode(key, indexExpr, start);
  }

  Node _parseKeyword() {
    final t = _expect(TokKind.keyword, 'tanımlayıcı');
    final name = t.text;
    // anahtar kelimeler: if / for
    if (name == 'if') return _parseIf(t.pos);
    if (name == 'for') return _parseFor(t.pos);

    // fonksiyon çağrısı?
    if (_is(TokKind.lparen)) {
      _advance();
      final args = <Node>[];
      if (!_is(TokKind.rparen)) {
        args.add(_parseExpr(0));
        while (_is(TokKind.comma)) {
          _advance();
          args.add(_parseExpr(0));
        }
      }
      _expect(TokKind.rparen, '")"');
      return CallNode(name, args, t.pos);
    }

    // indeksli binding?
    if (_is(TokKind.lbracket)) {
      _advance();
      final parts = <IndexPart>[];
      parts.add(_parseIndexPart());
      while (_is(TokKind.colon)) {
        _advance();
        parts.add(_parseIndexPart());
      }
      _expect(TokKind.rbracket, '"]"');
      return VarNode(name, parts, t.pos);
    }

    return VarNode(name, null, t.pos);
  }

  IndexPart _parseIndexPart() {
    if (_is(TokKind.star)) {
      _advance();
      return const IndexPart.wildcard();
    }
    // "_" wildcard de keyword olarak gelebilir
    if (_is(TokKind.keyword) && _cur.text == '_') {
      _advance();
      return const IndexPart.wildcard();
    }
    return IndexPart.expr(_parseExpr(0));
  }

  Node _parseIf(int start) {
    final branches = <(Node, BlockNode)>[];
    _expect(TokKind.lparen, '"("');
    final cond = _parseExpr(0);
    _expect(TokKind.rparen, '")"');
    final block = _parseBlock();
    branches.add((cond, block));
    BlockNode? elseBlock;
    while (_is(TokKind.keyword) && _cur.text == 'else') {
      _advance(); // else
      if (_is(TokKind.keyword) && _cur.text == 'if') {
        _advance(); // if
        _expect(TokKind.lparen, '"("');
        final c = _parseExpr(0);
        _expect(TokKind.rparen, '")"');
        final b = _parseBlock();
        branches.add((c, b));
      } else {
        elseBlock = _parseBlock();
        break;
      }
    }
    return IfNode(branches, elseBlock, start);
  }

  Node _parseFor(int start) {
    _expect(TokKind.lparen, '"("');
    final v = _expect(TokKind.variable, 'var.xxx');
    final inKw = _expect(TokKind.keyword, '"in"');
    if (inKw.text != 'in') throw ParseException('"in" bekleniyordu', inKw.pos);
    final iter = _parseExpr(0);
    _expect(TokKind.rparen, '")"');
    final block = _parseBlock();
    return ForNode(v.text, iter, block, start);
  }

  bool _isLValue(Node n) => n is VarNode || n is LocalVarNode || n is StateVarNode;
}
