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
To be on the safe side, you should plan for 4x the largest individual string value plus the input buffer size.

Using the default settings, this works out to a maximum memory usage of 41MB for the data structures of the parser.
If you store any of the tokens you parse that would obviously add to your memory usage.

## Parsing Large Numbers

JSON doesn't specify how to deal with large number values. JsonInputStream reads numbers
digit by digit into a Double value. If the value exceeds the precision of Double (15 decimal digits),
information is lost and roundtripping is no longer exact.

Numbers greater than Double.greatestFiniteMagnitude or less than Double.leastNonzeroMagnitude
are rounded to positive and negative infinity respectively. 

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
``` 

## Usage



