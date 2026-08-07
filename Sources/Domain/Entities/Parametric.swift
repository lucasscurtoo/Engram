import Foundation

/// Parametric exercises: the "variables" field declares integer ranges
/// (`a = 2..12, b = 1..9`), and `{a}` / `{= a * b}` placeholders in the other
/// fields resolve per review — same card, fresh numbers, so the *procedure*
/// gets practiced instead of one memorized answer.
public enum Parametric {
    /// Deterministic per seed: front and back of the same review must agree.
    public static func values(spec: String, seed: UInt64) -> [String: Int] {
        var rng = SplitMix64(seed: seed)
        var values: [String: Int] = [:]
        for declaration in spec.split(separator: ",") {
            let parts = declaration.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  let range = parseRange(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            values[name] = Int.random(in: range, using: &rng)
        }
        return values
    }

    /// Replaces `{name}` with its value and `{= expr}` with the evaluated expression.
    public static func substitute(_ text: String, values: [String: Int]) -> String {
        var result = text
        // Longest names first so `{ab}` never gets clobbered by `{a}`.
        for (name, value) in values.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: "{\(name)}", with: String(value))
        }
        for match in result.matches(of: /\{=\s*(.+?)\}/).reversed() {
            var expression = String(match.output.1)
            for (name, value) in values.sorted(by: { $0.key.count > $1.key.count }) {
                expression = expression.replacingOccurrences(of: name, with: String(value))
            }
            guard let evaluated = evaluate(expression) else { continue }
            result.replaceSubrange(match.range, with: evaluated)
        }
        return result
    }

    private static func parseRange(_ text: String) -> ClosedRange<Int>? {
        let bounds = text.components(separatedBy: "..").map { $0.trimmingCharacters(in: .whitespaces) }
        guard bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]), low <= high
        else { return nil }
        return low...high
    }

    /// NSExpression over pure arithmetic. The charset guard keeps malformed input
    /// (which raises ObjC exceptions) and anything non-arithmetic out.
    private static func evaluate(_ expression: String) -> String? {
        let allowed = CharacterSet(charactersIn: "0123456789+-*/(). ")
        guard !expression.isEmpty,
              expression.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { return nil }
        guard let number = NSExpression(format: expression).expressionValue(with: nil, context: nil)
                as? NSNumber
        else { return nil }
        let value = number.doubleValue
        return value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(format: "%g", value)
    }
}

/// Tiny deterministic RNG (SplitMix64) — seeds must reproduce exactly across runs.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
