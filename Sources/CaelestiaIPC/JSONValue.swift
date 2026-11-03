import Foundation
import CaelestiaCore

/// A dynamically typed JSON value. This is the payload type of every IPC request argument and
/// every IPC result, so the wire format stays schema-free while the Swift side stays `Codable`,
/// `Hashable` and `Sendable`.
///
/// Numbers are stored as `Double` (JSON has one number type). `intValue` recovers integers
/// exactly for anything within ±2^53, which covers window ids, pids and indices.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Value is not valid JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Accessors

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }

    /// The integer value when this is a number without a fractional part (or a bool-free scalar
    /// that converts exactly). Strings are not parsed; use `intValue(lenient:)` for that.
    public var intValue: Int? {
        guard case .number(let d) = self, d.isFinite, d == d.rounded(),
            d >= Double(Int.min), d <= Double(Int.max)
        else { return nil }
        return Int(d)
    }

    /// Integer value that also accepts decimal strings ("3"), for arguments typed by hand.
    public var lenientIntValue: Int? {
        if let i = intValue { return i }
        if case .string(let s) = self { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Bool value that also accepts "true"/"false"/"1"/"0"/"yes"/"no" strings and 0/1 numbers.
    public var lenientBoolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d == 0 ? false : (d == 1 ? true : nil)
        case .string(let s):
            switch s.lowercased() {
            case "true", "yes", "on", "1": return true
            case "false", "no", "off", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Member lookup on objects; `nil` for other kinds or missing keys.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let o) = self else { return nil }
        return o[key]
    }

    /// Element lookup on arrays; `nil` when out of range or not an array.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let a) = self, a.indices.contains(index) else { return nil }
        return a[index]
    }

    // MARK: Bridging to Foundation objects

    /// Builds a value from the object graph `JSONSerialization` produces (or from plain Swift
    /// scalars, arrays and dictionaries). Throws for anything that is not representable.
    public init(any: Any?) throws {
        guard let any else {
            self = .null
            return
        }
        switch any {
        case is NSNull: self = .null
        case let v as JSONValue: self = v
        case let n as NSNumber:
            // Swift Bool/Int/Double all bridge to NSNumber; CFBoolean tells booleans apart.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case let s as String: self = .string(s)
        case let a as [Any?]: self = .array(try a.map { try JSONValue(any: $0) })
        case let o as [String: Any?]:
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(o.count)
            for (k, v) in o { out[k] = try JSONValue(any: v) }
            self = .object(out)
        default:
            throw JSONValueError.unrepresentable(String(describing: type(of: any)))
        }
    }

    /// The Foundation representation (`NSNull`, `Bool`, `Double`, `String`, `[Any]`, `[String: Any]`).
    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.anyValue)
        case .object(let o): return o.mapValues(\.anyValue)
        }
    }

    // MARK: Bridging to Codable types

    /// Encodes any `Encodable` value and re-reads it as a dynamic JSON value.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONValue.encoder.encode(value)
        self = try JSONValue.decoder.decode(JSONValue.self, from: data)
    }

    /// Decodes this value into a concrete `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        let data = try JSONValue.encoder.encode(self)
        return try JSONValue.decoder.decode(T.self, from: data)
    }

    // MARK: Bridging to keymap arguments

    /// Converts a bind argument into its JSON form.
    public init(_ arg: ArgValue) {
        switch arg {
        case .string(let s): self = .string(s)
        case .int(let i): self = .number(Double(i))
        case .double(let d): self = .number(d)
        case .bool(let b): self = .bool(b)
        }
    }

    /// The scalar `ArgValue` for this value, or `nil` for null/array/object.
    public var argValue: ArgValue? {
        switch self {
        case .null, .array, .object: return nil
        case .bool(let b): return .bool(b)
        case .string(let s): return .string(s)
        case .number(let d):
            if let i = intValue { return .int(i) }
            return .double(d)
        }
    }

    // MARK: Serialization

    /// Shared encoder: sorted keys so output is deterministic, slashes unescaped for readability.
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return e
    }()

    public static let decoder = JSONDecoder()

    /// Parses UTF-8 JSON text.
    public static func parse(_ data: Data) throws -> JSONValue {
        try decoder.decode(JSONValue.self, from: data)
    }

    /// Parses a JSON string.
    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// Compact, single-line JSON (keys sorted).
    public var compactJSON: String {
        guard let data = try? JSONValue.encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Indented JSON (keys sorted).
    public var prettyJSON: String {
        guard let data = try? JSONValue.prettyEncoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Errors raised while bridging arbitrary objects to `JSONValue`.
public enum JSONValueError: Error, Equatable, Sendable, LocalizedError {
    case unrepresentable(String)

    public var errorDescription: String? {
        switch self {
        case .unrepresentable(let t): return "Value of type \(t) cannot be represented as JSON"
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var o: [String: JSONValue] = [:]
        for (k, v) in elements { o[k] = v }
        self = .object(o)
    }
}

extension JSONValue: CustomStringConvertible {
    public var description: String { compactJSON }
}

// MARK: - Convenience constructors

extension JSONValue {
    public init(_ value: Int) { self = .number(Double(value)) }
    public init(_ value: Double) { self = .number(value) }
    public init(_ value: Bool) { self = .bool(value) }
    public init(_ value: String) { self = .string(value) }
    public init(_ values: [JSONValue]) { self = .array(values) }
    public init(_ values: [String: JSONValue]) { self = .object(values) }

    /// Wraps an optional string: `nil` becomes `.null`.
    public init(_ value: String?) { self = value.map(JSONValue.string) ?? .null }

    /// Wraps an optional integer: `nil` becomes `.null`.
    public init(_ value: Int?) { self = value.map { JSONValue.number(Double($0)) } ?? .null }

    /// Builds an object from `ArgValue` arguments (bind args → IPC args).
    public static func object(args: [String: ArgValue]) -> JSONValue {
        .object(args.mapValues(JSONValue.init))
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Converts IPC arguments back into bind arguments, dropping values that have no scalar form.
    public var argValues: [String: ArgValue] {
        var out: [String: ArgValue] = [:]
        for (k, v) in self {
            if let a = v.argValue { out[k] = a }
        }
        return out
    }
}
