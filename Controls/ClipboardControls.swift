import ActivityKit
import SwiftUI
import WidgetKit

@main struct ClipboardControls: WidgetBundle {
    var body: some Widget {
        CopyControl()
        CopyIsland()
    }
}

struct CopyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: CollectionControl.kind) {
            ControlWidgetButton(action: ToggleCopyCollection()) {
                Label("连续复制", systemImage: CollectionControl.symbol)
            }.tint(.mint)
        }.displayName("Clipboard 连续复制").description("开启或结束跨 App 连拷。")
    }
}

private struct CopyIsland: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CopyActivity.self) { context in
            HStack {
                Image(systemName: "list.clipboard")
                Text("连续复制")
                Spacer()
                Text("已收 \(context.state.count) 条").monospacedDigit()
                Button(intent: EndCopyCollection()) { Image(systemName: "stop.fill") }.accessibilityLabel("停止连拷")
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white).foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("连续复制", systemImage: "list.clipboard") }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.count) 条").monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: EndCopyCollection()) { Label("停止连拷", systemImage: "stop.fill") }
                }
            } compactLeading: { Image(systemName: "list.clipboard").foregroundStyle(.mint) }
              compactTrailing: { Text("\(context.state.count)").monospacedDigit() }
              minimal: { Image(systemName: "list.clipboard").foregroundStyle(.mint) }
              .widgetURL(URL(string: "clipboard-collect://session"))
        }
    }
}
