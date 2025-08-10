//
//  String + localizeed.swift
//  Inst Translate
//
//  Created by Andrii Liakh on 23.08.16.
//  Copyright © 2016 Andrii Liakh. All rights reserved.
//

import Foundation

extension String {
    
    /**
     The app version parameter is ignored
     */
    
    func localizedUppercase(_ appVersion: String? = nil) -> String {
        return localized(appVersion).uppercased(with: NSLocale.current)
    }
    
    func localized(_ appVersion: String? = nil) -> String {
        let localized = NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: self, comment: "")
        
//        #if DEBUG
//            if NSLocalizedString("lang", comment: "") != "en" {
//                if self == localized {
//                    NSLog("String \"\(self)\" is not localized!")
//                }
//            }
//
//            return "UL: \(localized)"
//        #endif
        
        return localized
    }
    
    func withInsets() -> String {
        return "\(self)\u{3000}"
    }
    
    var isValidEmail: Bool {
        if self.isEmpty {
            return false
        }
        
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailTest.evaluate(with: self)
    }
    
    static func randomString(length: Int) -> String {
      let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
      return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    static func days(count: Int) -> String {
        return String.localizedStringWithFormat(NSLocalizedString("num_days", comment: ""), count)
    }
    
}

