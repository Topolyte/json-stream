# JsonStream

A streaming JSON pull parser and generator for Swift.

Parse JSON files of unlimited size or stream JSON from the network without fear of running out of memory.
Selectively use only the parts of potentially large JSON files that are relevant to you.

JsonStream allows you to read and write JSON content token by token.
It does not provide any kind of mapping between Swift structs/classes and JSON objects.

## Controlling Memory Usage

JsonInputStream allows you to set the input buffer size (the default is 1MB) and the maximum acceptable length of
individual string values in JSON properties and arrays (defaults to 10MB). If a longer string value occurs,
a JsonInputError.stringTooLong exception is thrown. Note that this maximum length applies only to individual
string values, not to the file as a whole. There is no file size limit.

The maximum memory usage of the parser is currently at least 2x the largest string value plus the size of the input buffer.
Depending on implementation details of the Swift standard library and Foundation classes it may grow even more.
To be on the safe side you should plan for 4x the largest individual string value plus the input buffer size.

Using the default settings, this works out to a maximum memory usage of 41MB for the data structures of the parser.
If you store any of the tokens you parse that would obviously add to your memory usage.

## Parsing Numbers

JsonInputStream returns numbers as Int64 if they contain less than 19 decimal digits
and neither a decimal point nor an e. All other numbers are returned as Double 
even if they are exactly representable as Int64.

So all of the following numbers are returned as Int64: -1, 0, 100, 123456789012345678
But these numbers are returned as Double in spite of the fact that they are whole
numbers: -1.0, 0.0, 1e2, 1234567890123456789

Note that all the usual warnings about floating point numbers apply. Double has
a precision of ~15 digits. If you read Double numbers outside of this range, you will lose
information and round-tripping will no longer be exact. 1e16 + 1 == 1e16.

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
            .product(name: "JsonStream", package: "https://github.com/Topolyte/json-stream.git"),
        ])
    ]
)
``` 

## Usage



