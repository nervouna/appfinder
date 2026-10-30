import Testing
import AppFinderCore

@Suite struct CalculatorTests {
    @Test(arguments: [
        ("1+2*3", "7"),
        ("(1+2)*3", "9"),
        ("10-3-2", "5"),
        ("24/3/2", "4"),
        ("-2 * (3 + 4)", "-14"),
        ("1--2", "3"),
        ("2/-4", "-0.5"),
        ("-(2+3) * -2", "10"),
        ("--2 + +3", "5"),
        ("6 × 2 ÷ 4", "3"),
        (".5 + 1.", "1.5"),
        ("0.1+0.2", "0.3"),
        ("1.20 + 2.30", "3.5"),
        ("1-1", "0"),
        ("9007199254740992+1", "9007199254740993"),
    ])
    func computesArithmetic(expression: String, expected: String) throws {
        let evaluation = try #require(Calculator.evaluate(expression))
        guard case .result(let result) = evaluation else {
            Issue.record("Expected a result for \(expression), got \(evaluation)")
            return
        }
        #expect(result.value == expected)
    }

    @Test func formatsCompactEquationForDisplayAndCopy() throws {
        let evaluation = try #require(Calculator.evaluate(" 6 × ( 2 + 3 ) "))
        guard case .result(let result) = evaluation else {
            Issue.record("Expected a calculation result")
            return
        }
        #expect(result.equation == "6×(2+3)=30")
    }

    @Test(arguments: [
        "", "  ", "123", "-1.5", "(123)", "Safari", "1Password", "report-2026.pdf",
        "1+", "(1+2", "1/0+", "1/0+abc", "1+2)", "1 2+3", "1..2+3",
        "2(3+4)", "1+()", "1/**2", "sqrt(4)", "2^3", "10%", "1+2=",
    ])
    func leavesOrdinaryAndUnfinishedQueriesAlone(expression: String) {
        #expect(Calculator.evaluate(expression) == nil)
    }

    @Test(arguments: ["1/0", "0/0", "5/(3-3)"])
    func rejectsDivisionByZero(expression: String) {
        #expect(Calculator.evaluate(expression) == .failure(.divisionByZero))
    }

    @Test func reportsNumbersItCannotRepresent() {
        let enormous = "1" + String(repeating: "0", count: 120)
        let tiny = "0." + String(repeating: "0", count: 120) + "1"
        #expect(Calculator.evaluate("\(enormous)*\(enormous)") == .failure(.outOfRange))
        #expect(Calculator.evaluate("\(tiny)*\(tiny)") == .failure(.outOfRange))
        #expect(Calculator.evaluate(String(repeating: "9", count: 50) + "+1") == .failure(.outOfRange))
    }
}
