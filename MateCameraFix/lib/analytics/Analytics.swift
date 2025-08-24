//
//  Analytics.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//

import Foundation

class Analytics {
    private static var implementation: IAnalytics.Type = ConsoleAnalytics.self
    
    static func configure(_ analyticsImpl: IAnalytics.Type) {
        implementation = analyticsImpl
    }
    
    static func setUserProperty(name: String, value: String) {
        implementation.setUserProperty(name: name, value: value)
    }
    
    static func trackEvent(name: String, value: String? = nil) {
        implementation.trackEvent(name: name, value: value)
    }
    
    static func sendScreenView(screen: String) {
        implementation.sendScreenView(screen: screen)
    }
}
