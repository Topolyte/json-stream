import XCTest
@testable import JsonStream

final class JsonInputStreamTests: XCTestCase {
    
    func testBasics() throws {
        let s = """
        {
            "type": "Captain",
            "name": "Jean-Luc Picard",
            "speed": {"quantity": 500.5e3, "unit": "m/s"},
            "isFrench": true,
            "height": null,
            "postings": ["USS-Enterprise-D", 2363, "USS-Enterprise-E", 2372],
            "boldness": 101
        }
        """
        let jis = try makeStream(s)
        
        let expected: [JsonToken] = [
            .startObject(nil),
            .string(.name("type"), "Captain"),
            .string(.name("name"), "Jean-Luc Picard"),
            .startObject(.name("speed")),
            .number(.name("quantity"), 500500.0),
            .string(.name("unit"), "m/s"),
            .endObject(.name("speed")),
            .bool(.name("isFrench"), true),
            .null(.name("height")),
            .startArray(.name("postings")),
            .string(.index(0), "USS-Enterprise-D"),
            .number(.index(1), 2363.0),
            .string(.index(2), "USS-Enterprise-E"),
            .number(.index(3), 2372.0),
            .endArray(.name("postings")),
            .number(.name("boldness"), 101.0),
            .endObject(nil)
        ]
        
        for token in expected {
            XCTAssertEqual(try jis.read(), token)
        }

        XCTAssertEqual(try jis.read(), nil)
    }
    
    func testNumber() throws {
        let valid = [
            ("1", 1.0),
            ("0", 0.0),
            ("1.23", 1.23),
            ("-11.234", -11.234),
            ("0.2233", 0.2233),
            ("12.40", 12.4),
            ("01.10", 1.1),
            ("-0.0", 0.0),
            ("1.23e+14", 1.23e14),
            ("1.23e-4", 1.23e-4),
            ("11e4", 110000.0),
            ("-12345678901234567890123456789.123", -12345678901234567890123456789.123),
            ("1234567890123456789", 1234567890123456789.0)
        ]
        
        let invalid = [
            ".1", "--1.2", "12,345.6", "12.34.56", "12 345", "12_345",
            "1.2a4", "0xABC", "1.2 e4", "12-e4", "12."
        ]
        
        for (s, n) in valid {
            let jis = try makeStream(s)
            XCTAssertEqual(try jis.read(), .number(nil, n))
        }
        
        for s in invalid {
            let jis = try makeStream(s)
            XCTAssertThrowsError(try consumeTokens(jis))
        }
    }
        
    func testNestedEmptyArrays() throws {
        let s = """
        [[]]
        """
        
        let jis = try makeStream(s)
        
        let expected: [JsonToken] = [
            .startArray(nil),
            .startArray(.index(0)),
            .endArray(.index(0)),
            .endArray(nil)
        ]
        
        for token in expected {
            print(token)
            XCTAssertEqual(try jis.read(), token)
        }
        
        XCTAssertEqual(try jis.read(), nil)
    }
    
    func testNestedObjects() throws {
        var s = """
        [{},{}]
        """
        
        var jis = try makeStream(s)
        
        var expected: [JsonToken] = [
            .startArray(nil),
            .startObject(.index(0)),
            .endObject(.index(0)),
            .startObject(.index(1)),
            .endObject(.index(1)),
            .endArray(nil)
        ]
        
        for token in expected {
            print(token)
            XCTAssertEqual(try jis.read(), token)
        }
        
        XCTAssertEqual(try jis.read(), nil)
        
        s = #"{"a":{"b":{"c":111}}}"#
        jis = try makeStream(s)
        expected = [
            .startObject(nil),
            .startObject(.name("a")),
            .startObject(.name("b")),
            .number(.name("c"), 111.0),
            .endObject(.name("b")),
            .endObject(.name("a")),
            .endObject(nil)
        ]
        
        for token in expected {
            print(token)
            XCTAssertEqual(try jis.read(), token)
        }

        XCTAssertEqual(try jis.read(), nil)
    }
    
    func testMisplacedComma() throws {
        var s = """
        [, 1, 2, 3]
        """
        var jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Leading comma in array") { err in
            print(err)
        }
        
        s = """
        [1, 2,]
        """
        jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Trailing comma in array") { err in
            print(err)
        }

        s = """
        {, "a": 1, "b": 2}
        """
        jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Leading comma in object") { err in
            print(err)
        }

        s = """
        {"a": 1, "b": 2 ,}
        """
        jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Trailing comma in object") { err in
            print(err)
        }
    }
    
    func testUnbalancedBrackets() throws {
        var s = """
        [[]
        """
        var jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis, printTokens: true), "Orphan left bracket in array") { err in
            print(err)
        }
        
        s = """
        {"a":1,
        """
        jis = try makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis, printTokens: true), "Orphan left bracket in array") { err in
            print(err)
        }
    }
    
    func testStringEscaping() throws {
        let s = #""\u20ac123 \"blah\/\" (\\) \r\n""#
        let expected = "\u{20ac}123 \"blah/\" (\\) \n"
        
        let jis = try makeStream(s)
        let token = try jis.read()
        
        guard case let .string(key, str) = token else {
            XCTFail("Expected .string token")
            return
        }
        
        XCTAssertEqual(str, expected)
        XCTAssertNil(key)
        XCTAssertNil(try jis.read())
    }
    
    func testInvalidStringEscaping() throws {
        let s = #""\u20azzz""#
        let jis = try makeStream(s)
        XCTAssertThrowsError(try jis.read()) { err in
            print(err)
        }
    }
    
    func testEmptyString() throws {
        let s = ""
        let jis = try makeStream(s)
        XCTAssertEqual(try jis.read(), nil)
    }
    
    func testStringTooLong() throws {
        let s = "\"abcdefgh\u{20ac}ijklmnopqrstuvwxyz\""
        let jis = try makeStream(s)
        jis.maxStringLength = 10
        
        XCTAssertThrowsError(try jis.read()) { err in
            print(err)
        }
    }
    
    func testBuffering() throws {
        let s = """
        {
            "key1": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "key2": "0123456789012345678901234567890123456789012345678901"
        }
        """
        
        let jis = try makeStream(s, bufferCapacity: 20)
        
        let expected: [JsonToken] = [
            .startObject(nil),
            .string(.name("key1"), "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"),
            .string(.name("key2"), "0123456789012345678901234567890123456789012345678901"),
            .endObject(nil)
        ]
        
        for token in expected {
            XCTAssertEqual(try jis.read(), token)
        }
        
        XCTAssertEqual(try jis.read(), nil)
    }
        
    func consumeTokens(_ jis: JsonInputStream, printTokens: Bool = false) throws {
        while let token = try jis.read() {
            if printTokens {
                print(token)
            }
        }
    }
    
    func makeStream(_ s: String, bufferCapacity: Int? = nil) throws -> JsonInputStream {
        let stream = InputStream(data: s.data(using: .utf8)!)
        stream.open()
        return try JsonInputStream(stream: stream, bufferCapacity: bufferCapacity)
    }
}

