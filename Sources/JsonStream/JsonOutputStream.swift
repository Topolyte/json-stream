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

enum JsonContext {
    case root
    case object
    case array
    case primitive
}

public enum JsonOutputError: Error {
    case ioError(String)
    case invalidContext(String)
}

public class JsonOutputStream {
    var out: OutputStream
    let isOwningStream: Bool
    public var index: Int = -1
    let context: JsonContext
        
    public init(path: String) throws {
        guard let stream = OutputStream(toFileAtPath: path, append: false) else {
            throw JsonOutputError.ioError("Failed to open output stream for \(path)")
        }
        stream.open()
        self.out = stream
        self.isOwningStream = true
        self.context = .root
    }
    
    public init(stream: OutputStream) {
        self.out = stream
        self.isOwningStream = false
        self.context = .root
        
        if self.out.streamStatus == .notOpen {
            self.out.open()
        }
    }
    
    init(stream: OutputStream, context: JsonContext) {
        self.out = stream
        self.isOwningStream = false
        self.context = context
    }
    
    deinit {
        if isOwningStream {
            out.close()
        }
    }
        
    public func writeObject(f: (_ object: JsonOutputStream) throws -> ()) throws {
        try requireValueContext()
        try nextItem()
        try writeRaw("{")
        let jos = JsonOutputStream(stream: out, context: .object)
        try f(jos)
        try writeRaw("}")
    }
    
    public func writeObject(_ name: String, f: (_ object: JsonOutputStream) throws -> ()) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeRaw("{")
        let jos = JsonOutputStream(stream: out, context: .object)
        try f(jos)
        try writeRaw("}")
    }
            
    public func writeArray(f : (_ array: JsonOutputStream) throws -> ()) throws {
        try requireValueContext()
        try nextItem()
        try writeRaw("[")
        let jos = JsonOutputStream(stream: out, context: .array)
        try f(jos)
        try writeRaw("]")
    }
    
    public func writeArray(_ name: String, f: (_ array: JsonOutputStream) throws -> ()) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeRaw("[")
        let jos = JsonOutputStream(stream: out, context: .array)
        try f(jos)
        try writeRaw("]")
    }
    
    public func write(_ name: String, _ value: String) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeValue(value)
    }

    public func write<T: Numeric>(_ name: String, _ value: T) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeValue(value)
    }

    public func write(_ name: String, _ value: Bool) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeValue(value)
    }
    
    public func writeNull(_ name: String) throws {
        try requirePropertyContext()
        try nextItem()
        try writeKey(name)
        try writeNullValue()
    }
    
    public func writeNull() throws {
        try requireValueContext()
        try nextItem()
        try writeNullValue()
    }
    
    public func write(_ value: String) throws {
        try requireValueContext()
        try nextItem()
        try writeValue(value)
    }
    
    public func write<T: Numeric>(_ value: T) throws {
        try requireValueContext()
        try nextItem()
        try writeValue(value)
    }

    public func write(_ value: Bool) throws {
        try requireValueContext()
        try nextItem()
        try writeValue(value)
    }
    
    public func newLine() throws {
        try writeRaw("\n")
    }

    fileprivate func nextItem() throws {
        if context == .array || context == .object {
            index += 1
            if index > 0 {
                try writeRaw(",")
            }
        }
    }
    
    fileprivate func writeKey(_ name: String) throws {
        try writeValue(name)
        try writeRaw(":")
    }
    
    fileprivate func writeValue(_ value: String) throws {
        try writeRaw("\"")
        
        if value.utf8.contains(where: {
            $0 < Ascii.space ||
            $0 == Ascii.quote ||
            $0 == Ascii.backslash })
        {
            try writeRaw(escape(value))
        } else {
            try writeRaw(value)
        }
        
        try writeRaw("\"")
    }

    fileprivate func writeValue<T: Numeric>(_ n: T) throws {
        try writeRaw(String(describing: n))
    }
    
    fileprivate func writeValue(_ b: Bool) throws {
        if b {
            try writeRaw("true")
        } else {
            try writeRaw("false")
        }
    }
    
    fileprivate func writeNullValue() throws {
        try writeRaw("null")
    }
        
    fileprivate func writeRaw(_ s: String) throws {
        var str = s
        
        func writeContiguous(_ str: inout String) throws -> Bool {
            let count = try str.utf8.withContiguousStorageIfAvailable { buf in
                guard let p = buf.baseAddress else {
                    throw JsonOutputError.ioError("String buffer is nil")
                }
                
                let res = out.write(p, maxLength: buf.count)
                
                if res > 0 {
                    return res
                }
                
                if res == 0 {
                    throw JsonOutputError.ioError("Buffer capacity reached")
                }
                
                throw out.streamError ??
                    JsonOutputError.ioError(
                        "OutputStream.write() failed. streamStatus: \(out.streamStatus)")
            }
            
            return count != nil
        }
        
        if try !writeContiguous(&str) {
            str.makeContiguousUTF8()
            guard try writeContiguous(&str) else {
                throw JsonOutputError.ioError("Failed to write \(str) as contiguous UTF-8")
            }
        }
    }
    
    fileprivate func escape(_ s: String) -> String {
        var result = ""
        
        for c in s {
            if let ascii = c.asciiValue {
                switch ascii {
                case Ascii.quote:
                    result.append("\\\"")
                case Ascii.backslash:
                    result.append("\\")
                case Ascii.lf:
                    result.append("\\n")
                case Ascii.cr:
                    result.append("\\r")
                case Ascii.tab:
                    result.append("\\t")
                case Ascii.backspace:
                    result.append("\\b")
                case Ascii.formFeed:
                    result.append("\\f")
                default:
                    result.append(c)
                }
            } else {
                result.append(c)
            }
        }
        
        return result
    }
    
    fileprivate func requireContext(for itemType: String, _ validContexts: JsonContext...) throws {
        if !validContexts.contains(context) {
            throw JsonOutputError.invalidContext("\(itemType) not valid in \(context) context")
        }
    }
    
    fileprivate func requirePropertyContext() throws {
        try requireContext(for: "property", .object)
    }
    
    fileprivate func requireValueContext() throws {
        try requireContext(for: "value", .root, .array)
    }
}


