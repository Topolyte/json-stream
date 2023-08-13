/*
Copyright (c) 2023 Topolyte Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import Foundation

public enum JsonError: Error {
    case invalidContext(String)
    case ioError(String)
    case unexpectedContent(String)
    case unexpectedEndOfStream
    case stringTooLong
    case invalidUTF8
    case invalidEscapeSequence(String)
    case invalidNumber(String)
}

public struct Ascii {
    static let quote = Character("\"").asciiValue!
    static let backslash = Character("\\").asciiValue!
    static let slash = Character("/").asciiValue!
    static let space = Character(" ").asciiValue!
    static let cr = Character("\r").asciiValue!
    static let lf = Character("\n").asciiValue!
    static let tab = Character("\t").asciiValue!
    static let formFeed = UInt8(12)
    static let backspace = UInt8(8)
    static let leftBrace = Character("{").asciiValue!
    static let rightBrace = Character("}").asciiValue!
    static let leftSquare = Character("[").asciiValue!
    static let rightSquare = Character("]").asciiValue!
    static let comma = Character(",").asciiValue!
    static let colon = Character(":").asciiValue!
    static let zero = Character("0").asciiValue!
    static let nine = Character("9").asciiValue!
    static let minus = Character("-").asciiValue!
    static let plus = Character("+").asciiValue!
    static let dot = Character(".").asciiValue!
    static let a = Character("a").asciiValue!
    static let A = Character("A").asciiValue!
    static let e = Character("e").asciiValue!
    static let E = Character("E").asciiValue!
    static let f = Character("f").asciiValue!
    static let F = Character("F").asciiValue!
    static let n = Character("n").asciiValue!
    static let r = Character("r").asciiValue!
    static let t = Character("t").asciiValue!
    static let b = Character("b").asciiValue!
    static let u = Character("u").asciiValue!
}



