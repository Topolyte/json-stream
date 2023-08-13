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

let asciiQuote = Character("\"").asciiValue!
let asciiBackslash = Character("\\").asciiValue!
let asciiSlash = Character("/").asciiValue!
let asciiSpace = Character(" ").asciiValue!
let asciiCr = Character("\r").asciiValue!
let asciiLf = Character("\n").asciiValue!
let asciiTab = Character("\t").asciiValue!
let asciiFormFeed = UInt8(12)
let asciiBackspace = UInt8(8)
let asciiLeftBrace = Character("{").asciiValue!
let asciiRightBrace = Character("}").asciiValue!
let asciiLeftSquare = Character("[").asciiValue!
let asciiRightSquare = Character("]").asciiValue!
let asciiComma = Character(",").asciiValue!
let asciiColon = Character(":").asciiValue!
let asciiZero = Character("0").asciiValue!
let asciiNine = Character("9").asciiValue!
let asciiMinus = Character("-").asciiValue!
let asciiPlus = Character("+").asciiValue!
let asciiDot = Character(".").asciiValue!
let asciia = Character("a").asciiValue!
let asciiA = Character("A").asciiValue!
let asciie = Character("e").asciiValue!
let asciiE = Character("E").asciiValue!
let asciif = Character("f").asciiValue!
let asciiF = Character("F").asciiValue!
let asciin = Character("n").asciiValue!
let asciir = Character("r").asciiValue!
let asciit = Character("t").asciiValue!
let asciib = Character("b").asciiValue!
let asciiu = Character("u").asciiValue!



