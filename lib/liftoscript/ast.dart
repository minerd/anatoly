/// Liftoscript AST düğümleri.
library;

sealed class Node {
  final int pos;
  const Node(this.pos);
}

class ProgramNode extends Node {
  final List<Node> body;
  const ProgramNode(this.body, int pos) : super(pos);
}

class BlockNode extends Node {
  final List<Node> body;
  const BlockNode(this.body, int pos) : super(pos);
}

class NumberNode extends Node {
  final double value;
  const NumberNode(this.value, int pos) : super(pos);
}

class WeightNode extends Node {
  final double value;
  final String unit;
  const WeightNode(this.value, this.unit, int pos) : super(pos);
}

class PercentageNode extends Node {
  final double value;
  const PercentageNode(this.value, int pos) : super(pos);
}

/// İndeks parçası: wildcard `*` veya ifade.
class IndexPart {
  final bool isWildcard;
  final Node? expr;
  const IndexPart.wildcard() : isWildcard = true, expr = null;
  const IndexPart.expr(this.expr) : isWildcard = false;
}

/// Binding değişkeni (Keyword), opsiyonel indeksli: `weights`, `reps[1]`, `weights[*:1:*]`.
class VarNode extends Node {
  final String name;
  final List<IndexPart>? indices;
  const VarNode(this.name, this.indices, int pos) : super(pos);
}

/// Yerel değişken `var.xxx`.
class LocalVarNode extends Node {
  final String name;
  const LocalVarNode(this.name, int pos) : super(pos);
}

/// State değişkeni `state.key` veya `state[idx].key`.
class StateVarNode extends Node {
  final String key;
  final Node? indexExpr;
  const StateVarNode(this.key, this.indexExpr, int pos) : super(pos);
}

class CallNode extends Node {
  final String name;
  final List<Node> args;
  const CallNode(this.name, this.args, int pos) : super(pos);
}

class UnaryNode extends Node {
  final String op; // ! + -
  final Node operand;
  const UnaryNode(this.op, this.operand, int pos) : super(pos);
}

class BinaryNode extends Node {
  final String op;
  final Node left;
  final Node right;
  const BinaryNode(this.op, this.left, this.right, int pos) : super(pos);
}

class TernaryNode extends Node {
  final Node cond;
  final Node ifTrue;
  final Node ifFalse;
  const TernaryNode(this.cond, this.ifTrue, this.ifFalse, int pos) : super(pos);
}

class IfNode extends Node {
  final List<(Node cond, BlockNode block)> branches;
  final BlockNode? elseBlock;
  const IfNode(this.branches, this.elseBlock, int pos) : super(pos);
}

class ForNode extends Node {
  final String varName; // var.xxx
  final Node iterable;
  final BlockNode block;
  const ForNode(this.varName, this.iterable, this.block, int pos) : super(pos);
}

class AssignNode extends Node {
  final Node target; // VarNode | LocalVarNode | StateVarNode
  final String op; // = += -= *= /=
  final Node value;
  const AssignNode(this.target, this.op, this.value, int pos) : super(pos);
}
