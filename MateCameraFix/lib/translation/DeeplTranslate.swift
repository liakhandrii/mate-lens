//
//  DeeplTranslate.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//


//
//  DeeplTranslate.swift
//  Inst Translate
//
//  Created by Andrew Liakh on 10.02.22.
//  Copyright © 2022 Andrii Liakh. All rights reserved.
//

import Foundation
import NaturalLanguage
import SwiftyJSON

open class DeeplTranslate: TranslationProvider {
    
    let translationUrl = "https://api.deepl.com/v2/translate"
    let apiKey = "280875c8-b797-4e85-9ce2-50d8f9ef58ca"
    
    init() {
        
    }
    
    func getRawTranslation(_ from: String, to: String, text: String) async -> String? {
        return await getRawTranslationBatch(from, to: to, texts: [text])
    }
    
    func getRawTranslationBatch(_ from: String, to: String, texts: [String]) async -> String? {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0
        sessionConfig.timeoutIntervalForResource = 10.0
        
        let session = URLSession(configuration: sessionConfig)
        
        let deeplFrom = getDeeplLanguageCode(from, isSource: true)
        let deeplTo = getDeeplLanguageCode(to, isSource: false)
        
        guard let targetLang = deeplTo else {
            return nil
        }
        
        var request = URLRequest(url: URL(string: translationUrl)!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "text": texts,
            "target_lang": targetLang
        ]
        
        if let sourceLang = deeplFrom, !sourceLang.isEmpty {
            requestBody["source_lang"] = sourceLang
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, _) = try await session.data(for: request)
            return String(data: data, encoding: .utf8)
        } catch {
            print("DeepL API error: \(error)")
            return nil
        }
    }
    
    fileprivate func getTranslation(_ from:String, to:String, text:String) async -> (json: JSON, isNative: Bool)? {
        if let translationJsonString = await getRawTranslation(from, to: to, text: text),
            let json = try? JSON(data: translationJsonString.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions.mutableContainers) {
            return (json: json, isNative: false)
        }
        
        return nil
    }
    
    fileprivate func getText(_ json:JSON) -> String {
        var res = ""
        for (_, subJSON) in json["translations"] {
            if let tr = subJSON["text"].string {
                res += tr
            }
        }
        return res
    }
    
    private func getSourceLanguage(_ json: JSON) -> String? {
        if let sourceLang = json["translations"].arrayValue.first?["detected_source_language"].string {
            return sourceLang.lowercased()
        }
        
        return nil
    }
    
    open func getNativeJson(_ from: String, to: String, text: String, autocorrected: String? = nil) -> JSON? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: JSON?
        
        Task {
            result = await getNativeJsonAsync(from, to: to, text: text)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    func getNativeJsonBatch(_ from: String, to: String, text: [String]) -> [JSON]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [JSON]?
        
        Task {
            result = await getNativeJsonBatchAsync(from, to: to, texts: text)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
    
    private func getNativeJsonAsync(_ from: String, to: String, text: String) async -> JSON? {
        if let deeplTranslation = await getTranslationAsync(from, to: to, text: text) {
            return convertDeeplJsonToNative(deeplTranslation.json, from: from, targetLanguage: to, text: text)
        }
        return nil
    }
    
    private func getNativeJsonBatchAsync(_ from: String, to: String, texts: [String]) async -> [JSON]? {
        guard let translationJsonString = await getRawTranslationBatch(from, to: to, texts: texts),
              let json = try? JSON(data: translationJsonString.data(using: .utf8)!) else {
            return nil
        }
        
        var results: [JSON] = []
        let translations = json["translations"].arrayValue
        
        for (index, translation) in translations.enumerated() {
            if index < texts.count {
                let originalText = texts[index]
                if let nativeJson = convertDeeplJsonToNative(JSON(["translations": [translation]]), from: from, targetLanguage: to, text: originalText) {
                    results.append(nativeJson)
                }
            }
        }
        
        return results.isEmpty ? nil : results
    }
    
    private func getTranslationAsync(_ from: String, to: String, text: String) async -> (json: JSON, isNative: Bool)? {
        if let translationJsonString = await getRawTranslation(from, to: to, text: text),
           let json = try? JSON(data: translationJsonString.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions.mutableContainers) {
            return (json: json, isNative: false)
        }
        return nil
    }
    
    fileprivate func convertDeeplJsonToNative(_ deeplJson: JSON, from: String, targetLanguage: String, text: String) -> JSON? {
        let jsonArray = NSMutableArray()
        let translatedText = getText(deeplJson)
        
        if translatedText.isEmpty {
            return nil
        }
        
        //is multi
        jsonArray.add(false)
        
        //orig
        jsonArray.add(text)
        
        //transcript
        jsonArray.add("")
        
        //tranaslated
        if translatedText.isEmpty {
            return nil
        }
        jsonArray.add(translatedText)
        
        //translit
        jsonArray.add("")
        
        //source lang
        if let sourceLang = getSourceLanguage(deeplJson)?.lowercased() {
            if sourceLang == "iw" {
                jsonArray.add("he")
            } else {
                jsonArray.add(sourceLang)
            }
        } else {
            jsonArray.add("")
        }
        
        //target lang
        jsonArray.add(targetLanguage.lowercased())
        
        //print(googleJson)
        
        jsonArray.add(NSMutableArray())
        
        // Original word gender
        jsonArray.add("")
        
        // Translated word gender
        jsonArray.add("")
        
        // Original word IPA
        jsonArray.add("")
        
        // Original word translit
        jsonArray.add("")
        
        //print(synonymsArray)
        
        return JSON(jsonArray)
        
    }
    
    func getDeeplLanguageCode(_ code: String, isSource: Bool) -> String? {
        if isSource {
            // Source languages use simplified codes
            return sourceLanguageCodes[code]
        } else {
            // Target languages use the full mapping
            return languageCodes[code]
        }
    }
    
    private let languageCodes = languageCodesMap
    
    private let sourceLanguageCodes = [
        // "auto": nil,
        "ar": "AR",
        "bg": "BG", 
        "cs": "CS",
        "da": "DA",
        "de": "DE",
        "el": "EL",
        "en": "EN",
        "en-us": "EN",
        "en-gb": "EN",
        "es": "ES",
        "et": "ET",
        "fi": "FI",
        "fr": "FR",
        "he": "HE",
        "hu": "HU",
        "id": "ID",
        "it": "IT",
        "ja": "JA",
        "ko": "KO",
        "lt": "LT",
        "lv": "LV",
        "nb": "NB",
        "nl": "NL",
        "pl": "PL",
        "pt": "PT",
        "pt-br": "PT",
        "ro": "RO",
        "ru": "RU",
        "sk": "SK",
        "sl": "SL",
        "sv": "SV",
        "th": "TH",
        "tr": "TR",
        "uk": "UK",
        "vi": "VI",
        "zh": "ZH",
        "zh-CN": "ZH"
    ]
    
    private static let languageCodesMap = [
        "auto": "",
        "bg": "BG",
        "cs": "CS",
        "da": "DA",
        "de": "DE",
        "el": "EL",
        "en": "EN-GB",
        "en-us": "EN-US",
        "es": "ES",
        "et": "ET",
        "fi": "FI",
        "fr": "FR",
        "hu": "HU",
        "id": "ID",
        "it": "IT",
        "ja": "JA",
        "lt": "LT",
        "lv": "LV",
        "nl": "NL",
        "pl": "PL",
        "pt-br": "PT-BR",
        "pt": "PT-PT",
        "ro": "RO",
        "ru": "RU",
        "sk": "SK",
        "sl": "SL",
        "sv": "SV",
        "tr": "TR",
        "uk": "UK",
        "zh-CN": "ZH"
    ]
    
    public static let supportedLanguages = Array(languageCodesMap.keys)
    
}

