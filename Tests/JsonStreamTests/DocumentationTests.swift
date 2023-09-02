import XCTest
@testable import JsonStream

final class DocumentationTests: XCTestCase {

    func testInputStreamExamples() throws {
        
        // Let's say we have this exciting JSON content in a file called countries.json
        
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
        let countriesPath = countriesURL.path(percentEncoded: false)
        try countries.write(to: countriesURL)
        
        func example1() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
                        
            while let token = try jis.read() {
                print(token)
            }
        }
                
        func example2() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                if case .number(.name("population"), let value) = token {
                    print("population: \(value)")
                }
            }
        }

        func example2b() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .number(.name("population"), let value):
                    print("population: \(value)")
                default:
                    continue
                }
            }
        }
        
        func example3() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                if case .number(.name("population"), let .int(value)) = token {
                    print("population: \(value)")
                }
            }
        }
        
        func example4() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .number(.name("population"), let .int(value)):
                    print("population: \(value)")
                case .number(.name("population"), let .double(value)):
                    print("population: \(value)")
                default:
                    continue
                }
            }
        }
        
        func example5() throws {
            let jis = try JsonInputStream(filePath: countriesPath, numberParsing: .allDecimal)
            
            while let token = try jis.read() {
                if case .number(.name("population"), let .decimal(value)) = token {
                    print("population: \(value)")
                }
            }
        }
        
        func example6() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .string(.name("name"), let value):
                    print("country: \(value)")
                case .number(.name("population"), let .int(value)):
                    print("population: \(value)")
                default:
                    continue
                }
            }
        }
                
        func example7() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .string(.name("name"), let value) where jis.path.count == 2:
                    print("country: \(value)")
                case .number(.name("population"), let .int(value)):
                    print("population: \(value)")
                default:
                    continue
                }
            }
        }
        
        func example8() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .string(.name("name"), let value) where jis.pathMatch(.name("cities")):
                    print("city: \(value)")
                default:
                    continue
                }
            }
        }
        
        func example8b() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            
            while let token = try jis.read() {
                switch token {
                case .string(.name("name"), _) where jis.pathMatch(.name("cities"), .name("rivers")):
                    continue
                case .string(.name("name"), let value) where jis.pathMatch(.name("cities")):
                    print("city: \(value)")
                default:
                    continue
                }
            }
        }

        
        func example9() throws {
            let jis = try JsonInputStream(filePath: countriesPath)
            var isReadingCities = false
            
            while let token = try jis.read() {
                switch token {
                case .startArray(.name("cities")):
                    isReadingCities = true
                case .endArray(.name("cities")):
                    isReadingCities = false
                case .string(.name("name"), let value) where !isReadingCities:
                    print("country: \(value)")
                case .number(.name("population"), let .int(value)):
                    print("population: \(value)")
                default:
                    continue
                }
            }
        }
        
        func example10() throws {
            struct Capital {
                let country: String
                let capital: String
            }
                        
            var capitals = [Capital]()
            var country: String?
            var capital: String?
            var city: String?
            var isCapital: Bool?
            
            let jis = try JsonInputStream(filePath: countriesPath)

            while let token = try jis.read() {
                switch token {
                case .string(.name("name"), let cityName) where jis.pathMatch(.name("cities")):
                    city = cityName
                case .bool(.name("isCapital"), let value):
                    isCapital = value
                case .string(.name("name"), let countryName):
                    country = countryName
                case .endObject where jis.path.count == 3: // end of city
                    if let city = city, let isCapital = isCapital, isCapital {
                        capital = city
                    }
                    city = nil
                    isCapital = nil
                case .endObject where jis.path.count == 1: // end of country
                    if let country = country, let capital = capital {
                        capitals.append(Capital(country: country, capital: capital))
                    }
                    country = nil
                    capital = nil
                default:
                    continue
                }
            }
            
            for c in capitals {
                print("\(c.country): \(c.capital)")
            }
        }
        
        func example11() throws {

            struct Capital {
                let country: String
                let capital: String
            }
            
            func readCountries(_ jis: JsonInputStream) throws -> [Capital] {
                var capitals = [Capital]()
                
                while let token = try jis.read() {
                    if case .startObject = token {
                        if let capital = try readCountry(jis) {
                            capitals.append(capital)
                        }
                    }
                }
                
                return capitals
            }
            
            func readCountry(_ jis: JsonInputStream) throws -> Capital? {
                var country: String?
                var capital: String?
                
                while let token = try jis.read() {
                    switch token {
                    case .startArray(.name("cities")):
                        capital = try readCities(jis)
                    case .string(.name("name"), let value):
                        country = value
                    case .endObject:
                        if let country = country, let capital = capital {
                            return Capital(country: country, capital: capital)
                        }
                        return nil
                    default:
                        continue
                    }
                }
                
                return nil
            }

            
            func readCities(_ jis: JsonInputStream) throws -> String? {
                var capital: String?
                
                while let token = try jis.read() {
                    switch token {
                    case .startObject:
                        let (city, isCapital) = try readCity(jis)
                        if let city = city, let isCapital = isCapital, isCapital {
                            capital = city
                        }
                    case .endArray:
                        return capital
                    default:
                        continue
                    }
                }
                
                return nil
            }
            
            func readCity(_ jis: JsonInputStream) throws -> (String?, Bool?) {
                var city: String?
                var isCapital: Bool?
                
                while let token = try jis.read() {
                    switch token {
                    case .string(.name("name"), let value):
                        city = value
                    case .bool(.name("isCapital"), let value):
                        isCapital = value
                    case .endObject:
                        return (city, isCapital)
                    default:
                        continue
                    }
                }
                
                return (city, isCapital)
            }
                        
            let jis = try JsonInputStream(filePath: countriesPath)
            let capitals = try readCountries(jis)
            
            for c in capitals {
                print("\(c.country): \(c.capital)")
            }
        }
        
    }
}
