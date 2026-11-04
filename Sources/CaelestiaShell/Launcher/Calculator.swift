import Foundation

/// The launcher calculator ("=" prefix or plain math, spec 5.3). A small recursive-descent parser
/// (never NSExpression: it raises Objective-C exceptions Swift cannot catch on bad input).
///
/// Grammar: expr = term (('+'|'-') term)* ; term = unary (('*'|'/'|'%'|implicit) unary)* ;
/// unary = ('-'|'+') unary | power ; power = atom ('^' unary)? ; atom = number | constant |
/// function '(' expr ')' | '(' expr ')'. Constants: pi, e. Functions: sqrt, abs, sin, cos, tan,
/// asin, acos, atan, ln, log (base 10), log2, exp, floor, ceil, round.
public enum Calculator {
    public enum Failure: Error, Equatable { case syntax, divisionByZero, notFinite }

    public static func evaluate(_ input: String) throws -> Double {
        var p = Parser(Array(input.lowercased().replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: ",", with: ".")))
        let v = try p.expression()
        p.skipSpaces()
        guard p.atEnd else { throw Failure.syntax }
        guard v.isFinite else { throw Failure.notFinite }
        return v
    }

    /// True when `query` looks like math worth evaluating without the "=" prefix: it has a digit,
    /// an operator (or a function call) and parses.
    public static func looksLikeMath(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.contains(where: \.isNumber) else { return false }
        let hasOperator = q.dropFirst().contains { "+-*/%^×÷".contains($0) } || q.contains("(")
        guard hasOperator else { return false }
        return (try? evaluate(q)) != nil
    }

    /// Up to 10 significant digits, no trailing zeros, no exponent for everyday magnitudes.
    public static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 10
        f.numberStyle = abs(v) >= 1e15 || abs(v) < 1e-6 ? .scientific : .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    struct Parser {
        let s: [Character]
        var i = 0
        init(_ s: [Character]) { self.s = s }

        var atEnd: Bool { i >= s.count }
        mutating func skipSpaces() { while i < s.count, s[i] == " " { i += 1 } }
        mutating func peek() -> Character? { skipSpaces(); return i < s.count ? s[i] : nil }
        mutating func eat(_ c: Character) -> Bool {
            if peek() == c { i += 1; return true }
            return false
        }

        mutating func expression() throws -> Double {
            var v = try term()
            while true {
                if eat("+") { v += try term() } else if eat("-") { v -= try term() } else { return v }
            }
        }

        mutating func term() throws -> Double {
            var v = try unary()
            while true {
                if eat("*") {
                    v *= try unary()
                } else if eat("/") {
                    let d = try unary()
                    guard d != 0 else { throw Failure.divisionByZero }
                    v /= d
                } else if eat("%") {
                    let d = try unary()
                    guard d != 0 else { throw Failure.divisionByZero }
                    v = v.truncatingRemainder(dividingBy: d)
                } else if let c = peek(), c == "(" || c.isLetter {
                    v *= try unary()  // implicit multiplication: 2pi, 3(4+1)
                } else {
                    return v
                }
            }
        }

        mutating func unary() throws -> Double {
            if eat("-") { return -(try unary()) }
            if eat("+") { return try unary() }
            return try power()
        }

        mutating func power() throws -> Double {
            let base = try atom()
            if eat("^") { return pow(base, try unary()) }
            return base
        }

        mutating func atom() throws -> Double {
            guard let c = peek() else { throw Failure.syntax }
            if eat("(") {
                let v = try expression()
                guard eat(")") else { throw Failure.syntax }
                return v
            }
            if c.isNumber || c == "." { return try number() }
            if c.isLetter {
                var name = ""
                while i < s.count, s[i].isLetter || (s[i].isNumber && !name.isEmpty) { name.append(s[i]); i += 1 }
                switch name {
                case "pi", "π": return Double.pi
                case "e": return M_E
                default: break
                }
                guard let f = Self.functions[name], eat("(") else { throw Failure.syntax }
                let v = try expression()
                guard eat(")") else { throw Failure.syntax }
                return f(v)
            }
            throw Failure.syntax
        }

        mutating func number() throws -> Double {
            var text = ""
            while i < s.count, s[i].isNumber || s[i] == "." { text.append(s[i]); i += 1 }
            guard let v = Double(text) else { throw Failure.syntax }
            return v
        }

        static let functions: [String: @Sendable (Double) -> Double] = [
            "sqrt": { $0.squareRoot() }, "abs": { abs($0) }, "sin": sin, "cos": cos, "tan": tan,
            "asin": asin, "acos": acos, "atan": atan, "ln": log, "log": log10, "log2": log2, "exp": exp,
            "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) }, "round": { $0.rounded() },
        ]
    }
}
