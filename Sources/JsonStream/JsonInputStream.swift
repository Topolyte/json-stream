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

public struct JsonInputError: Error, CustomStringConvertible {
    public enum ErrorKind {
        case ioError
        case unexpectedInput
        case unexpectedEOF
        case stringTooLong
        case invalidUTF8
        case invalidEscapeSequence
        case unexpectedError
    }

    public let kind: ErrorKind
    public let line: Int
    public let message: String?
    
    public var description: String {
        if let message = message {
            return "\(line) \(kind) \(message)"
        }
        
        return "\(line) \(kind)"
    }
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
        case let (.string(key1, val1), .string(key2, val2)):
            return key1 == key2 && val1 == val2
        case let (.number(key1, val1), .number(key2, val2)):
            return key1 == key2 && val1 == val2
        case let (.bool(key1, val1), .bool(key2, val2)):
            return key1 == key2 && val1 == val2
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

    public static let defaultBufferCapacity = 1024 * 1024
    public static let defaultMaxStringLength = 1024 * 1024 * 10
    
    public private(set) var line = 1
    public private(set) var keyPath = [JsonKey]()
    
    let stream: InputStream
    let isOwningStream: Bool
    let buf: UnsafeMutableBufferPointer<UInt8>
    let bufferCapacity: Int
    let maxStringLength: Int

    var strbuf = Data()
    var pos = 0
    var end = 0
    var arrayIndex = 0
    var state = [ParseState.root]

    public init(stream: InputStream, isOwningStream: Bool = true,
                bufferCapacity: Int? = nil, maxStringLength: Int? = nil) throws {
        
        self.stream = stream
        self.isOwningStream = isOwningStream
        self.bufferCapacity = bufferCapacity ?? Self.defaultBufferCapacity
        self.buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: self.bufferCapacity)
        self.maxStringLength = maxStringLength ?? Self.defaultMaxStringLength
        
