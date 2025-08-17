//
//  LanguagesManager.swift
//  Inst Translate
//
//  Created by Andrii Liakh on 08.08.15.
//  Copyright (c) 2015 Gikken UG. All rights reserved.
//

import Foundation
import SwiftyJSON

class TranslationManager {
    
    static var shared: TranslationManager {
        return instance
    }
    
    static fileprivate let instance = TranslationManager()
    
    fileprivate let providers: [TranslationProvider]
    
    fileprivate init() {
        providers = [
            DeeplTranslate(),
            GoogleTranslateV2(),
            GoogleTranslate()
        ]
    }
    
    func translateFromTextBatch(_ from: String, to: String, texts: [String], autocorrect: Bool) -> [TranslatedText?]? {
        for provider in providers {
            if let jsonResults = provider.getNativeJsonBatch(from, to: to, text: texts) {
                let translatedTexts = jsonResults.map { json in
                    let isEmpty = json[CorrectNativeJsonIndexes.translated].stringValue.isEmpty
                    return isEmpty ? nil : TranslatedText(json: json)
                }
                
                // If we got some results, return them (even if some are nil)
                if !translatedTexts.allSatisfy({ $0 == nil }) {
                    return translatedTexts
                }
            }
        }
        
        // No provider supports batch - let TranslationService handle concurrent individual calls
        return nil
    }
    
    func translateFromText(_ from: String, to: String, text: String, autocorrect: Bool) -> TranslatedText? {
        guard let json = translateFrom(from, to: to, text: text, autocorrect: autocorrect) else {
            return nil
        }
        
        return TranslatedText(json: json)
    }
    
    func translateFrom(_ from: String, to: String, text: String, autocorrect: Bool) -> JSON? {
        for provider in providers {
            if let translation = provider.getNativeJson(from, to: to, text: text, autocorrected: autocorrect ? nil : "") {
                let isEmpty = translation[CorrectNativeJsonIndexes.translated].stringValue.isEmpty
                if !isEmpty {
                    return translation
                }
            }
        }
        
        return nil
    }
    
    // macOS only
    func convertNativeJsonToMacArray(jsonString: String) -> NSArray {
        return convertNativeJsonToMacArray(json: try? JSON(data: jsonString.data(using: .utf8, allowLossyConversion: false)!))
    }
    
    func convertNativeJsonToMacArray(json optionalJson: JSON?) -> NSArray {
        if optionalJson == nil {
            return ["no_int"]
        } else if optionalJson![CorrectNativeJsonIndexes.translated].stringValue.isEmpty {
            return ["no_res"]
        }
        
        let json = optionalJson!
        
        let res = NSMutableArray()
        
        // extracting the translation and putting it into array
        let translation = json[CorrectNativeJsonIndexes.translated].stringValue
        res.add(translation)
        
        // extracting the transliteration and putting it into array if present
        if let translitString = json[CorrectNativeJsonIndexes.translit].string, !translitString.isEmpty {
            let translitGroup = [
                "type": "translit",
                "header": NSLocalizedString("Transliteration", comment: "").uppercased(),
                "transliteration": translitString
            ]
            
            res.add(translitGroup)
        }
        
        // extracting the IPA and putting it into array if present
        if let ipaText = json[CorrectNativeJsonIndexes.translatedTranscription].string, !ipaText.isEmpty {
            let ipa = [
                "type": "translit",
                "header": "Phonetic transliteration".localizedUppercase("v4"),
                "transliteration": ipaText
            ]
            res.add(ipa)
        }
        
        // nothing to do anymore if the translation has no synonyms
        if !json[CorrectNativeJsonIndexes.isMulti].boolValue {
            // print(res)
            return res
        }
        
        for (index, synonymsJson) in json[CorrectNativeJsonIndexes.synonymsArray] {
            
            if synonymsJson.count == 0 {
                continue
            }
            
            // part name depends on it's index in the native translation JSON
            let partName = CorrectNativeJsonIndexes.indexesToPartsOfSpeech[Int(index)!] ?? ""
            let partOfSpeech = [
                "group": partName.localizedUppercase()
            ]
            
            // we decided not to show group if it has no category
            if partName != "" {
                res.add(partOfSpeech)
            }
            
            for (_, oneSynonynymJson) in synonymsJson {
                let wordString = oneSynonynymJson[CorrectNativeJsonIndexes.synWord].stringValue
                
                let gender = oneSynonynymJson[CorrectNativeJsonIndexes.synGender].string
                
                var wordDict = [
                    "word": wordString,
                    "gender": gender
                ]
                
                var i = 1
                
                for (_, reverseJson) in oneSynonynymJson[CorrectNativeJsonIndexes.synReverse] {
                    if let reverseString = reverseJson.string, !reverseString.isEmpty {
                        wordDict["reverse\(i)"] = reverseString
                        i += 1
                    }
                }
                
                res.add(wordDict)
            }
            
        }
        // print(res)
        return res

    }
}
