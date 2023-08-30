import XCTest
@testable import JsonStream

final class JsonInputStreamTests: XCTestCase {
    
//    func testAdHoc() throws {
//        let s = #"{"a":"#
//
//        let jis = try makeStream(s)
//
//        try consumeTokens(jis, printTokens: true)
//    }
    
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
            .number(.name("quantity"), JsonNumber.double(500500.0)),
            .string(.name("unit"), "m/s"),
            .endObject(.name("speed")),
            .bool(.name("isFrench"), true),
            .null(.name("height")),
            .startArray(.name("postings")),
            .string(.index(0), "USS-Enterprise-D"),
            .number(.index(1), JsonNumber.int(2363)),
            .string(.index(2), "USS-Enterprise-E"),
            .number(.index(3), JsonNumber.int(2372)),
            .endArray(.name("postings")),
            .number(.name("boldness"), JsonNumber.int(101)),
            .endObject(nil)
        ]
        
        for token in expected {
            XCTAssertEqual(try jis.read(), token)
        }

        XCTAssertEqual(try jis.read(), nil)
    }
    
    func testNumber() throws {
        let valid: [(String, JsonNumber)] = [
            ("1", .int(1)),
            ("0", .int(0)),
            ("0.0", .double(0.0)),
            ("1.23", .double(1.23)),
            ("-11.234", .double(-11.234)),
            ("0.2233", .double(0.2233)),
            ("12.40", .double(12.4)),
            ("-0.0", .double(0.0)),
            ("1.0012300", .double(1.00123)),
            ("1.23E+14", .double(1.23e14)),
            ("1.23e-4", .double(1.23e-4)),
            ("11e4", .double(110000.0)),
            ("-12345678901234567890123456789.123", .double(-12345678901234567890123456789.123)),
            ("999999999999999999", .int(999999999999999999)),
            ("1234567890123456789", .double(1234567890123456789.0))
        ]
        
        let invalid = [
            ".1", "--1.2", "12,345.6", "12.34.56", "12 345", "12_345",
            "1.2a4", "0xABC", "1.2 e4", "12-e4", "12.", "1e4.1", "01"
        ]
        
        for (s, n) in valid {
            print(s)
            let jis = try makeStream(s)
            XCTAssertEqual(try jis.read(), .number(nil, n))
        }
        
        for s in invalid {
            print(s)
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
            .number(.name("c"), JsonNumber.int(111)),
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
        let jis = try makeStream(s, maxStringLength: 10)
        
        XCTAssertThrowsError(try jis.read()) { err in
            print(err)
        }
    }
    
    func testNumberArrays() throws {
        let s = "[1.23e4,0.001  ,1]"
        
        let expected: [JsonToken] = [
            .startArray(nil),
            .number(.index(0), .double(1.23e4)),
            .number(.index(1), .double(0.001)),
            .number(.index(2), .int(1)),
            .endArray(nil)
        ]
        
        let jis = try makeStream(s)
        
        for e in expected {
            XCTAssertEqual(try jis.read(), e)
        }
        
        XCTAssertNil(try jis.read())
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
    
    func testKeyPathString() throws {
        let s = """
        {
            "starship": {
                "type": "research vessel",
                "features": [
                    {
                        "sensors": [
                            "subspace sensor",
                            "camera",
                            "light sensor"
                        ]
                    },
                    "deflector shield"
                ]
            }
        }
        """
        
        let jis = try makeStream(s)
        var cameraPath = ""
        var typePath = ""
        
        while let token = try jis.read() {
            switch token {
            case .string(.index(1), "camera"):
                cameraPath = jis.keyPathString
            case .string(.name("type"), "research vessel"):
                typePath = jis.keyPathString
            default:
                break
            }
        }
        
        XCTAssertEqual(cameraPath, "starship.features[0].sensors[1]")
        XCTAssertEqual(typePath, "starship.type")
    }
            
    func makeStream(_ s: String, bufferCapacity: Int? = nil, maxStringLength: Int? = nil) throws -> JsonInputStream {
        let stream = InputStream(data: s.data(using: .utf8)!)
        stream.open()
        
        return try JsonInputStream(
            stream: stream, bufferCapacity: bufferCapacity, maxStringLength: maxStringLength)
    }
}

