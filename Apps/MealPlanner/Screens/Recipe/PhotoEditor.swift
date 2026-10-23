import AppKit
import CoreTransferable
import MealStore
import SwiftUI
import UniformTypeIdentifiers

/// The recipe's photo while editing: drop a file or a picture from Safari, paste one, pick a file or give
/// a link. Every photo is shrunk to 1600 px and kept in the app's folder.
struct PhotoEditor: View {
    let images: ImageStore
    @Binding var photo: String?

    @State private var isTargeted = false
    @State private var importing = false
    @State private var askingLink = false
    @State private var link = ""
    @State private var isLoading = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let photo {
                    CoverImage(url: images.url(for: photo), height: 220)
                } else {
                    Color(.surfaceRaised)
                        .frame(height: 220)
                        .overlay {
                            Label("Перетащите фото сюда", systemImage: "photo")
                                .foregroundStyle(Color(.textSecondary))
                        }
                }
                if isLoading {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color(.hairline),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: photo == nil ? [6] : []))
            )
            .dropDestination(for: DroppedImage.self) { items, _ in
                guard let item = items.first else { return false }
                take(item)
                return true
            } isTargeted: {
                isTargeted = $0
            }
            HStack {
                Button("Выбрать файл…") { importing = true }
                Button("Вставить", action: paste)
                Button("По ссылке…") {
                    link = ""
                    askingLink = true
                }
                if photo != nil {
                    Button("Убрать фото", role: .destructive) { photo = nil }
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                store { try images.save(contentsOf: url) }
            case .failure(let error):
                problem = String(describing: error)
            }
        }
        .alert("Фото по ссылке", isPresented: $askingLink) {
            TextField("https://…", text: $link)
            Button("Загрузить") {
                if let url = URL(string: link.trimmingCharacters(in: .whitespaces)) { download(url) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func take(_ item: DroppedImage) {
        switch item {
        case .data(let data): store { try images.save(data) }
        case .web(let url): download(url)
        }
    }

    /// A picture copied in Preview or Safari, an image file copied in Finder, or a link to a picture.
    private func paste() {
        let pasteboard = NSPasteboard.general
        if let file =
            (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first
        {
            store { try images.save(contentsOf: file) }
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            store { try images.save(data) }
        } else if let text = pasteboard.string(forType: .string), let url = URL(string: text),
            url.scheme?.hasPrefix("http") == true
        {
            download(url)
        } else {
            problem = "В буфере обмена нет картинки."
        }
    }

    private func store(_ save: () throws -> String) {
        do {
            photo = try save()
            problem = nil
        } catch {
            problem = String(describing: error)
        }
    }

    private func download(_ url: URL) {
        isLoading = true
        Task {
            do {
                photo = try await images.download(url)
                problem = nil
            } catch {
                problem = String(describing: error)
            }
            isLoading = false
        }
    }
}

/// What can be dropped on the photo: image data, an image file, or a link to download.
enum DroppedImage: Transferable {
    case data(Data)
    case web(URL)

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in DroppedImage.data(data) }
        ProxyRepresentation(importing: { (url: URL) in
            url.isFileURL ? DroppedImage.data(try Data(contentsOf: url)) : DroppedImage.web(url)
        })
    }
}
