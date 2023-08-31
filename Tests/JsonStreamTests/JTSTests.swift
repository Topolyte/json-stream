import XCTest
@testable import JsonStream

enum TestError: Error {
    case setupError(String)
}

final class JTSTests: XCTestCase {

    var jtsPath = ""
    
    enum TestType: Character {
        case mustSucceed = "y"
        case mustFail = "n"
        case implementationDefined = "i"
    }
    
    override func setUpWithError() throws {
        if let path = ProcessInfo.processInfo.environment["JTS_PATH"] {
            jtsPath = path
        } else {
            throw TestError.setupError("JTS_PATH environment variable not found")
        }
        
        guard FileManager.default.fileExists(atPath: jtsPath) else {
            throw TestError.setupError("JTS_PATH directory not found")
        }
    }

    func testJTS() throws {
        try runJTS(numberParsing: .intDouble)
    }
    
    func testJTSDecimal() throws {
        try runJTS(numberParsing: .allDecimal)
    }
    
    func runJTS(numberParsing: JsonInputStream.NumberParsing) throws {
        let fm = FileManager.default
        let dir = URL(filePath: jtsPath).appending(path: "test_parsing", directoryHint: .isDirectory)
        
        for fileName in try fm.contentsOfDirectory(atPath: dir.path()) {
            let testType = TestType(rawValue: fileName.first!)!
            let fileURL = dir.appending(path: fileName, directoryHint: .notDirectory)
            let jis = try JsonInputStream(filePath: fileURL.path(percentEncoded: false),
                                          numberParsing: numberParsing)
            
            switch testType {
            case .mustSucceed:
                XCTAssertNoThrow(try consumeTokens(jis, printTokens: false), fileName)
            case .mustFail:
                XCTAssertThrowsError(try consumeTokens(jis, printTokens: false), fileName)
            case .implementationDefined:
                break
            }
        }
    }
}
