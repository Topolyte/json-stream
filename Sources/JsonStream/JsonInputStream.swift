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
        case valueTooLong
        case invalidUTF8
        case unescapedControlCharacter
        case invalidEscapeSequence
        case unexpectedError
    }

    public let kind: ErrorKind
    public let line: Int
    public let message: String?
    
    public var description: String {
        if let message = message {
            return "Line \(line): \(kind) \(message)"
        }
        
        return "Line \(line): \(kind)"
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
}

public enum JsonNumber: Equatable {
    case int(Int64)
    case double(Double)
    case decimal(Decimal)
}

public enum JsonToken: Equatable {
    case startObject(_ key: JsonKey?)
    case endObject(_ key: JsonKey?)
    case startArray(_ key: JsonKey?)
    case endArray(_ key: JsonKey?)
    case string(_ key: JsonKey?, _ value: String)
    case number(_ key: JsonKey?, _ value: JsonNumber)
    case bool(_ key: JsonKey?, _ value: Bool)
    case null(_ key: JsonKey?)
}
    
public final class JsonInputStream: Sequence, IteratorProtocol {
    enum ParseState {
        case root
        case object(Int)
        case array(Int)
    }
    
    public enum NumberParsing {
        case intDouble
        case allDecimal
    }

    public static let defaultBufferCapacity = 1024 * 1024
    public static let defaultMaxValueLength = 1024 * 1024 * 10
    public static let defaultNumberParsing = NumberParsing.intDouble
    
    public private(set) var line = 1
    public private(set) var path = [JsonKey]()
    
    let stream: InputStream
    let closeStream: Bool
    let buf: UnsafeMutableBufferPointer<UInt8>
    let bufferCapacity: Int
    let maxValueLength: Int
    let numberParsing: NumberParsing

    var strbuf = Data()
    var numbuf = ""
    var pos = 0
    var end = 0
    var arrayIndex = 0
    var state = [ParseState.root]
    var rootValueSeen = false

