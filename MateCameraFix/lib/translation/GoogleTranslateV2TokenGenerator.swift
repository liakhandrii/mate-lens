//
//  GoogleTranslateV2TokenGenerator.swift
//  Instant Translate
//
//  Created by Andrew Liakh on 8/7/17.
//  Copyright © 2017 Gikken UG. All rights reserved.
//

import Foundation
import JavaScriptCore

// Yeah, using JavaScript for two functions may not be the best idea, but I wasted a lot of time on getting the Swift version to work and it doesn't work :(

class GoogleTranslateV2TokenGenerator {
    
    // Swift 3 doesn't support multi line strings
    // TODO: Make this string multi line in Swift 4 version
    private let jsSource = "var yf = function (a, b) { for (var c = 0; c < b.length - 2; c += 3) { var d = b[c + 2]; d = \"a\" <= d ? d.charCodeAt(0) - 87 : Number(d); d = \"+\" == b[c + 1] ? a >>> d : a << d; a = \"+\" == b[c] ? a + d & 4294967295 : a ^ d; } return a; }; var tk = function (a) { var d = []; for (var f = 0, e = 0; f < a.length; ++f) { var g = a.charCodeAt(f); if (128 > g) { d[e++] = g; } else { if (2048 > g) { d[e++] = g >> 6 | 192; } else { d[e++] = g >> 12 | 224; d[e++] = g >> 6 & 63 | 128; } d[e++] = g & 63 | 128; } } var b = 0; var tk = 0; for (e = 0; e < d.length; e++) { tk += d[e]; tk = yf(tk, \"+-a^+6\"); } tk = yf(tk, \"+-3^+b+-f\"); if (0 > tk) { tk = (tk & 2147483647) + 2147483648; } tk %= 1E6; return tk.toString() + \".\" + (tk ^ b).toString(); };"
    
    private var context = JSContext()!
    private var tkFunction: JSValue!
    
    init() {
        context.evaluateScript(jsSource)
        tkFunction = context.objectForKeyedSubscript("tk")
    }
    
    func tk(text: String) -> String {
        let result = tkFunction.call(withArguments: [text])
        return result!.toString()
    }
    
}
