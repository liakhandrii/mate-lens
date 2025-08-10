//
//  ConsoleAnalytics.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//

import Foundation

class ConsoleAnalytics: IAnalytics {
    
    static func setUserProperty(name: String, value: String) {
        print("📊 [Analytics] User Property: \(name) = \(value)")
    }
    
    static func trackEvent(name: String, value: String?) {
        if let value = value {
            print("📊 [Analytics] Event: \(name) with value: \(value)")
        } else {
            print("📊 [Analytics] Event: \(name)")
        }
    }
    
    static func sendScreenView(screen: String) {
        print("📊 [Analytics] Screen View: \(screen)")
    }
}
