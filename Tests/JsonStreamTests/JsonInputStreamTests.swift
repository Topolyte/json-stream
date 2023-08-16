import XCTest
@testable import JsonStream

// XCTest Documenation
// https://developer.apple.com/documentation/xctest

// Defining Test Cases and Test Methods
// https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

final class JsonInputStreamTests: XCTestCase {
    
    func testBasics() throws {
        let s = """
        {
            "type": "Captain",
            "name": "Jean-Luc Picard",
            "speed": {"quantity": 500000.5, "unit": "m/s"},
            "isFrench": true,
            "height": null,
            "postings": ["USS-Enterprise-D", 2363, "USS-Enterprise-E", 2372],
            "boldness": 101
        }
        """
        let jis = makeStream(s)
        
        let expected: [JsonToken] = [
            .startObject(nil),
            .string(.name("type"), "Captain"),
            .string(.name("name"), "Jean-Luc Picard"),
            .startObject(.name("speed")),
            .number(.name("quantity"), 500000.5),
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
    
    func testNestedEmptyArrays() throws {
        let s = """
        [[]]
        """
        
        let jis = makeStream(s)
        
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
        
        var jis = makeStream(s)
        
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
        jis = makeStream(s)
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
        var jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Leading comma in array") { err in
            print(err)
        }
        
        s = """
        [1, 2,]
        """
        jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Trailing comma in array") { err in
            print(err)
        }

        s = """
        {, "a": 1, "b": 2}
        """
        jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Leading comma in object") { err in
            print(err)
        }

        s = """
        {"a": 1, "b": 2 ,}
        """
        jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis), "Trailing comma in object") { err in
            print(err)
        }
    }
    
    func testUnbalancedBrackets() throws {
        var s = """
        [[]
        """
        var jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis, printTokens: true), "Orphan left bracket in array") { err in
            print(err)
        }
        
        s = """
        {"a":1,
        """
        jis = makeStream(s)
        XCTAssertThrowsError(try consumeTokens(jis, printTokens: true), "Orphan left bracket in array") { err in
            print(err)
        }
    }
    
    func testStringEscaping() throws {
        let s = #""\u20ac123 \"blah\/\" (\\) \r\n""#
        let expected = "\u{20ac}123 \"blah/\" (\\) \n"
        
        let jis = makeStream(s)
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
        var s = #""\u20azzz""#
        var jis = makeStream(s)
        XCTAssertThrowsError(try jis.read()) { err in
            print(err)
        }
    }
    
    func consumeTokens(_ jis: JsonInputStream, printTokens: Bool = false) throws {
        while let token = try jis.read() {
            if printTokens {
                print(token)
            }
        }
    }
    
    func makeStream(_ s: String) -> JsonInputStream {
        let stream = InputStream(data: s.data(using: .utf8)!)
        stream.open()
        return JsonInputStream(stream: stream)
    }
}

