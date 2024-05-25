import fastparse._, NoWhitespace._

def wsSingle[$: P] = P(" " | "\t")
def ws[$: P] = P(wsSingle.rep)
def newline[$: P] = P("\n\r" | "\r" | "\n")

def numberP[$: P] =
  P((CharPred(_.isDigit) ~ CharPred(_.isDigit).rep).!).map(s =>
    Number(s.toDouble)
  )

def stringP[$: P] = P("'" ~ AnyChar.rep.! ~ "'")
def stringConcatP[$: P] = P("++")

enum BooleanOps:
  case And, Or, Not

enum CompareOps:
  case Less, LessEq, Greater, GreaterEq, Eq, NotEq

enum ArithmaticOps:
  case Add, Sub, Mul, Div, Expo

def arihmeticOperatorP[$: P] = P((CharIn("*/+^") | "-").!).map {
  case "*" => ArithmaticOps.Mul
  case "+" => ArithmaticOps.Add
  case "-" => ArithmaticOps.Sub
  case "/" => ArithmaticOps.Div
  case "^" => ArithmaticOps.Expo
  case _   => assert(false, "arithmatic operator not defined")
}

def booleanOperatorP[$: P] = P(("and" | "or" | "not").!).map {
  case "and" => BooleanOps.And
  case "or"  => BooleanOps.Or
  case "not" => BooleanOps.Not
  case _     => assert(false, "boolean operator not defined")
}

def compareOperatorP[$: P] = P(("==" | "!=" | "<=" | ">=" | "<" | ">").!).map {
  case "<"  => CompareOps.Less
  case "<=" => CompareOps.LessEq
  case ">"  => CompareOps.Greater
  case ">=" => CompareOps.GreaterEq
  case "==" => CompareOps.Eq
  case "!=" => CompareOps.NotEq
  case _    => assert(false, "comparision operator not defined")
}

trait Operator
trait Value
trait Statement

case class ArithmaticOp(op: ArithmaticOps) extends Operator
case class CompareOp(op: CompareOps) extends Operator
case class BooleanOp(op: BooleanOps) extends Operator

case class Identifier(name: String) extends Value
case class Number(value: Double) extends Value
case class Bool(b: Boolean) extends Value
case class BinaryOp(left: Value, op: Operator, right: Value) extends Value
case class Function(args: Seq[String], body: Seq[Statement]) extends Value
case class Wrapped(value: Value) extends Value

case class Assignment(varName: String, value: Value) extends Statement
class Branch(condition: Value, boby: Seq[Statement])
case class If(
    inital: Branch,
    elifs: Seq[Branch],
    end: Option[Seq[Statement]]
) extends Statement
case class WhileLoop(loop: Branch) extends Statement
case class Expression(expr: Value) extends Statement
case class Return(value: Value) extends Statement

case class FunctionCall(identifier: String, args: Seq[Value])
    extends Value,
      Statement

def condition[$: P]: P[Value] =
  P("(" ~ ws ~ valueP ~ ws ~ ")")

def initialBranch[$: P]: P[Branch] =
  P(
    "if" ~ ws ~ condition ~ ws ~ codeBlock
  ).map((v, sts) => Branch(v, sts))

def whileloop[$: P]: P[Statement] =
  P("while" ~ ws ~ condition ~ ws ~ codeBlock).map((c, cb) =>
    WhileLoop(Branch(c, cb))
  )

def elif[$: P]: P[Branch] =
  P(
    "elif" ~ ws ~ condition ~ ws ~ codeBlock
  ).map((v, sts) => Branch(v, sts))

def endBranch[$: P]: P[Seq[Statement]] =
  P("else" ~ ws ~ codeBlock)

def ifStatement[$: P]: P[Statement] =
  (initialBranch ~ ws ~ elif.rep ~ ws ~ endBranch.?).map((i, m, e) =>
    If(i, m, e)
  )

def returnP[$: P]: P[Statement] =
  P("return" ~ ws ~ valueP).map(Return(_))

def statementP[$: P]: P[Statement] =
  returnP | whileloop | ifStatement | functionCallP | assignmentP

def codeBlock[$: P]: P[Seq[Statement]] =
  P("{" ~ newline ~ (ws ~ statementP ~ ws ~ newline).rep ~ ws ~ "}")

def functionDefBodyP[$: P]: P[Seq[Statement]] =
  codeBlock | valueP.map((v) => Seq(Expression(v)))

def functionDefArgsP[$: P]: P[Seq[String]] = (
  identifierP ~ (ws ~ "," ~ ws ~ functionDefArgsP).?
).map((i, is) =>
  (i, is) match {
    case (Identifier(n), Some(args)) => n +: args
    case (Identifier(n), None)       => Seq(n)
  }
)

def functionDefP[$: P]: P[Value] = (
  "(" ~ ws ~ functionDefArgsP.? ~ ws ~ ")" ~ ws ~ "=>" ~ ws ~ functionDefBodyP
).map((bs, b) =>
  bs match {
    case Some(args) => Function(args, b)
    case None       => Function(Seq(), b)
  }
)

def valueTerminalP[$: P]: P[Value] =
  functionCallP./ | identifierP | numberP | booleanP

def booleanP[$: P]: P[Value] = P(
  ("true" | "false").!
).map {
  case "true"  => Bool(true)
  case "false" => Bool(false)
  case _       => assert(false, "unreachable")
}

def functionCallArgsP[$: P]: P[Seq[Value]] = (
  valueP ~ (ws ~ "," ~ ws ~ functionCallArgsP).?
).map((v, vs) =>
  vs match {
    case None     => Seq(v)
    case Some(xs) => v +: xs
  }
)

def functionCallP[$: P]: P[FunctionCall] = (
  identifierP.! ~ "(" ~ ws ~ functionCallArgsP.? ~ ws ~ ")"
).map((n, bs) =>
  bs match {
    case None     => FunctionCall(n, Seq())
    case Some(xs) => FunctionCall(n, xs)
  }
)

def binaryOperator[$: P]: P[Operator] =
  arihmeticOperatorP.map(ArithmaticOp(_)) | booleanOperatorP.map(
    BooleanOp(_)
  ) | compareOperatorP.map(CompareOp(_))

def valueBinaryOpP[$: P]: P[Value] = (
  (valueWrappedP | valueTerminalP./) ~ (ws ~ binaryOperator ~ ws ~ valueP).?
).map((l, rest) =>
  rest match {
    case Some((op, r)) => BinaryOp(l, op, r)
    case None          => l
  }
)

def valueWrappedP[$: P]: P[Value] =
  ("(" ~ valueP ~ ")").map(Wrapped(_))

def valueP[$: P]: P[Value] = (
  functionDefP | valueBinaryOpP | valueWrappedP | valueTerminalP./
)

def identifierStartP[$: P] = P(CharIn("a-z") | CharIn("A-Z"))
def identifierRestP[$: P] = P(
  CharIn("a-z") | CharIn("A-Z") | CharIn("0-9") | "_"
)
def identifierP[$: P]: P[Value] =
  ((identifierStartP ~ identifierRestP.rep).!).map(Identifier(_))

def assignmentP[$: P]: P[Statement] =
  (identifierP.! ~/ ws ~ "=" ~ ws ~ valueP).map((n, v) => Assignment(n, v))

def mapper(sts: Seq[Option[Statement]]): Seq[Statement] =
  sts match {
    case Some(st) :: rest => st +: mapper(rest)
    case None :: rest     => mapper(rest)
    case Seq()            => Seq()
  }

def fileP[$: P]: P[Seq[Statement]] =
  ((statementP.? ~ ws ~ newline).rep).map(mapper(_))