    public init(stream: InputStream,
                closeStream: Bool = true,
                bufferCapacity: Int? = nil,
                maxValueLength: Int? = nil,
                numberParsing: NumberParsing? = nil) throws
    {
        self.stream = stream
        
        if self.stream.streamStatus == .notOpen {
            self.stream.open()
            self.closeStream = true
        } else {
            self.closeStream = closeStream
        }
        
        self.bufferCapacity = bufferCapacity ?? Self.defaultBufferCapacity
        self.buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: self.bufferCapacity)
        self.maxValueLength = maxValueLength ?? Self.defaultMaxValueLength
        self.numberParsing = numberParsing ?? Self.defaultNumberParsing
    }

    public convenience init(filePath: String,
                            bufferCapacity: Int? = nil,
                            maxValueLength: Int? = nil,
                            numberParsing: NumberParsing? = nil) throws
    {
        guard let istr = InputStream(fileAtPath: filePath) else {
            throw JsonInputError(kind: .ioError, line: 1, message: "Failed to open \(filePath)")
        }

        istr.open()
        try checkStreamStatus(istr, path: filePath)
        
        try self.init(stream: istr,
                      closeStream: true,
                      bufferCapacity: bufferCapacity,
                      maxValueLength: maxValueLength,
                      numberParsing: numberParsing)
    }

    public convenience init(data: Data,
                            bufferCapacity: Int? = nil,
                            maxValueLength: Int? = nil,
                            numberParsing: NumberParsing? = nil) throws
    {
        let istr = InputStream(data: data)
        istr.open()
        try checkStreamStatus(istr, path: "")
        
        try self.init(stream: istr,
                      closeStream: true,
                      bufferCapacity: bufferCapacity,
                      maxValueLength: maxValueLength,
                      numberParsing: numberParsing)
    }

    deinit {
        if closeStream {
            stream.close()
        }
        buf.deallocate()
    }
    
    public var pathString: String {
        var res = ""
        
        for key in path {
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
    
    public func pathMatch(_ keys: JsonKey...) -> Bool {
        var k = 0
        var p = 0
        
        while p < path.count && k < keys.count {
            if keys[k] == path[p] {
                k += 1
            }
            p += 1
        }
        
        return k == keys.count
    }
            
    public func read() throws -> JsonToken? {
        guard var c = try nextContentByte() else {
            guard case .root = state.last else {
                throw err(.unexpectedEOF)
            }
            guard rootValueSeen else {
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
                return .endObject(path.last)
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
            path.append(key)
            
            guard let value = try readValue(key) else {
                throw err(.unexpectedEOF)
            }
            
            return value
        case .array:
            if c == Ascii.rightSquare {
                guard case let .array(index) = try popState() else {
                    throw err(.unexpectedError, "Expected array parsing state")
                }
                if index >= 0 {
                    popPath()
                }
                return .endArray(path.last)
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
            path.append(key)
            pushback()
            return try readValue(key)
        case .root:
            pushback()
            let token = try readValue(nil)
            
            if rootValueSeen {
                throw errUnexpectedInput(c, expected: "End of input")
            }
            rootValueSeen = true
            
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
    
    public func next() -> Result<JsonToken, Error>? {
        do {
            if let token = try read() {
                return .success(token)
            }
            return nil
        } catch {
            return .failure(error)
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
                return try .number(key, readNumber())
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

    func readNumber() throws -> JsonNumber {
        switch numberParsing {
        case .intDouble:
            let n = try readInt()
            
            guard let c = try nextByte() else {
                return .int(n)
            }
            
            if c == Ascii.dot || c == Ascii.e || c == Ascii.E || isDigit(c) {
                pushback()
                return try .double(readDouble(n))
            } else {
                pushback()
                return .int(n)
            }
        case .allDecimal:
            return try .decimal(readDecimal())
        }
    }
    
    func readDecimal() throws -> Decimal {
        func numbufAppend(_ c: UInt8) throws {
            if numbuf.utf8.count == maxValueLength {
                throw err(.valueTooLong)
            }
            numbuf.append(Character(UnicodeScalar(c)))
        }
        
        func digits(signed: Bool, allowLeadingZero: Bool) throws {
            guard var c = try nextByte() else {
                throw err(.unexpectedEOF)
            }
            
            if c == Ascii.minus || c == Ascii.plus {
                guard signed else {
                    throw errUnexpectedInput(c, expected: "decimal digits")
                }
                try numbufAppend(c)
                guard let next = try nextByte() else {
                    throw err(.unexpectedEOF)
                }
                c = next
            }
            
            guard isDigit(c) else {
                throw errUnexpectedInput(c)
            }
            
            numbuf.append(Character(UnicodeScalar(c)))
            let first = c
            var digitsCount = 1
            
            while let c = try nextByte(), isDigit(c) {
                try numbufAppend(c)
                digitsCount += 1
            }
            
            guard digitsCount == 1 || first != Ascii.zero || allowLeadingZero else {
                throw errUnexpectedInput(Ascii.zero)
            }
            
            pushback()
        }
        
        func optionalFraction() throws {
            guard let c = try nextByte() else {
                return
            }
            
            if c == Ascii.dot {
                try numbufAppend(c)
                try digits(signed: false, allowLeadingZero: true)
                return
            }
            
            pushback()
            return
        }
        
        func optionalExponent() throws {
            guard let c = try nextByte() else {
                return
            }
            
            guard c == Ascii.e || c == Ascii.E else {
                pushback()
                return
            }
            
            try numbufAppend(Ascii.e)
            try digits(signed: true, allowLeadingZero: false)
        }
        
        numbuf.removeAll(keepingCapacity: true)
        try digits(signed: true, allowLeadingZero: false)
        try optionalFraction()
        try optionalExponent()
        
        guard let d = Decimal(string: numbuf) else {
            throw err(.unexpectedInput, numbuf)
        }
        
        return d
    }
        
    func readDouble(_ prefix: Int64) throws -> Double {
        let sign = prefix >= 0 ? 1.0 : -1.0
        var d = abs(Double(prefix))
        var pointSeen = false
        
        while true {
            guard let c = try nextByte() else {
                return d * sign
            }
            
            if c == Ascii.dot {
                if pointSeen {
                    throw errUnexpectedInput(c)
                }
                pointSeen = true
                d += try readFraction()
            } else if c == Ascii.e || c == Ascii.E {
                let exp = try Double(readInt())
                d *= pow(10.0, exp)
                break
            } else if isDigit(c) {
                pushback()
                let n = try Double(readInt())
                d = d * pow(10, digitsCount(n)) + n
            } else {
                pushback()
                break
            }
        }
        
        return d * sign
    }
    
    func readFraction() throws -> Double {
        var d = 0.0
        var zeroCount = 0
        
        while let c = try nextByte(), isDigit(c) {
            if c == Ascii.zero {
                zeroCount += 1
            } else {
                pushback()
                let n = try Double(readInt(signed: false))
                let nDigits = digitsCount(n) + Double(zeroCount)
                d = d + n * pow(10, -nDigits)
                zeroCount = 0
            }
        }
        
        if d.isZero && zeroCount == 0 {
            guard let c = try nextByte() else {
                throw err(.unexpectedEOF)
            }
            throw errUnexpectedInput(c, expected: "digits")
        }
        
        pushback()
        
        return d
    }
            
    func readInt(signed: Bool = true) throws -> Int64 {
        var sign: Int64 = 1
        
        guard var c = try nextByte() else {
            throw err(.unexpectedEOF)
        }
        
        if c == Ascii.minus || c == Ascii.plus {
            if c == Ascii.minus {
                if !signed {
                    throw errUnexpectedInput(c, expected: "number")
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
        
        let hasLeadingZero = c == Ascii.zero
        var n: Int64 = Int64(c - Ascii.zero)
        var nDigits = 1
        
        while let c = try nextByte() {
            if isDigit(c) && nDigits < 18 {
                n = n * 10 + Int64(c - Ascii.zero)
                nDigits += 1
            } else {
                pushback()
                break
            }
        }
        
        if hasLeadingZero && nDigits > 1 {
            throw err(.unexpectedInput, "Number with leading zero")
        }
                
        return n * sign
    }
    
    func digitsCount(_ d: Double) -> Double {
        return floor(log10(d)) + 1
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
            if strbuf.count >= maxValueLength {
                throw err(.valueTooLong, validStringPrefix(strbuf, count: 50))
            }
            
            if c == Ascii.backslash {
                try readEscape()
            } else if c == Ascii.quote {
                guard let s = String(data: strbuf, encoding: .utf8) else {
                    throw err(.invalidUTF8)
                }
                return s
            } else if isControlCharacter(c) {
                throw err(.unescapedControlCharacter,
                          "\(c) in \(validStringPrefix(strbuf, count: 20))")
            } else {
                strbuf.append(c)
            }
        }
        
        throw err(.unexpectedEOF)
    }
    
    func isControlCharacter(_ c: UInt8) -> Bool {
        (0...0x1F).contains(c)
    }
    
    func validStringPrefix(_ data: Data, count: Int) -> String {
        if data.count < 1 || count < 1 {
            return ""
        }
        
        let len = Swift.min(count, data.count)
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
        var n = try readHex()
        
        if isHighSurrogate(n) {
            try mustRead("\\u")
            let lowSurrogate = try readHex()
            n = surrogatePairToCodePoint(n, lowSurrogate)
        }
        
        guard let u = UnicodeScalar(n) else {
            throw err(.invalidEscapeSequence, "Invalid unicode scalar \(n)")
        }
        
        let ch = Character(u)
        if strbuf.count + ch.utf8.count >= maxValueLength {
            throw err(.valueTooLong, validStringPrefix(strbuf, count: 50))
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
    
    func isHighSurrogate(_ n: Int) -> Bool {
        (0xD800...0xDBFF).contains(n)
    }
    
    func isLowSurrogate(_ n: Int) -> Bool {
        (0xDC00...0xDFFF).contains(n)
    }
    
    func surrogatePairToCodePoint(_ high: Int, _ low: Int) -> Int {
        (high - 0xD800) * 0x400 + low - 0xDC00 + 0x10000
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
        return path.popLast()
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
        let n = Swift.min(count, end - pos)
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
        
        return c
    }
    
    func pushback() {
        guard pos > 0 else {
            return
        }
        
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

func checkStreamStatus(_ stream: InputStream, path: String) throws {
    if let error = stream.streamError {
        throw JsonInputError(kind: .ioError, line: 1, message: "Path: \(path), \(error)")
    }
    
    if stream.streamStatus != .open && stream.streamStatus != .atEnd {
        throw JsonInputError(
            kind: .ioError, line: 1,
            message: "Path: \(path), unexpected stream status: \(statusDescription(stream.streamStatus))")
    }
}
