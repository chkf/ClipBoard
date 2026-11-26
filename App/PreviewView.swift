import SwiftUI

struct PreviewView: View {
    let row: ClipRow
    let session: ClipboardSession
    @Environment(\.dismiss) private var dismiss
    @State private var bodyValue: ClipBody?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let text = bodyValue?.text {
                    ScrollView {
                        Text(verbatim: text).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                } else if let data = bodyValue?.data, let image = UIImage(data: data) {
                    ZoomImage(image: image).accessibilityLabel("完整图片")
                } else if failed {
                    ContentUnavailableView("记录不可用", systemImage: "doc.questionmark")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(row.isImage ? "图片预览" : "文本预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }.accessibilityIdentifier("closePreview")
                }
            }
        }
        .task {
            bodyValue = await session.body(row)
            failed = bodyValue == nil
        }
    }
}

private struct ZoomImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView(image: image) }
    func updateUIView(_ view: ImageScrollView, context: Context) {}
}

private final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
    let picture: UIImageView
    private var fittedSize = CGSize.zero

    init(image: UIImage) {
        picture = UIImageView(image: image)
        super.init(frame: .zero)
        addSubview(picture)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        if fittedSize != size, size.width > 0, size.height > 0, let original = picture.image?.size {
            fittedSize = size
            let fit = min(size.width / original.width, size.height / original.height)
            minimumZoomScale = fit
            maximumZoomScale = max(3, fit * 5)
            zoomScale = fit
        }
        picture.center = CGPoint(x: max(contentSize.width, size.width) / 2,
                                 y: max(contentSize.height, size.height) / 2)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
}
