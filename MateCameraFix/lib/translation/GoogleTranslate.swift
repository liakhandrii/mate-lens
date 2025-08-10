//
//  GoogleTranslate.swift
//  Instant Translate
//
//  Created by Andrii Liakh on 19.03.15.
//  Copyright (c) 2015 Gikken UG. All rights reserved.
//

import Foundation
import SwiftyJSON
import NaturalLanguage

open class GoogleTranslate: TranslationProvider {
    
    let supportedLanguages = ["am", "co", "fy", "gd", "haw", "ku", "ky", "lb", "ps", "sd", "sm", "sn", "xh", "no", "uz", "fa", "mg", "de", "ig", "ko", "lt", "pl", "tl", "ro", "bn", "auto", "be", "zh-CN", "id", "la", "eu", "mn", "st", "sk", "ta", "da", "gu", "lo", "gl", "uk", "el", "ml", "vi", "si", "pt", "mt", "it", "so", "ceb", "hr", "bg", "lv", "tg", "te", "ht", "ha", "pa", "su", "ur", "ca", "cs", "ne", "sr", "sq", "my", "af", "et", "hu", "cy", "ms", "ru", "mr", "ga", "bs", "hmn", "hy", "sw", "is", "sv", "fi", "eo", "ka", "jw", "mk", "zh-TW", "mi", "sl", "ny", "es", "th", "km", "yo", "zu", "ja", "tr", "nl", "kn", "yi", "az", "he", "ar", "hi", "kk", "fr", "en", "en-us"]
    
    let translationUrl = "http://clients5.google.com/translate_a/t"
    let parametersString = "client=dict-chrome-ex&q={{text}}&sl={{from_lang}}&tl={{to_lang}}&tbb=1&ie=UTF-8&oe=UTF-8&hl=en"
    let oneRequestLimit = 1000
    
    init() {
        
    }
    
    func getRawTranslation(_ from:String, to:String, text:String) -> String? {
        var resultString: String?
        
        let sessionConfig = URLSessionConfiguration.default
        
        sessionConfig.timeoutIntervalForRequest = 20.0
        sessionConfig.timeoutIntervalForResource = 20.0
        
        let session = URLSession(configuration: sessionConfig)
        
        var postString = parametersString
        
        postString = postString.replacingOccurrences(of: "{{text}}",
                                                     with: text.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!.replacingOccurrences(of: "&", with: "%26"),
                                                     options: NSString.CompareOptions.literal, range: nil)
        postString = postString.replacingOccurrences(of: "{{from_lang}}", with: from, options: NSString.CompareOptions.literal, range: nil)
        postString = postString.replacingOccurrences(of: "{{to_lang}}", with: to, options: NSString.CompareOptions.literal, range: nil)
        // postString = postString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
        
        var request = URLRequest(url: URL(string: "\(translationUrl)?\(postString)")!)
        request.httpMethod = "POST"
        
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11) AppleWebKit/601.1.56 (KHTML, like Gecko) Version/9.0 Safari/601.1.56", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        let semaphore = DispatchSemaphore(value: 0)
        
        //request.HTTPBody = postString.dataUsingEncoding(NSUTF8StringEncoding)
        
        let task = session.dataTask(with: request, completionHandler: {
            data, response, error in
            
            if error != nil {
                print("error \(error!)")
                semaphore.signal()
                return
            }
            
            if let responseData = data {
                var stringResult = NSString(data: responseData, encoding: String.Encoding.utf8.rawValue)! as String
                stringResult = stringResult.replacingOccurrences(of: ",,", with: ",0,")
                stringResult = stringResult.replacingOccurrences(of: ",,", with: ",0,")
                stringResult = stringResult.replacingOccurrences(of: "[,", with: "[0,")
                stringResult = stringResult.replacingOccurrences(of: ",]", with: ",0]")
                
                resultString = stringResult
            }
            
            semaphore.signal()
        })
        
        task.resume()
        _ = semaphore.wait(timeout: DispatchTime.distantFuture)
        
