import XCTest
@testable import JsonStream

func consumeTokens(_ jis: JsonInputStream, printTokens: Bool = false) throws {
    while let token = try jis.read() {
        if printTokens {
            print(token)
        }
    }
}
