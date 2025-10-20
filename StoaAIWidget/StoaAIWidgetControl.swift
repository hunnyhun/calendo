//
//  StoaAIWidgetControl.swift
//  StoaAIWidget
//
//  Created by Ahmet Kemal  Akbudak on 19.07.2025.
//

import AppIntents
import SwiftUI
import WidgetKit

struct StoaAIWidgetControl: ControlWidget {
    static let kind: String = "com.hunnyhun.stoicism.StoaAIWidget"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { value in
            ControlWidgetButton(action: RefreshQuoteIntent()) {
                Label("Refresh Quote", systemImage: "quote.bubble")
                    .foregroundColor(.blue)
            }
        }
        .displayName("Stoa AI Quote")
        .description("Refresh your daily Stoic wisdom quote.")
    }
}

extension StoaAIWidgetControl {
    struct Value {
        var lastRefreshTime: Date
        var quotesAvailable: Bool
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: QuoteConfiguration) -> Value {
            StoaAIWidgetControl.Value(lastRefreshTime: Date(), quotesAvailable: true)
        }

        func currentValue(configuration: QuoteConfiguration) async throws -> Value {
            let quotesAvailable = true // You can add logic to check if quotes are available
            return StoaAIWidgetControl.Value(lastRefreshTime: Date(), quotesAvailable: quotesAvailable)
        }
    }
}

struct QuoteConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Quote Source Configuration"

    @Parameter(title: "Quote Source", default: "Daily Wisdom")
    var quoteSource: String
}

struct RefreshQuoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Daily Quote"
    static let description: IntentDescription = "Get a new Stoic wisdom quote"

    func perform() async throws -> some IntentResult {
        // Trigger quote refresh in the main app
        // This could update UserDefaults or send a notification to the main app
        let sharedDefaults = UserDefaults(suiteName: "group.com.hunnyhun.stoicism")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "lastQuoteRefreshRequest")
        
        return .result()
    }
}
