import Foundation

/// Basic arithmetic for the search field. Only complete expressions with a binary operator
/// become calculator results; ordinary queries and unfinished expressions stay searches.
public enum Calculator {
    public struct Result: Equatable, Sendable {
        public let expression: String
        public let value: String

        public var equation: String { "\(expression.filter { !$0.isWhitespace })=\(value)" }
    }

    public enum Evaluation: Equatable, Sendable {
        case result(Result)
        case failure(Failure)
    }

    public enum Failure: Equatable, Sendable {
        case divisionByZero
        case outOfRange
    }

    public static func evaluate(_ expression: String) -> Evaluation? {
        let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        var parser = Parser(expression)
        guard var value = try? parser.parse() else { return nil }
        if let failure = parser.failure { return .failure(failure) }
        return .result(Result(expression: expression, value: NSDecimalString(&value, locale)))
    }

    private static let locale = Locale(identifier: "en_US_POSIX")

    private enum Operation {
        case add, subtract, multiply, divide, negate, open

        var precedence: Int {
            switch self {
            case .open: 0
            case .add, .subtract: 1
            case .multiply, .divide: 2
            case .negate: 3
            }
        }
    }

    private enum SyntaxError: Error { case invalid }

    /// Two stacks keep pasted expressions and nested parentheses off the call stack.
    private struct Parser {
        let characters: [Character]
        var index = 0
        var values: [Decimal] = []
        var operations: [Operation] = []
        var failure: Failure?

        init(_ text: String) {
            characters = Array(text)
        }

        mutating func parse() throws -> Decimal {
            var expectsOperand = true
            var hasBinaryOperator = false

            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace {
                    index += 1
                    continue
                }
                if Self.isDigit(character) || character == "." {
                    guard expectsOperand else { throw SyntaxError.invalid }
                    values.append(try number())
                    expectsOperand = false
                    continue
                }
                index += 1
                let operation: Operation
                switch character {
                case "(":
                    guard expectsOperand else { throw SyntaxError.invalid }
                    operations.append(.open)
                    continue
                case ")":
                    guard !expectsOperand else { throw SyntaxError.invalid }
                    while let previous = operations.last, previous != .open {
                        try apply(operations.removeLast())
                    }
                    guard operations.popLast() == .open else { throw SyntaxError.invalid }
                    continue
                case "+", "-":
                    if expectsOperand {
                        if character == "-" { operations.append(.negate) }
                        continue
                    }
                    operation = character == "+" ? .add : .subtract
                case "*", "×": operation = .multiply
                case "/", "÷": operation = .divide
                default: throw SyntaxError.invalid
                }
                guard !expectsOperand else { throw SyntaxError.invalid }
                while let previous = operations.last, previous != .open,
                      previous.precedence >= operation.precedence {
                    try apply(operations.removeLast())
                }
                operations.append(operation)
                expectsOperand = true
                hasBinaryOperator = true
            }

            guard !expectsOperand, hasBinaryOperator else { throw SyntaxError.invalid }
            while let operation = operations.popLast() {
                guard operation != .open else { throw SyntaxError.invalid }
                try apply(operation)
            }
            guard values.count == 1 else { throw SyntaxError.invalid }
            return values[0]
        }

        mutating func number() throws -> Decimal {
            let start = index
            var digits = 0
            var hasPoint = false
            while index < characters.count {
                let character = characters[index]
                if Self.isDigit(character) {
                    digits += 1
                } else if character == ".", !hasPoint {
                    hasPoint = true
                } else {
                    break
                }
                index += 1
            }
            guard digits > 0 else { throw SyntaxError.invalid }
            let text = String(characters[start..<index])
            let significant = text.filter(Self.isDigit).drop(while: { $0 == "0" })
                .reversed().drop(while: { $0 == "0" })
            if significant.isEmpty { return .zero }
            // Decimal(string:) silently truncates overlong literals. Refuse those rather than
            // presenting a different number as if the input had been represented exactly.
            guard significant.count <= 38, let value = Decimal(string: text, locale: locale) else {
                failure = failure ?? .outOfRange
                return .zero
            }
            return value
        }

        mutating func apply(_ operation: Operation) throws {
            guard var right = values.popLast() else { throw SyntaxError.invalid }
            if operation == .negate {
                values.append(-right)
                return
            }
            guard var left = values.popLast() else { throw SyntaxError.invalid }
            var result = Decimal.zero
            let status: Decimal.CalculationError
            switch operation {
            case .add: status = NSDecimalAdd(&result, &left, &right, .plain)
            case .subtract: status = NSDecimalSubtract(&result, &left, &right, .plain)
            case .multiply: status = NSDecimalMultiply(&result, &left, &right, .plain)
            case .divide: status = NSDecimalDivide(&result, &left, &right, .plain)
            case .negate, .open: throw SyntaxError.invalid
            }
            switch status {
            case .noError, .lossOfPrecision:
                // Some Foundation versions wrap an underflowing multiplication's exponent
                // instead of reporting underflow. Its magnitude must still match the operands.
                if operation == .multiply, left != .zero, right != .zero {
                    let order = Self.order(of: left) + Self.order(of: right)
                    guard result != .zero, (order...order + 2).contains(Self.order(of: result)) else {
                        failure = failure ?? .outOfRange
                        values.append(.zero)
                        return
                    }
                }
                values.append(result)
            case .divideByZero:
                failure = failure ?? .divisionByZero
                values.append(.zero)
            case .overflow, .underflow:
                failure = failure ?? .outOfRange
                values.append(.zero)
            @unknown default:
                failure = failure ?? .outOfRange
                values.append(.zero)
            }
        }

        static func isDigit(_ character: Character) -> Bool {
            character >= "0" && character <= "9"
        }

        static func order(of value: Decimal) -> Int {
            var significand = value.significand
            return value.exponent + NSDecimalString(&significand, locale).count - 1
        }
    }
}
