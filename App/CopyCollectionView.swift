import SwiftUI
import UIKit

struct CopyCollectionView: View {
    @ObservedObject var collector: CopyCollector
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CopyCollector.startWhenOpenedKey) private var startWhenOpened = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    PictureSource(collector: collector)
                        .aspectRatio(320/112, contentMode: .fit).frame(maxWidth: .infinity)
                        .background(Color(red: 0.08, green: 0.10, blue: 0.13), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    LabeledContent("本次已收", value: "\(collector.count) 条").accessibilityIdentifier("captureCount")
                    Button(collector.phase == .idle ? "开始连拷" : collector.phase == .starting ? "取消启动" : "停止连拷") {
                        collector.requestToggle()
                    }.accessibilityIdentifier("captureToggle")
                } footer: {
                    Text("小窗开启后，在其他 App 正常复制。可把小窗拖到屏幕边缘收起。关闭小窗或锁屏会结束本次收集。")
                }
                if collector.pending > 0, collector.phase == .idle {
                    Section {
                        Button("存入键盘（\(collector.pending) 条）") { collector.showImport = true }
                            .accessibilityIdentifier("deliverCopies")
                    } footer: { Text("记录已保存在本机。首次接收后，切到键盘可自动取回近期记录。较大的图片和剩余记录可在这里整批存入。") }
                }
                if let message = collector.message {
                    Section { Text(message).font(.footnote).accessibilityIdentifier("captureStatus") }
                }
                Section {
                    Toggle("打开 Clipboard 时开始连拷", isOn: $startWhenOpened)
                        .accessibilityIdentifier("collectWhenOpened")
                } header: { Text("控制中心") } footer: {
                    Text("如果「连续复制」控件是空白的，打开这个选项，在控制中心添加苹果的「打开 App」，选 Clipboard。以后点它或桌面图标都会启动连拷。收集中打开 App 可查看计数或点停止。")
                }
            }
            .navigationTitle("连续复制")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { await collector.refreshPending() }
        .sheet(isPresented: $collector.showImport, onDismiss: { Task { await collector.refreshPending() } }) { CaptureDeliveryView() }
    }
}

private struct PictureSource: UIViewRepresentable {
    let collector: CopyCollector
    func makeUIView(context: Context) -> Source { Source(collector: collector) }
    func updateUIView(_ view: Source, context: Context) {}
    final class Source: UIView {
        let collector: CopyCollector
        init(collector: CopyCollector) { self.collector = collector; super.init(frame: .zero); clipsToBounds = true; layer.cornerRadius = 12 }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() { super.layoutSubviews(); if window != nil { collector.mountPicture(self) } }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { collector.mountPicture(self); collector.picture.render(count: collector.count) }
            else { collector.unmountPicture(self) }
        }
    }
}
