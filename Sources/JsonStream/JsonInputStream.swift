/*
Copyright (c) 2023 Topolyte Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import Foundation

public enum JsonInputError: Error {
    case ioError(String)
    case unexpectedInput(String)
    case unexpectedEndOfInput
    case stringTooLong
    case invalidUTF8
    case invalidEscapeSequence(String)
    case invalidNumber(String)
    case unexpected(String)
}

public enum JsonKey: CustomStringConvertible, Equatable {
    case name(String)
    case index(Int)
    
    public var description: String {
        switch self {
        case let .name(name):
            return name
        case let .index(index):
            return "\(index)"
        }
    }
    
    public static func == (lhs: JsonKey, rhs: JsonKey) -> Bool {
        switch (lhs, rhs) {
        case let (.name(name1), .name(name2)):
            return name1 == name2
        case let (.index(index1), .index(index2)):
            return index1 == index2
        default:
            return false
        }
    }
}

public enum JsonToken: Equatable {
    case startObject(_ key: JsonKey?)
    case endObject(_ key: JsonKey?)
    case startArray(_ key: JsonKey?)
    case endArray(_ key: JsonKey?)
    case string(_ key: JsonKey?, _ value: String)
    case number(_ key: JsonKey?, _ value: Double)
    case bool(_ key: JsonKey?, _ value: Bool)
    case null(_ key: JsonKey?)
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.startObject(key1), .startObject(key2)):
            return key1 == key2
        case let (.endObject(key1), .endObject(key2)):
            return key1 == key2
        case let (.startArray(key1), .startArray(key2)):
            return key1 == key2
        case let (.endArray(key1), .endArray(key2)):
            return key1 == key2
        case let (.string(key1, s1), .string(key2, s2)):
            return s1 == s2 && key1 == key2
        case let (.number(key1, n1), .number(key2, n2)):
            return n1 == n2 && key1 == key2
        case let (.bool(key1, b1), .bool(key2, b2)):
            return b1 == b2 && key1 == key2
        case let (.null(key1), .null(key2)):
            return key1 == key2
        default:
            return false
        }
    }
}
    
public final class JsonInputStream {
    enum ParseState {
        case root, object(Int), array(Int)
    }

    public static var bufferCapacity = 1024 * 4
    
    let stream: InputStream
    let isOwningStream: Bool
    public var maxStringLength = 1024 * 1024 * 10
    
    private let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bufferCapacity)
    private var bytes = Data()
    private var pos = 0
    private var end = 0
    private var arrayIndex = 0
    
    var state = [ParseState.root]
    public private(set) var path = [JsonKey]()
    
    public init(filePath: String) throws {
        guard let stream = InputStream(fileAtPath: filePath) else {
            throw JsonInputError.ioError("Failed to open input stream for \(path)")
        }
        
        stream.open()
        
        self.stream = stream
        self.isOwningStream = true
        self.stream.open()
    }

    public init(stream: InputStream) {
        self.stream = stream
        self.isOwningStream = false
    }
    
    deinit {
        if isOwningStream {
            stream.close()
        }
        buf.deallocate()
    }
        
    func read() throws -> JsonToken? {
        guard var c = try nextContentByte() else {
            guard case .root = state.last else {
                throw JsonInputError.unexpectedEndOfInput
            }
            return nil
        }
        
        switch state.last! {
        case .object:
            if c == Ascii.rightBrace {
                guard case let .object(index) = try popState() else {
                    throw JsonInputError.unexpected("Expected object parsing state")
                }
                if index >= 0 {
                    popPath()
                }
                return .endObject(path.last)
            }
            
            let nextIndex = try incrementObjectIndex()
                        
            if c == Ascii.comma {
                guard nextIndex > 0 else {
                    throw unexpectedInput(c, expected: "property")
                }
                popPath()
                if let next = try nextContentByte() {
                    c = next
                } else {
                    throw JsonInputError.unexpectedEndOfInput
                }
            } else if nextIndex != 0 {
                throw unexpectedInput(c, expected: ",")
            }
            
            guard c == Ascii.quote else {
                throw unexpectedInput(c, expected: "\"")
            }
            
            let key = try JsonKey.name(readPropertyStart())
            path.append(key)
            return try readValue(key)
        case .array:
            if c == Ascii.rightSquare {
                guard case let .array(index) = try popState() else {
                    throw JsonInputError.unexpected("Expected array parsing state")
                }
                if index >= 0 {
                    popPath()
                }
                return .endArray(path.last)
            }
            
            let nextIndex = try incrementArrayIndex()
            
            if c == Ascii.comma {
                guard nextIndex > 0 else {
                    throw unexpectedInput(c, expected: "array element")
                }
                guard case .index = popPath() else {
                    throw JsonInputError.unexpected("Path not ending with array index")
                }
                if let next = try nextContentByte() {
                    c = next
                } else {
                    throw JsonInputError.unexpectedEndOfInput
                }
            } else if nextIndex != 0 {
                throw unexpectedInput(c, expected: ",")
            }
            
            let key = JsonKey.index(nextIndex)
            path.append(key)
            pushback()
            return try readValue(key)
        case .root:
            pushback()
            return try readValue(nil)
        }
    }
    
    func readValue(_ key: JsonKey?) throws -> JsonToken? {
        guard let c = try nextContentByte() else {
            return nil
        }
        
        switch c {
        case Ascii.quote:
            let str = try readString()
            return .string(key, str)
        case Ascii.n:
            try mustRead("ull")
            return .null(key)
        case Ascii.t:
            try mustRead("rue")
            return .bool(key, true)
        case Ascii.f:
            try mustRead("alse")
            return .bool(key, false)
        case Ascii.leftBrace:
            pushState(.object(-1))
            return .startObject(key)
        case Ascii.leftSquare:
            pushState(.array(-1))
            return .startArray(key)
        default:
            if isStartOfNumber(c) {
                return try .number(key, readDouble(c))
            } else {
                throw unexpectedInput(c)
            }
        }
    }
    
    func incrementObjectIndex() throws -> Int {
        guard case let .object(index) = try popState() else {
            throw JsonInputError.unexpected("Expected object state")
        }
        
        let newIndex = index + 1
        pushState(.object(newIndex))
        return newIndex
    }
    
    func incrementArrayIndex() throws -> Int {
        guard case let .array(index) = try popState() else {
            throw JsonInputError.unexpected("Expected array state")
        }
        
        let newIndex = index + 1
        pushState(.array(newIndex))
        return newIndex
    }

    func readDouble(_ firstChar: UInt8) throws -> Double {
        var str = String(UnicodeScalar(firstChar))
        
        while let c = try nextByte() {
            if isWhitespace(c) || c == Ascii.comma || c == Ascii.rightBrace || c == Ascii.rightSquare {
                pos -= 1
                break
            }
            
            switch c {
            case Ascii.zero...Ascii.nine, Ascii.dot, Ascii.e, Ascii.E, Ascii.plus, Ascii.minus:
                if str.utf8.count == maxStringLength {
                    throw JsonInputError.stringTooLong
                }
                str.append(Character(UnicodeScalar(c)))
            default:
                throw JsonInputError.invalidNumber(str + String(UnicodeScalar(c)))
            }
        }
        
        guard let d = Double(str) else {
            throw JsonInputError.invalidNumber(str)
        }
        return d
    }
    
    func readPropertyStart() throws -> String {
        let propertyName = try readString()
        
        guard let c = try nextContentByte() else {
            throw JsonInputError.unexpectedEndOfInput
        }
        
        guard c == Ascii.colon else {
            throw unexpectedInput(c, expected: ":")
        }

        return propertyName
    }
    
    func readString() throws -> String {
        bytes.removeAll(keepingCapacity: true)
        
        while let c = try nextByte() {
            if bytes.count > maxStringLength {
                throw JsonInputError.stringTooLong
            }
            
            if c == Ascii.backslash {
                try readEscape()
            } else if c == Ascii.quote {
                guard let s = String(data: bytes, encoding: .utf8) else {
                    throw JsonInputError.invalidUTF8
                }
                return s
            } else {
                bytes.append(c)
            }
        }
        
        throw JsonInputError.unexpectedEndOfInput
    }
    
    func readEscape() throws {
        guard let c = try nextByte() else {
            throw JsonInputError.unexpectedEndOfInput
        }
        
        switch c {
        case Ascii.n:
            bytes.append(Ascii.lf)
        case Ascii.quote, Ascii.backslash, Ascii.slash:
            bytes.append(c)
        case Ascii.t:
            bytes.append(Ascii.tab)
        case Ascii.u:
            try readHexEscape()
        case Ascii.r:
            break
        case Ascii.b:
            bytes.append(Ascii.backspace)
        case Ascii.f:
            bytes.append(Ascii.formFeed)
        default:
            throw JsonInputError.invalidEscapeSequence("\\\(Character(UnicodeScalar(c)))")
        }
    }
    
    func readHexEscape() throws {
        let n = try readHex()
        
        guard let u = UnicodeScalar(n) else {
            throw JsonInputError.invalidEscapeSequence("Invalid unicode scalar \(n)")
        }
        
        let ch = Character(u)
        if bytes.count + ch.utf8.count > maxStringLength {
            throw JsonInputError.stringTooLong
        }
        
        let appended = ch.utf8.withContiguousStorageIfAvailable { buf in
            bytes.append(buf.baseAddress!, count: buf.count)
            return buf.count
        }

        if appended == nil {
            bytes.append(contentsOf: Array(ch.utf8))
        }
    }
    
    func readHex() throws -> Int {
        var n = 0
        
        for _ in 0..<4 {
            guard let c = try nextByte() else {
                throw JsonInputError.unexpectedEndOfInput
            }
            
            switch c {
            case Ascii.zero...Ascii.nine:
                n = n * 16 + Int(c - Ascii.zero)
            case Ascii.a...Ascii.f:
                n = n * 16 + Int(c - Ascii.a) + 10
            case Ascii.A...Ascii.F:
                n = n * 16 + Int(c - Ascii.A) + 10
            default:
                throw JsonInputError.invalidEscapeSequence("Invalid hex character \(Character(UnicodeScalar(c)))")
            }
        }

        return n
    }
        
    func isStartOfNumber(_ c: UInt8) -> Bool {
        return (c >= Ascii.zero && c <= Ascii.nine) || c == Ascii.minus
    }
    
    func mustRead(_ s: String) throws {
        for expected in s.utf8 {
            guard let c = try nextByte() else {
                throw JsonInputError.unexpectedEndOfInput
            }
            guard c == expected else {
                throw unexpectedInput(c, expected: String(UnicodeScalar(expected)))
            }
        }
    }

    func pushState(_ newState: ParseState) {
        state.append(newState)
    }
    
    @discardableResult
    func popState() throws -> ParseState {
        if state.count < 2 {
            throw JsonInputError.unexpected("Attempt to pop root state. This is never valid")
        }
        return state.popLast()!
    }
    
    @discardableResult
    func popPath() -> JsonKey? {
        return path.popLast()
    }
    
    func unexpectedInput(_ c: UInt8, expected: String? = nil) -> JsonInputError {
        var message = ""
        if let expected = expected {
            message += "Expected \(expected) but got "
        }
        message += "\(UnicodeScalar(c))\(readRaw(20))"
        return JsonInputError.unexpectedInput(message)
    }
    
    func readRaw(_ count: Int) -> String {
        var s = readRawAvailable(count)
        if s.utf8.count < count {
            if let _ = try? readStream() {
                s.append(readRawAvailable(count - s.utf8.count))
            }
        }
                
        return s
    }
    
    func readRawAvailable(_ count: Int) -> String {
        let n = min(count, end - pos)
        if n < 1 {
            return ""
        }
        
        let s = String(unsafeUninitializedCapacity: n) { strbuf in
            _ = strbuf.initialize(fromContentsOf: buf[pos..<pos+n])
            pos += n
            return n
        }
        
        return s
    }
        
    func isWhitespace(_ c: UInt8) -> Bool {
        return c == Ascii.space || c == Ascii.lf || c == Ascii.tab || c == Ascii.cr
    }
            
    func nextByte() throws -> UInt8? {
        if pos == end {
            try readStream()
            if pos == end {
                return nil
            }
        }
        
        let c = buf[pos]
        pos += 1
        
        if c == 0 {
            return nil
        }
        
        return c
    }
    
    func pushback() {
        pos -= 1
    }
        
    func nextContentByte() throws -> UInt8? {
        while let c = try nextByte() {
            if !isWhitespace(c) {
                return c
            }
        }
        return nil
    }

    func nextByteUnchecked() -> UInt8 {
        pos += 1
        return buf[pos - 1]
    }
            
    @discardableResult
    func readStream() throws -> Bool {
        let res = stream.read(buf.baseAddress!, maxLength: Self.bufferCapacity)
        guard res > -1 else {
            throw stream.streamError ?? JsonInputError.ioError("Stream error")
        }
        
        end = res
        pos = 0
        
        return end > 0
    }
}
