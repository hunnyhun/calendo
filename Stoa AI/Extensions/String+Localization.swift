import Foundation
import os.log

// MARK: - String Localization Extension
extension String {
    // Returns localized string using self as key
    var localized: String {
        let bundle = Bundle.main
        let localizedString = NSLocalizedString(self, tableName: "Localizable", bundle: bundle, value: self, comment: "")
        
        // Only warn if the returned value equals the key AND we're not using English
        // (English translations often match their keys, so we don't want false warnings)
        if localizedString == self {
            let preferredLanguages = bundle.preferredLocalizations
            let currentLang = preferredLanguages.first ?? "en"
            let langCode = currentLang.split(separator: "_").first.map(String.init) ?? "en"
            
            // Only warn for non-English languages where the translation might actually be missing
            if langCode != "en" {
                Logger.warning("Missing translation for key: \(self) (current language: \(currentLang))", logger: Logger.localization)
            }
            // For English, suppress warnings since translations matching keys is expected
        }
        
        return localizedString
    }
    
    // Returns localized string with format arguments
    func localized(_ args: CVarArg...) -> String {
        let bundle = Bundle.main
        let localizedString = NSLocalizedString(self, tableName: "Localizable", bundle: bundle, value: self, comment: "")
        
        // Same logic as above for warnings
        if localizedString == self {
            let preferredLanguages = bundle.preferredLocalizations
            let currentLang = preferredLanguages.first ?? "en"
            let langCode = currentLang.split(separator: "_").first.map(String.init) ?? "en"
            
            if langCode != "en" {
                Logger.warning("Missing translation for key: \(self) (current language: \(currentLang))", logger: Logger.localization)
            }
        }
        
        return String(format: localizedString, arguments: args)
    }
} 