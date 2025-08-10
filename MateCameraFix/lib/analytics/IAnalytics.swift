//
//  IAnalytics.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//

protocol IAnalytics {
    static func setUserProperty(name: String, value: String)
    static func trackEvent(name: String, value: String?)
    static func sendScreenView(screen: String)
}
