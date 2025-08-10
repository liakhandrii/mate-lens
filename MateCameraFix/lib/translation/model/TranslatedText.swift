//
//  TranslatedText.swift
//  MateCameraFix
//
//  Created by Andrew Liakh on 10.08.25.
//

import SwiftyJSON

enum PartOfSpeech: String, CaseIterable {
    case noun, verb, adjective, adverb, pronoun, preposition, conjunction, interjection, abbreviation, phrase, suffix, auxiliaryverb
}

struct Synonym {
    let word: String
    let reverseTranslations: [String]
    let gender: String?
    
    init(json: JSON) {
        self.word = json[CorrectNativeJsonIndexes.synWord].stringValue
        self.reverseTranslations = json[CorrectNativeJsonIndexes.synReverse].arrayValue.map { $0.stringValue }.filter { !$0.isEmpty }
        let genderValue = json[CorrectNativeJsonIndexes.synGender].stringValue
        self.gender = genderValue.isEmpty ? nil : genderValue
    }
}

struct TranslatedText {
    let isMulti: Bool
    let original: String
    let translatedTranscription: String?
    let translated: String
    let translit: String?
    let sourceLanguage: String
    let targetLanguage: String
    let synonymsByPartOfSpeech: [PartOfSpeech: [Synonym]]
    
    init(json: JSON) {
        self.isMulti = json[CorrectNativeJsonIndexes.isMulti].boolValue
        self.original = json[CorrectNativeJsonIndexes.original].stringValue
        
        let transcriptionValue = json[CorrectNativeJsonIndexes.translatedTranscription].stringValue
        self.translatedTranscription = transcriptionValue.isEmpty ? nil : transcriptionValue
        
        self.translated = json[CorrectNativeJsonIndexes.translated].stringValue
        
        let translitValue = json[CorrectNativeJsonIndexes.translit].stringValue
        self.translit = translitValue.isEmpty ? nil : translitValue
        
        self.sourceLanguage = json[CorrectNativeJsonIndexes.sourceLanguage].stringValue
        self.targetLanguage = json[CorrectNativeJsonIndexes.targetLanguage].stringValue
        
        var synonymsDict: [PartOfSpeech: [Synonym]] = [:]
        let synonymsArray = json[CorrectNativeJsonIndexes.synonymsArray].arrayValue
        
        for (index, synonymGroup) in synonymsArray.enumerated() {
            if let partOfSpeechString = CorrectNativeJsonIndexes.indexesToPartsOfSpeech[index], 
               !partOfSpeechString.isEmpty,
               let partOfSpeech = PartOfSpeech(rawValue: partOfSpeechString) {
                let synonyms = synonymGroup.arrayValue.map { Synonym(json: $0) }.filter { !$0.word.isEmpty }
                if !synonyms.isEmpty {
                    synonymsDict[partOfSpeech] = synonyms
                }
            }
        }
        
        self.synonymsByPartOfSpeech = synonymsDict
    }
}

class CorrectNativeJsonIndexes {
    
    let numberOfElements = 8
    
    static let isMulti = 0
    static let original = 1
    static let translatedTranscription = 2
    static let translated = 3
    static let translit = 4
    static let sourceLanguage = 5
    static let targetLanguage = 6
    static let synonymsArray = 7
    
    static let synWord = 0
    static let synGender = 2
    static let synReverse = 1
    
    static let indexesToPartsOfSpeech: [Int: String] = [
        0: "",
        1: "noun",
        2: "verb",
        3: "adjective",
        4: "adverb",
        5: "pronoun",
        6: "preposition",
        7: "conjunction",
        8: "interjection",
        9: "abbreviation",
        10: "phrase",
        11: "suffix",
        12: "auxiliaryverb"
    ]
    
    static func createEmptyJson() -> JSON {
        let res = "[false,\"\",\"\",\"\",\"\",\"\",\"\",[[],[],[],[],[],[],[],[],[],[],[],[],[]]]"
        
        return try! JSON(data: res.data(using: String.Encoding.utf8, allowLossyConversion: false)!, options: JSONSerialization.ReadingOptions.mutableContainers)
    }
    
}