        return resultString
    }
    
    fileprivate func getTranslation(_ from:String, to:String, text:String) -> (json: JSON, isNative: Bool)? {
        
        if text.count > oneRequestLimit {
            // separating by whitespaces because "." can vary in different languages and can be found in numbers like 4.20
            let words = text.components(separatedBy: NSCharacterSet.whitespacesAndNewlines)
            
            var smallerStrings = [String]()
            
            // looping through all the words and creating separate strings each no larger (or a little bit larger) that the limit
            var i = 0
            for word in words {
                if smallerStrings.count < i + 1 {
                    smallerStrings.append(word)
                } else {
                    if smallerStrings[i].count >= oneRequestLimit {
                        i += 1
                        smallerStrings.append(word)
                    } else {
                        smallerStrings[i] += " \(word)"
                    }
                }
            }
            
            var resultString = ""
            var resultTranslit = ""
            var sourceLanguage: String? = nil
            
            
            // looping thorough all the small strings, translating them and adding to the result
            // same for translit
            // detected language is taken from the first string, as the last can happen to be something like "Google"
            for smallString in smallerStrings {
                if let translationJsonString = getRawTranslation(from, to: to, text: smallString) {
                    let smallTranslationJson = (try? JSON(data: translationJsonString.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions.mutableContainers)) ?? JSON()
                    
                    resultString += "\(getText(smallTranslationJson)) "
                    
                    if sourceLanguage == nil {
                        sourceLanguage = getSourceLanguage(smallTranslationJson)
                    }
                }
            }
            
            // creating a native json
            let jsonArray: Any = [
                false, // isMulti
                text, // original
                "",
                resultString, // translated text
                resultTranslit, // transliteration
                sourceLanguage ?? "" // source language
            ]
            
            return (JSON(jsonArray), isNative: true)
        }
        
        if let translationJsonString = getRawTranslation(from, to: to, text: text) {
            return (json: (try? JSON(data: translationJsonString.data(using: String.Encoding.utf8)!, options: JSONSerialization.ReadingOptions.mutableContainers)) ?? JSON(), isNative: false)
        }
        
        return nil
    }
    
    fileprivate func getText(_ json:JSON) -> String {
        return json.arrayValue.first?.string ?? json.arrayValue.first?.arrayValue.first?.stringValue ?? ""
    }
    
    private func getSourceLanguage(_ json: JSON) -> String {
        return json.arrayValue.first?.arrayValue.last?.stringValue ?? ""
    }
    
    open func getNativeJson(_ from: String, to: String, text: String, autocorrected: String? = nil) -> JSON? {
        let googleTranslation = getTranslation(from, to: to, text: text)
        if let googleJson = googleTranslation?.json {
            
            if googleTranslation?.isNative == true {
                return googleJson
            }
            
            return convertGoogleJsonToNative(googleJson, from: from, targetLanguage: to, text: text)
        } else {
            return nil
        }
    }
    
    fileprivate func convertGoogleJsonToNative(_ googleJson: JSON, from: String, targetLanguage: String, text: String) -> JSON? {
        let jsonArray = NSMutableArray()
        let translatedText = getText(googleJson)
        //is multi
        let multi = googleJson["dict"] != JSON.null
        jsonArray.add(multi)
        
        //orig
        jsonArray.add(text)
        
        //transcript
        jsonArray.add("")
        
        
        //tranaslated
        jsonArray.add(translatedText)
        
        //translit
        jsonArray.add("")
        
        //source lang
        if from == "auto", let sourceLang = detectedLanguage(for: text) {
            jsonArray.add(sourceLang)
        } else {
            jsonArray.add(from)
        }
        
        //target lang
        jsonArray.add(targetLanguage)
        
        //synonyms
        let synonymsDictionary = NSMutableDictionary()
        
        //print(googleJson)
        
        if googleJson["dict"] != JSON.null {
            let limit = 50
            
            var i = 0
            
            for (_, subJSON): (String, JSON) in googleJson["dict"] {
                
                if i > limit {
                    break
                }
                i += 1
                
                //group - part of speech
                if let group = subJSON["pos"].string {
                    let words = NSMutableArray()
                    
                    for (_, subSubJSON): (String, JSON) in subJSON["entry"] {
                        let word:NSMutableArray = NSMutableArray()
                        
                        //translation
                        if let stringWord = subSubJSON["word"].string {
                            word.add(stringWord)
                        } else {
                            word.add("")
                        }
                        
                        //reverse array
                        let reverseWords = NSMutableArray()
                        
                        for i in 0 ..< 3 {
                            if let reverse = subSubJSON["reverse_translation"][i].string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) {
                                reverseWords.add(reverse)
                            }else{
                                reverseWords.add("")
                            }
                        }
                        word.add(reverseWords)
                        
                        //gender
                        if let gender = subSubJSON["previous_word"].string {
                            word.add(gender)
                        } else if let gender = subSubJSON["gender"].string {
                            word.add(gender)
                        } else {
                            word.add("")
                        }
                        
                        words.add(word)
                    }
                    
                    synonymsDictionary.setObject(words, forKey: NSString(string: group))
                    //print("\n\n\n\n\(synonymsDictionary)\n\n\n\n")
                    
                }
                
            }
        }
        
        let synonymsArray = NSMutableArray()
        for i in 0 ..< CorrectNativeJsonIndexes.indexesToPartsOfSpeech.count {
            let part = CorrectNativeJsonIndexes.indexesToPartsOfSpeech[i]!
            if let array = synonymsDictionary[part] as? NSArray{
                synonymsArray.add(array)
            }else{
                synonymsArray.add(NSArray())
            }
        }
        
        jsonArray.add(synonymsArray)
        
        //print(synonymsArray)
        
        return JSON(jsonArray)
        
    }
    
    func detectedLanguage(for string: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(string)
        guard let languageCode = recognizer.dominantLanguage?.rawValue.lowercased() else { return nil }
        if supportedLanguages.contains(languageCode) {
            return languageCode
        }
        return nil
    }
    
}

