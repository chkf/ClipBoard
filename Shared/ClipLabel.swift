import SwiftUI

struct ClipLabel: View {
    let row: ClipRow
    let session: ClipboardSession
    var compact = false
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if row.isImage {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(height: compact ? 52 : 86)
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityLabel("图片")
                .task(id: row.id) {
                    thumbnail = nil
                    guard let bytes = try? await session.store?.thumbnail(row.id), !Task.isCancelled else { return }
                    thumbnail = UIImage(data: bytes)
                }
            } else {
                Text(verbatim: row.preview)
                    .lineLimit(compact ? 2 : 3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 32 : 40, alignment: .leading)
        .contentShape(Rectangle())
    }
}