        try checkStreamStatus()
    }

    public convenience init(filePath: String, bufferCapacity: Int? = nil,
                            maxStringLength: Int? = nil) throws {
        
        guard let istr = InputStream(fileAtPath: filePath) else {
            throw JsonInputError(kind: .ioError, line: 1, message: "Failed to open \(filePath)")
        }

        istr.open()
        try self.init(stream: istr, isOwningStream: true)
    }
    
    deinit {
        if isOwningStream {
            stream.close()
        }
        buf.deallocate()
    }
    
    public var keyPathString: String {
        var res = ""
        
        for key in keyPath {
            switch key {
            case .index(let i):
                res.append("[\(i)]")
            case .name(let name):
                if !res.isEmpty {
                    res.append(".")
                }
                res.append(name)
            }
        }
        
        return res
    }
        
    public func read() throws -> JsonToken? {
        guard var c = try nextContentByte() else {
            guard case .root = state.last else {
                throw err(.unexpectedEOF)
            }
            return nil
        }
        
        switch state.last! {
        case .object:
            if c == Ascii.rightBrace {
                guard case let .object(index) = try popState() else {
                    throw err(.unexpectedError, "Expected object parsing state")
                }
                if index >= 0 {
                    popPath()
                }
                return .endObject(keyPath.last)
            }
            
            let nextIndex = try incrementObjectIndex()
                        
            if c == Ascii.comma {
                guard nextIndex > 0 else {
                    throw errUnexpectedInput(c, expected: "property")
                }
                popPath()
                if let next = try nextContentByte() {
                    c = next
                } else {
                    throw err(.unexpectedEOF)
                }
            } else if nextIndex != 0 {
                throw errUnexpectedInput(c, expected: ",")
            }
            
            guard c == Ascii.quote else {
                throw errUnexpectedInput(c, expected: "\"")
            }
            
            let key = try JsonKey.name(readPropertyName())
            keyPath.append(key)
            return try readValue(key)
        case .array:
            if c == Ascii.rightSquare {
                guard case let .array(index) = try popState() else {
                    throw err(.unexpectedError, "Expected array parsing state")
                }
                if index >= 0 {
                    popPath()
                }
                return .endArray(keyPath.last)
            }
            
            let nextIndex = try incrementArrayIndex()
            
            if c == Ascii.comma {
                guard nextIndex > 0 else {
                    throw errUnexpectedInput(c, expected: "array element")
                }
                guard case .index = popPath() else {
                    throw err(.unexpectedError, "Path not ending with array index")
                }
                if let next = try nextContentByte() {
                    c = next
                } else {
                    throw err(.unexpectedEOF)
                }
            } else if nextIndex != 0 {
                throw errUnexpectedInput(c, expected: ",")
            }
            
            let key = JsonKey.index(nextIndex)
            keyPath.append(key)
            pushback()
            return try readValue(key)
        case .root:
            pushback()
            let token = try readValue(nil)
            switch token {
            case .startObject, .startArray:
                return token
            default:
                let next = try nextContentByte()
                guard next == nil else {
                    throw errUnexpectedInput(next!)
                }
                return token
            }
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
                pushback()
                return try .number(key, readDouble())
            } else {
                throw errUnexpectedInput(c)
            }
        }
    }
    
    func incrementObjectIndex() throws -> Int {
        guard case let .object(index) = try popState() else {
            throw err(.unexpectedError, "Expected object state")
        }
        
        let newIndex = index + 1
        pushState(.object(newIndex))
        return newIndex
    }
    
    func incrementArrayIndex() throws -> Int {
        guard case let .array(index) = try popState() else {
            throw err(.unexpectedError, "Expected array state")
        }
        
        let newIndex = index + 1
        pushState(.array(newIndex))
        return newIndex
    }
    
    func readDouble() throws -> Double {
        var d: Double
        
        guard let n = try readDigits() else {
            throw err(.unexpectedEOF)
        }
        
        d = n
                
        guard var c = try nextByte() else {
            return d
        }
        
        if c == Ascii.dot {
            guard let n = try readDigits(signed: false) else {
                throw err(.unexpectedEOF)
            }
            
            if n > 0 {
                let digits = floor(log10(n)) + 1
                let frac = n * pow(10.0, digits * -1)
                
                if d >= 0 {
                    d += frac
                } else {
                    d -= frac
                }
            }

            guard let next = try nextByte() else {
                return d
            }
            
            c = next
        }
                
        if c == Ascii.e || c == Ascii.E {
            guard let n = try readDigits() else {
                throw errUnexpectedInput(c, expected: "number")
            }
            
            d *= pow(10.0, n)
        } else {
            pushback()
        }
        
        return d
    }
    
    func readDigits(signed: Bool = true) throws -> Double? {
        var sign = 1
        
        guard var c = try nextByte() else {
            return nil
        }
        
        if c == Ascii.minus || c == Ascii.plus {
            if c == Ascii.minus {
                if !signed {
                    throw errUnexpectedInput(c, expected: "digits")
                }
                sign = -1
            }
         
            guard let next = try nextByte() else {
                throw err(.unexpectedEOF)
            }
            
            c = next
        }
        
        guard isDigit(c) else {
            throw errUnexpectedInput(c, expected: "number")
        }
        
        var d = 0.0
        var n = UInt64(c - Ascii.zero)
        var nDigits = 1
        var overflow = false
        
        while let c = try nextByte() {
            if isDigit(c) {
                if nDigits < 19 {
                    n = n * 10 + UInt64(c - Ascii.zero)
                    nDigits += 1
                } else {
                    d = d * pow(10.0, Double(nDigits)) + Double(n)
                    n = UInt64(c - Ascii.zero)
                    nDigits = 1
                    overflow = true
                }
            } else {
                pushback()
                break
            }
        }
        
        if !overflow {
            d = Double(n)
        } else {
            d = d * pow(10, Double(nDigits)) + Double(n)
        }
        
        return d * Double(sign)
    }
    
    func isDigit(_ c: UInt8) -> Bool {
        Ascii.zero...Ascii.nine ~= c
    }
    
    func readPropertyName() throws -> String {
        let propertyName = try readString()
        
        guard let c = try nextContentByte() else {
            throw err(.unexpectedEOF)
        }
        
        guard c == Ascii.colon else {
            throw errUnexpectedInput(c, expected: ":")
        }

        return propertyName
    }
    
    func readString() throws -> String {
        strbuf.removeAll(keepingCapacity: true)
        
        while let c = try nextByte() {
            if strbuf.count >= maxStringLength {
                throw err(.stringTooLong, validStringPrefix(strbuf, count: 50))
            }
            
            if c == Ascii.backslash {
                try readEscape()
            } else if c == Ascii.quote {
                guard let s = String(data: strbuf, encoding: .utf8) else {
                    throw err(.invalidUTF8)
                }
                return s
            } else {
                strbuf.append(c)
            }
        }
        
        throw err(.unexpectedEOF)
    }
    
    func validStringPrefix(_ data: Data, count: Int) -> String {
        if data.count < 1 || count < 1 {
            return ""
        }
        
        let len = min(count, data.count)
        var end = len - 1
        
        while end > 0 && !isUtf8Start(data[end]) {
            end -= 1
        }
        
        if !isUtf8Start(data[end]) {
            return ""
        }
        
        guard var s = String(data: data[0...end], encoding: .utf8) else {
            return ""
        }
        
        if count > end {
            s += "..."
        }
        
        return s
    }
    
    func isUtf8Start(_ c: UInt8) -> Bool {
        c <= 0x7F
    }
    
    func readEscape() throws {
        guard let c = try nextByte() else {
            throw err(.unexpectedEOF)
        }
        
        switch c {
        case Ascii.n:
            strbuf.append(Ascii.lf)
        case Ascii.quote, Ascii.backslash, Ascii.slash:
            strbuf.append(c)
        case Ascii.t:
            strbuf.append(Ascii.tab)
        case Ascii.u:
            try readHexEscape()
        case Ascii.r:
            break
        case Ascii.b:
            strbuf.append(Ascii.backspace)
        case Ascii.f:
            strbuf.append(Ascii.formFeed)
        default:
            throw err(.invalidEscapeSequence, "\\\(Character(UnicodeScalar(c)))")
        }
    }
    
    func readHexEscape() throws {
        let n = try readHex()
        
        guard let u = UnicodeScalar(n) else {
            throw err(.invalidEscapeSequence, "Invalid unicode scalar \(n)")
        }
        
        let ch = Character(u)
        if strbuf.count + ch.utf8.count >= maxStringLength {
            throw err(.stringTooLong, validStringPrefix(strbuf, count: 50))
        }
        
        let appended = ch.utf8.withContiguousStorageIfAvailable { buf in
            strbuf.append(buf.baseAddress!, count: buf.count)
            return buf.count
        }

        if appended == nil {
            strbuf.append(contentsOf: Array(ch.utf8))
        }
    }
    
    func readHex() throws -> Int {
        var n = 0
        
        for _ in 0..<4 {
            guard let c = try nextByte() else {
                throw err(.unexpectedEOF)
            }
            
            switch c {
            case Ascii.zero...Ascii.nine:
                n = n * 16 + Int(c - Ascii.zero)
            case Ascii.a...Ascii.f:
                n = n * 16 + Int(c - Ascii.a) + 10
            case Ascii.A...Ascii.F:
                n = n * 16 + Int(c - Ascii.A) + 10
            default:
                throw err(.invalidEscapeSequence, "Invalid hex character \(Character(UnicodeScalar(c)))")
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
                throw err(.unexpectedEOF)
            }
            guard c == expected else {
                throw errUnexpectedInput(c, expected: String(UnicodeScalar(expected)))
            }
        }
    }

    func pushState(_ newState: ParseState) {
        state.append(newState)
    }
    
    @discardableResult
    func popState() throws -> ParseState {
        if state.count < 2 {
            throw err(.unexpectedError,
                        "Attempt to pop root state. This is never valid")
        }
        return state.popLast()!
    }
    
    @discardableResult
    func popPath() -> JsonKey? {
        return keyPath.popLast()
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

        if c == Ascii.lf {
            line += 1
        }

        if c == 0 {
            return nil
        }
        
        return c
    }
    
    func pushback() {
        pos -= 1
        
        if buf[pos] == Ascii.lf {
            line -= 1
        }
    }
        
    func nextContentByte() throws -> UInt8? {
        while let c = try nextByte() {
            if !isWhitespace(c) {
                return c
            }
        }
        return nil
    }
            
    @discardableResult
    func readStream() throws -> Bool {
        let n = stream.read(buf.baseAddress!, maxLength: bufferCapacity)
        
        guard n > -1 else {
            let status = " [\(stream.streamStatus)]"
            
            if let error = stream.streamError {
                throw err(.ioError, String(describing: error) + status)
            } else {
                throw err(.ioError, "Stream error" + status)
            }
        }
        
        end = n
        pos = 0
        
        return end > 0
    }
    
    func checkStreamStatus() throws {
        if let error = stream.streamError {
            throw JsonInputError(kind: .ioError, line: line, message: "\(error)")
        }
        
        if stream.streamStatus != .open && stream.streamStatus != .atEnd {
            throw JsonInputError(
                kind: .ioError, line: line,
                message: "Unexpected stream status: \(statusDescription(stream.streamStatus))")
        }
    }
        
    func err(_ kind: JsonInputError.ErrorKind, _ message: String? = nil) -> JsonInputError {
        JsonInputError(kind: kind, line: line, message: message)
    }
    
    func errUnexpectedInput(_ c: UInt8, expected: String? = nil) -> JsonInputError {
        var message = ""
        if let expected = expected {
            message += "Expected \(expected) but got "
        }
        
        let line = self.line
        message += "\(UnicodeScalar(c))\(readRaw(20))"
        
        return JsonInputError(kind: .unexpectedInput, line: line, message: message)
    }
}
