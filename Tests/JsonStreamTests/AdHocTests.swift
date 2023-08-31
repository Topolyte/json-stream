import XCTest
@testable import JsonStream

final class AdHocTests: XCTestCase {

    func testAdHoc() throws {
        
        // Let's say we have this exciting JSON file in file called countries.json
        
        let countries = """
        [
            {
                "name": "United Kingdom",
                "population": 68138484,
                "density": 270.7,
                "cities": [
                    {"name": "London", "isCapital": true},
                    {"name": "Liverpool", "isCapital": false}
                ],
                "monarch": "King Charles III"
            },
            {
                "name": "United States",
                "population": 333287557,
                "density": 33.6,
                "cities": [
                    {"name": "Washington, D.C", "isCapital": true},
                    {"name": "San Francisco", "isCapital": false}
                ],
                "monarch": null
            }
        ]
        """.data(using: .utf8)!

        let directoryURL = FileManager.default.temporaryDirectory
        let countriesURL = directoryURL.appending(component: "countries.json")
        try countries.write(to: countriesURL)
        
        // Now we can open it with JsonInputStream ...
        
        let jis = try JsonInputStream(filePath: countriesURL.path(percentEncoded: false))
        
        //... and iterate over the tokens printing only the names of cities
        
        while let token = try jis.read() {
            switch token {
            case .string(.name("name"), let value) where jis.pathMatch(.name("cities")):
                print(value)
            default:
                continue
            }
        }

    }

}
