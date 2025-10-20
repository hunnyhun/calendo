//
//  StoaAIWidgetLiveActivity.swift
//  StoaAIWidget
//
//  Created by Ahmet Kemal  Akbudak on 19.07.2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct StoaAIWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var quote: String
    }

    // Fixed non-changing properties about your activity go here!
    var title: String
}

struct StoaAIWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StoaAIWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Stoa AI")
                    .font(.headline)
                    .foregroundColor(.blue)
                Text(context.state.quote)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .activityBackgroundTint(Color.white)
            .activitySystemActionForegroundColor(Color.blue)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("📚")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Stoa AI")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.quote)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            } compactLeading: {
                Text("📚")
            } compactTrailing: {
                Text("💭")
            } minimal: {
                Text("📚")
            }
            .widgetURL(URL(string: "stoaai://"))
            .keylineTint(Color.blue)
        }
    }
}

extension StoaAIWidgetAttributes {
    fileprivate static var preview: StoaAIWidgetAttributes {
        StoaAIWidgetAttributes(title: "Daily Wisdom")
    }
}

extension StoaAIWidgetAttributes.ContentState {
    fileprivate static var stoicQuote: StoaAIWidgetAttributes.ContentState {
        StoaAIWidgetAttributes.ContentState(quote: "You have power over your mind - not outside events. Realize this, and you will find strength.")
     }
     
     fileprivate static var marcusQuote: StoaAIWidgetAttributes.ContentState {
         StoaAIWidgetAttributes.ContentState(quote: "The happiness of your life depends upon the quality of your thoughts.")
     }
}

#Preview("Notification", as: .content, using: StoaAIWidgetAttributes.preview) {
   StoaAIWidgetLiveActivity()
} contentStates: {
    StoaAIWidgetAttributes.ContentState.stoicQuote
    StoaAIWidgetAttributes.ContentState.marcusQuote
}
