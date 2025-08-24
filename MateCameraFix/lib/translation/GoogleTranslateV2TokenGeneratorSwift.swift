//
//  GoogleTranslateV2TokenGeneratorSwift.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//

import Foundation

class GoogleTranslateV2TokenGeneratorSwift {
    
    private func yf(_ a: UInt32, _ b: String) -> UInt32 {
        var result = a
        let chars = Array(b)
        
        var c = 0
        while c < chars.count - 2 {
            let d: UInt32
            let char = chars[c + 2]
            
            if char >= "a" {
                d = UInt32(char.asciiValue! - 87)
            } else {
                d = UInt32(String(char))!
            }
            
            let shifted: UInt32
            if chars[c + 1] == "+" {
                shifted = result >> d
            } else {
                shifted = result << d
            }
            
            if chars[c] == "+" {
                result = (result &+ shifted) & 4294967295
            } else {
                result = result ^ shifted
            }
            
            c += 3
        }
        
        return result
    }
    
    func tk(text: String) -> String {
        var d: [UInt32] = []
        var e = 0
        
        for char in text {
            let g = UInt32(char.unicodeScalars.first!.value)
            
            if g < 128 {
                d.append(g)
                e += 1
            } else if g < 2048 {
                d.append((g >> 6) | 192)
                d.append((g & 63) | 128)
                e += 2
            } else {
                d.append((g >> 12) | 224)
                d.append(((g >> 6) & 63) | 128)
                d.append((g & 63) | 128)
                e += 3
            }
        }
        
        let b: UInt32 = 0
        var tk: UInt32 = 0
        
        for value in d {
            tk = tk &+ value
            tk = yf(tk, "+-a^+6")
        }
        
        tk = yf(tk, "+-3^+b+-f")
        
        if tk > 2147483647 {
            tk = (tk & 2147483647) + 2147483648
        }
        
        tk = tk % 1000000
        
        return "\(tk).\(tk ^ b)"
    }
}
