//
//  SeenlyWidget.swift
//  SeenlyWidget (WidgetKit extension target — see HomeWidgetSetup.md
//  for the one-time manual Xcode steps needed to turn this file into
//  an actual build target; it does nothing sitting here on disk).
//
//  Renders whatever the Flutter side last pushed via
//  HomeWidget.saveWidgetData (lib/services/home_widget_service.dart):
//  a countdown to the next co-viewing evening, today's pick, the
//  current streak, or an empty/locked placeholder. Mirrors
//  SeenlyWidgetProvider.kt's five states and fixed "diary paper" look
//  — see that file's own doc comment for why the colors are a fixed
//  hex set rather than tracking the in-app skin/flavor/brightness
//  choice.
//
//  Shape checked against home_widget v0.6.0's own reference example
//  (ABausG/home_widget, example/ios/HomeWidgetExample/
//  HomeWidgetExample.swift) rather than written from memory —
//  UserDefaults(suiteName:), the plain-TimelineProvider shape, and
//  Image(uiImage: UIImage(contentsOfFile:)) for a HomeWidget-rendered
//  file are all taken directly from there.

import SwiftUI
import WidgetKit

// Must equal HomeWidgetService._appGroupId exactly — this is what
// HomeWidget.setAppGroupId on the Flutter side points saveWidgetData
// at, and it's also an Xcode-side setting (App Groups capability, both
// the Runner target and this extension target) with no compiler check
// tying the three together. See HomeWidgetSetup.md step 3.
private let widgetGroupId = "group.com.example.seenly.widget"

struct SeenlyWidgetEntry: TimelineEntry {
    let date: Date
    let state: String // "countdown" | "pick" | "streak" | "empty" | "locked"
    let title: String
    let subtitle: String
    let number: String
    let posterPath: String?
}

struct SeenlyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SeenlyWidgetEntry {
        SeenlyWidgetEntry(
            date: Date(), state: "streak", title: "твой стрик", subtitle: "дней подряд",
            number: "7", posterPath: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SeenlyWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SeenlyWidgetEntry>) -> Void) {
        let entry = readEntry()
        // The Flutter side is the real source of truth (it pushes on
        // its own at app-pause and sign-in — see
        // HomeWidgetService.refresh's doc comment); this `.after` is
        // only WidgetKit's own safety-net reload so a widget that's
        // been sitting untouched for a while still asks again, mirroring
        // Android's updatePeriodMillis floor in seenly_widget_info.xml.
        let nextReload = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }

    private func readEntry() -> SeenlyWidgetEntry {
        let data = UserDefaults(suiteName: widgetGroupId)
        return SeenlyWidgetEntry(
            date: Date(),
            state: data?.string(forKey: "state") ?? "empty",
            title: data?.string(forKey: "title") ?? "",
            subtitle: data?.string(forKey: "subtitle") ?? "",
            number: data?.string(forKey: "number") ?? "",
            posterPath: data?.string(forKey: "poster_path"))
    }
}

private enum SeenlyWidgetPalette {
    // Same fixed light-classic hex set as seenly_widget_background.xml
    // and SeenlyWidgetProvider.kt — see their comments for why.
    static let paper = Color(red: 1.0, green: 0.992, blue: 0.973) // #FFFDF8
    static let border = Color(red: 0.894, green: 0.851, blue: 0.769) // #E4D9C4
    static let ink = Color(red: 0.290, green: 0.247, blue: 0.220) // #4A3F38
    static let inkMuted = Color(red: 0.541, green: 0.478, blue: 0.408) // #8A7A68
    static let inkFaint = Color(red: 0.659, green: 0.588, blue: 0.498) // #A8967F
    static let accent = Color(red: 0.490, green: 0.353, blue: 0.420) // #7D5A6B
}

struct SeenlyWidgetEntryView: View {
    var entry: SeenlyWidgetProvider.Entry

    private var posterImage: UIImage? {
        guard entry.state == "pick", let path = entry.posterPath, !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("tanè")
                .font(.system(size: 9))
                .tracking(0.8)
                .foregroundColor(SeenlyWidgetPalette.inkFaint)

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 12) {
                if let poster = posterImage {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if !entry.number.isEmpty {
                    Text(entry.number)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(SeenlyWidgetPalette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if !entry.title.isEmpty {
                        Text(entry.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(SeenlyWidgetPalette.ink)
                            .lineLimit(2)
                    }
                    Text(entry.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(SeenlyWidgetPalette.inkMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SeenlyWidgetPalette.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(SeenlyWidgetPalette.border, lineWidth: 1)
        )
        // No routing to a specific screen yet — see
        // HomeWidgetService's doc comment on scope — every state opens
        // the app the same way, distinguished from the referral
        // deep-link's "invite" host only so app-side routing can special-
        // case it later without a scheme change.
        .widgetURL(URL(string: "seenly://widget"))
    }
}

struct SeenlyWidget: Widget {
    let kind: String = "SeenlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SeenlyWidgetProvider()) { entry in
            SeenlyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("tanè")
        .description("Сегодняшний стрик, подобранное под тебя или обратный отсчёт до совместного вечера.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SeenlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        SeenlyWidget()
    }
}

struct SeenlyWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SeenlyWidgetEntryView(entry: SeenlyWidgetEntry(
                date: Date(), state: "streak", title: "твой стрик", subtitle: "7 дней подряд",
                number: "7", posterPath: nil))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            SeenlyWidgetEntryView(entry: SeenlyWidgetEntry(
                date: Date(), state: "countdown", title: "Дюна: Часть вторая",
                subtitle: "вечер с Аней", number: "завтра", posterPath: nil))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
