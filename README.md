# JsonStream

A streaming JSON parser and generator for Swift.

Parse JSON files of unlimited size or stream JSON from the network without fear of running out of memory.
Selectively use only the parts of potentially large JSON files that are relevant to you.

JsonStream does not provide any kind of mapping between Swift structs/classes and JSON objects.

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

## Installation



## Usage



