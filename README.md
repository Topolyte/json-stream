# JsonStream

A streaming JSON pull parser and generator for Swift.

Parse JSON files of unlimited size or stream JSON from the network without fear of running out of memory.
Selectively use only the parts of potentially large JSON files that are relevant to you.

JsonStream allows you to read and write JSON content token by token.
It does not provide any kind of mapping between Swift structs/classes and JSON objects.

## Controlling Memory Usage

JsonInputStream allows you to set the input buffer size (the default is 1MB) and the maximum acceptable length of
individual values in JSON properties and arrays (defaults to 10MB). If a longer value occurs,
a JsonInputError.valueTooLong exception is thrown. Note that this maximum length applies only to individual
values, not to the file as a whole. There is no file size limit.

The maximum memory usage of the parser is currently at least 2x the largest string value plus the size of the input buffer.
Depending on implementation details of the Swift standard library and Foundation classes it may grow some more.
To be on the safe side you should plan for 4x the largest individual string (or number) value plus the input buffer size.

Using the default settings, this works out to a maximum memory usage of 41MB for the data structures of the parser.
If you store any of the tokens you parse that would obviously add to your memory usage.

## Parsing Numbers

JsonInputStream has two number parsing options.
The default mode is JsonInputStream.NumberParsing.intDouble.
In this mode, numbers are returned as as Int64 if they are less than 19 digits long
and contain neither a decimal point nor an e. All other numbers are returned as Double
even if they are exactly representable as Int64.

So all of the following numbers would be returned as Double in spite of the fact that they are whole
numbers: -1.0, 0.0, 1e2, 1234567890123456789

The second number parsing mode is JsonInputStream.NumberParsing.allDecimal, which returns
all numbers as Decimal values.

The intDouble mode is a lot faster than allDecimal and should work for most applications.
However, floating point numbers come with well known issues that prevent exact round-tripping
of large numbers. So if floating point issues are a concern for your particular application
you can select allDecimal mode by passing numberParsing: .allDecimal to the constructor.

## Installation

### Swift Package Manager

Add the JsonStream package dependency to the dependencies section of your Package.swift
and a product dependency to each target that uses JsonStream: 

```
let package = Package(
    // name, platforms, products, etc.
    dependencies: [
        .package(url: "https://github.com/Topolyte/json-stream.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(name: "<your target>", dependencies: [
            .product(name: "JsonStream", package: "json-stream"),
        ])
    ]
)
``` 

## Usage

### JsonInputStream

Let's say we have this exciting JSON content in a file called countries.json

```
import JsonStream

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

```

Now we can create the JsonInputStream and iterate over the stream of tokens in depth-first order.
At the end of the stream, read() returns nil.

```
func example1() throws {
    
    let jis = try JsonInputStream(filePath: countriesPath)
        
    while let token = try jis.read() {
        print(token)
    }
}

```

Alteratively you can use a for-in loop instead of the throwing read() function:

```
func example1a() throws {
    
    let jis = try JsonInputStream(filePath: countriesPath)

    for tokenResult in jis {
        switch tokenResult {
        case let .success(token):
            print(token)
        case let .failure(error):
            throw error
        }
    }
}

```

After creating a JsonInputStream it can be iterated over exactly once.
After the loop has run its course, jis.read() will only ever return nil.
This is why we are re-creating the JsonInputStream before each example.

There are eight token types in the JsonToken enum:

```
public enum JsonToken: Equatable {
    case startObject(_ key: JsonKey?)
    case endObject(_ key: JsonKey?)
    case startArray(_ key: JsonKey?)
    case endArray(_ key: JsonKey?)
    case string(_ key: JsonKey?, _ value: String)
    case number(_ key: JsonKey?, _ value: JsonNumber)
    case bool(_ key: JsonKey?, _ value: Bool)
    case null(_ key: JsonKey?)
}
```

Each token has a key representing the property name or array index of the value.
The key for the root value is always nil. In addition to a key, tokens of type 
string, number and bool also have a value.

This is how we would print the value of all population properties in the example file:

```
func example2() throws {
    let jis = try JsonInputStream(filePath: countriesPath)
    
    while let token = try jis.read() {
        if case .number(.name("population"), let value) = token {
            print("population: \(value)")
        }
    }
}
```

Alternatively, this can be expressed as

```
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

```

The output is:

population: int(68138484)  
population: int(333287557)

Why does it print int(68138484) rather than just 68138484?
That's because number values are returned as JsonNumber, which is defined as

```
public enum JsonNumber: Equatable {
    case int(Int64)
    case double(Double)
    case decimal(Decimal)
}
```

Please consult the Parsing Numbers section for a detailed explanation.
In this case we know that the population property will always contain integers.
So we can rewrite the loop as follows:

```
func example3() throws {
    let jis = try JsonInputStream(filePath: countriesPath)
    
    while let token = try jis.read() {
        if case .number(.name("population"), let .int(value)) = token {
            print("population: \(value)")
        }
    }
}
```

