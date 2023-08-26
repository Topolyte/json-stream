import XCTest
@testable import JsonStream

final class JsonOutputStreamTests: XCTestCase {

    func testRootLiterals() throws {
        var jos = makeStream()
        try jos.write(1.2)
        XCTAssertEqual(toString(jos), "1.2")
        
        jos = makeStream()
        try jos.write("abc 123")
        XCTAssertEqual(toString(jos), #""abc 123""#)
        
        jos = makeStream()
        try jos.write(true)
        XCTAssertEqual(toString(jos), "true")
        
        jos = makeStream()
        try jos.write(false)
        XCTAssertEqual(toString(jos), "false")

        jos = makeStream()
        try jos.writeNull()
        XCTAssertEqual(toString(jos), "null")
    }
    
    func testArray() throws {
        let jos = makeStream()
        try jos.writeArray { array in
            try array.write("abc 123")
            try array.writeArray { nested in
                try nested.write(11)
                try nested.write(true)
            }
        }
        
        XCTAssertEqual(toString(jos), #"["abc 123",[11,true]]"#)
    }
    
    func testObject() throws {
        let jos = makeStream()
        try jos.writeObject { obj in
            try obj.write("string", "abc 123")
            try obj.writeArray("values") { array in
                try array.writeNull()
                try array.write(false)
                try array.writeObject { _ in
                    //empty
                }
            }
            try obj.write("number", 11.22)
        }
        
        XCTAssertEqual(toString(jos), #"{"string":"abc 123","values":[null,false,{}],"number":11.22}"#)
    }
    
    func testStringEscaping() throws {
        let jos = makeStream()
        let s = "line one\nline two\n\tindented"
        try jos.write(s)
        XCTAssertEqual(toString(jos), "\"line one\\nline two\\n\\tindented\"")
    }
    
    func testJsonLinesFormat() throws {
        let jos = makeStream()
        
        try jos.writeObject { obj in
            try obj.write("the key", "abc 123")
            try obj.write("num", 11)
        }
        try jos.newLine()
        try jos.writeObject { obj in
            try obj.write("the key", "bcd 234")
            try obj.write("num", 12)
        }
        
        XCTAssertEqual(toString(jos), """
        {"the key":"abc 123","num":11}
        {"the key":"bcd 234","num":12}
        """)
    }
    
    
    func makeStream() -> JsonOutputStream {
        let memStream = OutputStream(toMemory: ())
        let jos = JsonOutputStream(stream: memStream)
        return jos
    }
    
    func toString(_ stream: JsonOutputStream) -> String {
        if let data = stream.stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data {
            return String(data: data, encoding: .utf8)!
        }
        return "Error: Not a memory stream"
    }
}
