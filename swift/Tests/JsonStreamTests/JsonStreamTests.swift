import XCTest
@testable import JsonStream

// XCTest Documenation
// https://developer.apple.com/documentation/xctest

// Defining Test Cases and Test Methods
// https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

final class JsonStreamTests: XCTestCase {
    let sample1 = #"{"type":"event","cost":123.456,"places":[{"city":"London","country","UK"},{"city":"San Francisco","country":"US"}]}"#
    
    func testExample() throws {
    }
}
