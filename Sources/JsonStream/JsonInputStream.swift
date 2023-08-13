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

public enum JsonParseState {
    case object
    case array
    case property(String)
    case element(Int)
}

public enum JsonToken {
    case startObject
    case endObject
    case startArray
    case endArray
    case startProperty(String)
    case endProperty
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
}
    
public final class JsonInputStream {
    public static var bufferCapacity = 1024 * 4
    
    let stream: InputStream
    let isOwningStream: Bool
    public var maxStringLength = 1024 * 1024 * 10
    
    private let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bufferCapacity)
    private var bytes = Data()
    private var pos = 0
    private var end = 0
    
    public private(set) var context = [JsonParseState]()
    
    public init(path: String) throws {
        guard let stream = InputStream(fileAtPath: path) else {
            throw JsonError.ioError("Failed to open input stream for \(path)")
        }
        
        stream.open()
        
        self.stream = stream
        self.isOwningStream = true
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
    
    public func read() throws -> JsonToken? {
        if let c = try nextContentByte() {
            switch c {
            case asciiLeftBrace:
                context.append(.object)
                return .startObject
            case asciiRightBrace:
                pop()
                return .endObject
            case asciiLeftSquare:
                context.append(.array)
                return .startArray
            case asciiRightSquare:
                pop()
                return .endArray
            case asciiQuote:
                if case .some(.object) = context.last {
                    let propertyName = try readPropertyStart()
                    context.append(.property(propertyName))
                    return .startProperty(propertyName)
                } else if case .some(.property) = context.last {
                    let stringValue = try readString()
                    pop()
                    try skipComma()
                    return .string(stringValue)
                } else if case .some(.array) = context.last {
                    let stringValue = try readString()
                    try skipComma()
                    return .string(stringValue)
                } else { // root level string
                    return try .string(readString())
                }
            default:
                if c == asciin {
                    try mustRead("ull")
                    if case .some(.property) = context.last {
                        pop()
                    }
                    return .null
                } else if c == asciit {
                    try mustRead("rue")
                    return .bool(true)
                } else if c == asciif {
                    try mustRead("alse")
                    return .bool(false)
                } else {
                    let d = try readDouble(c)
                    if floor(d) == d {
                        return .int(Int(d))
                    }
                    return .double(d)
                }
            }
        } else {
            return nil
        }
    }
    
    func readDouble(_ firstChar: UInt8) throws -> Double {
        var str = String(UnicodeScalar(firstChar))
        
        while let c = try nextByte() {
            if isWhitespace(c) || c == asciiComma || c == asciiRightBrace || c == asciiRightSquare {
                pos -= 1
                break
            }
            
            switch c {
            case asciiZero...asciiNine, asciiDot, asciie, asciiE, asciiPlus, asciiMinus:
                if str.utf8.count == maxStringLength {
                    throw JsonError.stringTooLong
                }
                str.append(Character(UnicodeScalar(c)))
            default:
                throw JsonError.invalidNumber(str + String(UnicodeScalar(c)))
            }
        }
        
        guard let d = Double(str) else {
            throw JsonError.invalidNumber(str)
        }
        return d
    }
    
    func readPropertyStart() throws -> String {
        let propertyName = try readString()
        
        guard let c = try nextContentByte() else {
            throw JsonError.unexpectedEndOfStream
        }
        
        guard c == asciiColon else {
            throw try unexpected(c, expected: ":")
        }

        return propertyName
    }
    
    func readString() throws -> String {
        bytes.removeAll(keepingCapacity: true)
        
        while let c = try nextByte() {
            if bytes.count > maxStringLength {
                throw JsonError.stringTooLong
            }
            
            if c == asciiBackslash {
                try readEscape()
            } else if c == asciiQuote {
                guard let s = String(data: bytes, encoding: .utf8) else {
                    throw JsonError.invalidUTF8
                }
                return s
            } else {
                bytes.append(c)
            }
        }
        
        throw JsonError.unexpectedEndOfStream
    }
    
    func readEscape() throws {
        guard let c = try nextByte() else {
            throw JsonError.unexpectedEndOfStream
        }
        
        switch c {
        case asciin:
            bytes.append(asciiLf)
        case asciiQuote, asciiBackslash, asciiSlash:
            bytes.append(c)
        case asciit:
            bytes.append(asciiTab)
        case asciiu:
            try readHexEscape()
        case asciir:
            break
        case asciib:
            bytes.append(asciiBackspace)
        case asciif:
            bytes.append(asciiFormFeed)
        default:
            throw JsonError.invalidEscapeSequence("\\\(Character(UnicodeScalar(c)))")
        }
    }
    
    func readHexEscape() throws {
        let n = try readHex()
        
        guard let u = UnicodeScalar(n) else {
            throw JsonError.invalidEscapeSequence("Invalid unicode scalar \(n)")
        }
        
        let ch = Character(u)
        if bytes.count + ch.utf8.count > maxStringLength {
            throw JsonError.stringTooLong
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
                throw JsonError.unexpectedEndOfStream
            }
            
            switch c {
            case asciiZero...asciiNine:
                n = n * 16 + Int(c - asciiZero)
            case asciia...asciif:
                n = n * 16 + Int(c - asciia) + 10
            case asciiA...asciiF:
                n = n * 16 + Int(c - asciiA) + 10
            default:
                throw JsonError.invalidEscapeSequence("Invalid hex character \(Character(UnicodeScalar(c)))")
            }
        }

        return n
    }
        
    func isStartOfNumber(_ c: UInt8) -> Bool {
        return (c >= asciiZero && c <= asciiNine) || c == asciiMinus
    }
    
    func mustRead(_ s: String) throws {
        for expected in s.utf8 {
            guard let c = try nextByte() else {
                throw JsonError.unexpectedEndOfStream
            }
            guard c == expected else {
                throw try unexpected(c, expected: String(UnicodeScalar(expected)))
            }
        }
    }
    
    func skipComma() throws {
        guard let c = try nextContentByte() else {
            return
        }
        
        if c != asciiComma {
            pos -= 1
        }
    }
        
    func pop() {
        _ = context.popLast()
    }
                
    func unexpected(_ c: UInt8, expected: String? = nil) throws -> JsonError {
        var message = try String(UnicodeScalar(c)) + readRaw(20)
        if let expected = expected {
            message.append(". Expected \(expected)")
        }
        return JsonError.unexpectedContent(message)
    }
    
    func readRaw(_ count: Int) throws -> String {
        var s = try readRawAvailable(count)
        if s.utf8.count < count {
            if try readStream() {
                try s.append(readRawAvailable(count - s.utf8.count))
            }
        }
                
        return s
    }
    
    func readRawAvailable(_ count: Int) throws -> String {
        let n = min(count, end - pos)
        if n == 0 {
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
        return c == asciiSpace || c == asciiLf || c == asciiTab || c == asciiCr
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
        return c
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
            throw stream.streamError ?? JsonError.ioError("Stream error")
        }
        
        end = res
        
        return end - pos > 0
    }
}
