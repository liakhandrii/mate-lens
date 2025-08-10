//
//  TranslatedTextTests.swift
//  MateCameraFixTests
//
//  Created by Andrew Liakh on 10.08.25.
//

import XCTest
import SwiftyJSON
@testable import MateCameraFix

final class TranslatedTextTests: XCTestCase {
    
    func testTranslatedTextParser() {
        let jsonString = """
        [
            true,
            "hello",
            "həˈloʊ",
            "hola",
            "hola",
            "en",
            "es",
            [
                [],
                [
                    ["greeting", ["hi", "hey"], "f"],
                    ["salutation", ["welcome"], null]
                ],
                [
                    ["greet", ["say hello"], null]
                ]
            ]
        ]
        """
        
        let json = try! JSON(data: jsonString.data(using: .utf8)!)
        let translatedText = TranslatedText(json: json)
        
        XCTAssertTrue(translatedText.isMulti)
        XCTAssertEqual(translatedText.original, "hello")
        XCTAssertEqual(translatedText.translatedTranscription, "həˈloʊ")
        XCTAssertEqual(translatedText.translated, "hola")
        XCTAssertEqual(translatedText.translit, "hola")
        XCTAssertEqual(translatedText.sourceLanguage, "en")
        XCTAssertEqual(translatedText.targetLanguage, "es")
        
        // Test noun synonyms
        let nouns = translatedText.synonymsByPartOfSpeech[.noun]
        XCTAssertNotNil(nouns)
        XCTAssertEqual(nouns?.count, 2)
        
        let greeting = nouns?.first { $0.word == "greeting" }
        XCTAssertNotNil(greeting)
        XCTAssertEqual(greeting?.reverseTranslations, ["hi", "hey"])
        XCTAssertEqual(greeting?.gender, "f")
        
        let salutation = nouns?.first { $0.word == "salutation" }
        XCTAssertNotNil(salutation)
        XCTAssertEqual(salutation?.reverseTranslations, ["welcome"])
        XCTAssertNil(salutation?.gender)
        
        // Test verb synonyms
        let verbs = translatedText.synonymsByPartOfSpeech[.verb]
        XCTAssertNotNil(verbs)
        XCTAssertEqual(verbs?.count, 1)
        XCTAssertEqual(verbs?.first?.word, "greet")
        XCTAssertEqual(verbs?.first?.reverseTranslations, ["say hello"])
        XCTAssertNil(verbs?.first?.gender)
    }
}
