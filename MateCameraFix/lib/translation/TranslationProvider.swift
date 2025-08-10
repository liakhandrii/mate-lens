//
//  TranslationProvider.swift
//  Mate Translate
//
//  Created by Andrew Liakh on 10.11.22.
//  Copyright © 2022 Andrii Liakh. All rights reserved.
//

import SwiftyJSON

protocol TranslationProvider {
    func getNativeJson(_ from: String, to: String, text: String, autocorrected: String?) -> JSON?
}