Now this will print:

population: 68138484  
population: 333287557

But what if we are not sure whether population is really always an int?
Whoever generated the file might have put a decimal point in there somewhere
which would cause (some of) the numbers to come out as double.
We can code this somewhat more defensively like this:

```
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
```

As explained in the Parsing Numbers section, numbers will never be read as decimal
unless you create the JsonInputStream with numberParsing: .allDecimal.
This is much slower but avoids floating point issues. Besides, it allows you
to handle only the decimal case without accidentally missing any numbers:

```
func example5() throws {
    let jis = try JsonInputStream(filePath: countriesPath, numberParsing: .allDecimal)
        
    while let token = try jis.read() {
        if case .number(.name("population"), let .decimal(value)) = token {
            print("population: \(value)")
        }
    }
}
```

But what's the point of listing population numbers without the countries they belong to?
Let's print the country names as well:

```
func example6() throws {
    let jis = try JsonInputStream(filePath: countriesPath)
    
    while let token = try jis.read() {
        switch token {
        case .string(.name("name"), let value): //BUG!
            print("country: \(value)")
        case .number(.name("population"), let .int(value)):
            print("population: \(value)")
        default:
            continue
        }
    }
}
```

This prints:

country: United Kingdom  
population: 68138484  
country: London  
country: Liverpool  
country: United States  
population: 333287557  
country: Washington, D.C  
country: San Francisco  

Something is clearly wrong here. The problem is that
case .string(.name("name"), let value) matches both country and city names.

This is one of the reasons why streaming parsers like JsonInputStream
are not as convenient as JSON libraries that load everything into memory
and map JSON objects to Swift structs or classes.
The downside of that approach is of course unbounded memory usage.

So how can we extract only country names with JsonInputStream?
One way to do this is to check how deep down in the tree the property occurs:

```
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
```

The path property of JsonInputStream is an array of JsonKey, holding all
the array indexes and property names from the root down to the current token.
In this example, we're just checking the depth of the path, because we know
how deep down in the tree cities and countries occur respectively.

When the name property of the first country is read, jis.path is [.index(0), .name("name")].
When the name property of the first city in the first country is read, jis.path is
[.index(0), .name("cities"), .index(0), .name("name")].

This solution is fast, and it's fine because this is a list of countries and countries
will probably always be the top level elements within the array at the root of the JSON tree.

But if we wanted to match items that might get moved to a different level in the tree,
we would need a more flexible solution.

For instance, "cities" is currently a property of country objects. What if regions were
introduced and the path to city names changed to something like
[.index(0), .name("regions"), .index(0), .name("cities"), .index(0), .name("name")]?
Regions have names as well, so that would create yet another ambiguity.

This can be coded in a less brittle way using the pathMatch function of JsonInputStream,
which is defined as
```
func pathMatch(_ keys: JsonKey...) -> Bool
```

Here's how we can match city names regardless of whether cities occur as
direct children of countries or further down the tree:

```
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
```

jis.pathMatch(.name("cities")) checks whether a "cities" property occurs somehwere
along the path to the current token.

pathMatch() can be called with more than one parameter. For instance, to match only the
first city in each country you could say
```
jis.patchMatch(.name("cities"), .index(0)).
```

pathMatch() is pretty flexible. It doesn't simply match the exact sequence of keys.
There can be gaps in between and anything is allowed before or after the sequence.

So if there was a name property on a deeper level such as

```
{
    "cities": [
        {
            "name": "London",
            "rivers": [
                {
                    "name": "Thames"
                }
            ]
        }
    ]
}
```

then pathMatch(.name("cities")) would match both city and river names.
In order to match only river names, we have to be more specific:
``` 
pathMatch(.name("cities"), .name("rivers"))
```

But how would you match only city names? This is a little convoluted because
we have to match both just to do nothing in the rivers case:

```
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

``` 

This can be worked around by using the key path directly rather than relying on the matchPath function.
A better solution is already in the works. Stay tuned! 

What about the performance of pathMatch? It depends on the depth of the JSON tree.
In this example we have to check the path for each name property.
Country names require 2 comparisons per name property and city names require 4 comparisons.
It's pretty fast but pathMatch() is not a constant time operation.
If the tree was very deep and the document contained a large number of name properties
then performance could suffer. So here's a faster way to print countries with their population numbers:

```
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
```

Granted, this is less elegant. It's simple enough in this particular case but
toggling boolean flags to track parsing state can get messy pretty quickly.

The next example shows how tricky more complex state management problems can get.
Let's say we want to collect the names of countries and their capital cities:

```
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
```

This gets the job done but the code is pretty hairy.
Being a pull parser, JsonInputStream supports a more structured approach 
that can sometimes be cleaner (but also more verbose)

```
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

```

### JsonOutputStream

TBD...




