//
//  StoaAIWidget.swift
//  StoaAIWidget
//
//  Created by Ahmet Kemal  Akbudak on 19.07.2025.
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), quote: NSLocalizedString("CFBundleDisplayName", tableName: "InfoPlist", bundle: .main, value: "Stoa AI", comment: ""))
    }

    func getLastDailyQuote() -> String {
        let sharedDefaults = UserDefaults(suiteName: "group.com.hunnyhun.stoicism")
        let value = sharedDefaults?.string(forKey: "lastDailyQuote")
        print("[StoaAIWidget] Read last quote from App Group: \(value ?? "nil")")
        return value ?? "You have power over your mind - not outside events. Realize this, and you will find strength."
    }

    func getEntry(for date: Date) -> SimpleEntry {
        let quote = getLastDailyQuote()
        return SimpleEntry(date: date, quote: quote)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = getEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let currentDate = Date()
        let entry = getEntry(for: currentDate)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let quote: String
}

// MARK: - Stoic Cross for Widget (similar to TraditionalCross but adapted for Stoicism)
struct WidgetStoicSymbol: View {
    let width: CGFloat
    let color: Color
    let shadowColor: Color
    
    var body: some View {
        let height = width * (8/5)
        let thickness = width / 5
        let horizontalPosition = height * 0.2
        
        ZStack {
            // Vertical beam
            Rectangle()
                .fill(color)
                .frame(width: thickness, height: height)
            // Horizontal beam
            Rectangle()
                .fill(color)
                .frame(width: width, height: thickness)
                .offset(y: -height/2 + horizontalPosition + thickness/2)
        }
        .frame(width: width, height: height)
        .shadow(color: shadowColor, radius: 2, x: 1, y: 1)
    }
}

struct StoaAIWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        HStack(spacing: 12) {
            // Marcus Aurelius Image with fallback
            Group {
                if let image = UIImage(named: "MarcusAurelius") {
                    Image(uiImage: image)
                        .resizable()
                } else {
                    // Fallback to a philosopher-like system image
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.blue)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
            )
            
            // Quote Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.quote)
                    .font(.system(size: 12, weight: .medium, design: .serif))
                    .foregroundColor(.primary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                
                Spacer(minLength: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct StoaAIWidget: Widget {
    let kind: String = "StoaAIWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StoaAIWidgetEntryView(entry: entry)
                .containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Stoa AI Daily Quote")
        .description("Shows your most recent daily quote from Stoa AI.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    StoaAIWidget()
} timeline: {
    SimpleEntry(date: .now, quote: "You have power over your mind - not outside events. Realize this, and you will find strength.")
}
