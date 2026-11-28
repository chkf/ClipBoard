import SwiftUI

struct ClipLabel: View {
    let row: ClipRow
    let session: ClipboardSession
    let keyHeight: CGFloat
    @State private var thumbnail: (id: String, image: UIImage)?

    var body: some View {
        HStack(spacing: 0) {
            if row.isImage {
                Group {
                    if let thumbnail, thumbnail.id == row.id {
                        Image(uiImage: thumbnail.image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(height: min(42, keyHeight - 4), alignment: .leading)
                .accessibilityLabel("图片")
                .task(id: row.id) {
                    guard thumbnail?.id != row.id, let bytes = await session.thumbnail(row.id),
                          !Task.isCancelled, let image = UIImage(data: bytes) else { return }
                    thumbnail = (row.id, image)
                }
            } else {
                Text(verbatim: row.preview)
                    .font(.body).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
