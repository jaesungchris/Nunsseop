import Testing
@testable import Nunsseop

struct CalculatorTests {
    @Test(arguments: [
        ("-2^2", -4.0), ("(-2)^2", 4), ("2^-1", 0.5), ("-2^-2", -0.25), ("-3*2", -6), ("--2", 2), ("+3-1", 2),
        ("2^3^2", 512), ("2^10", 1024), ("12*(3+4)/2", 42), ("2+3*4", 14), ("10-4-3", 3), ("8/4/2", 1),
        ("15%", 0.15), ("200*50%", 100), ("-5%", -0.05), ("2^50%*2", 2 * 2.0.squareRoot()),
        ("2*-3", -6), ("3-2^2", -1), ("-(2)^2", -4), ("2^-1^2", 0.5), ("50%^2", 0.25),
        ("1,000+1", 1001), ("3×4", 12), ("9÷3", 3), ("1.5 * 2", 3),
    ])
    func evaluates(input: String, expected: Double) throws {
        let value = try #require(Calculator.evaluate(input))
        #expect(abs(value - expected) < 1e-9)
    }

    @Test(arguments: ["", "12", "abc", "1+", "(1+2", "1+2)", "1/0", "2*x", "^2", "1..2+1"])
    func rejects(input: String) {
        #expect(Calculator.evaluate(input) == nil)
    }

    @Test func rejectsOverlongInput() {
        #expect(Calculator.evaluate(String(repeating: "1+", count: 128) + "1") == nil)
        #expect(Calculator.evaluate(String(repeating: "-", count: 100_000) + "1+1") == nil)
        #expect(Calculator.evaluate(String(repeating: "1+", count: 127) + "1") == 128)
    }
}
