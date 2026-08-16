import Foundation
import UniformTypeIdentifiers

/// Which files a Drop Transcription will accept. Asked of the system rather
/// than matched against a list of extensions, so every container macOS can
/// decode is covered and nothing has to be maintained here.
enum MediaFileTypes {
  /// The decision itself, over a type the caller already resolved. Audio and
  /// video only: a video's audio track is what gets transcribed.
  static func isTranscribable(_ type: UTType?) -> Bool {
    guard let type else { return false }
    return type.conforms(to: .audio) || type.conforms(to: .movie)
  }

  /// The type macOS reports for this URL. The file's recorded type wins,
  /// because a file can be named anything; its extension is the fallback for
  /// a URL that names nothing on disk yet.
  static func contentType(of url: URL) -> UTType? {
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      return type
    }
    return UTType(filenameExtension: url.pathExtension)
  }

  static func isTranscribable(url: URL) -> Bool {
    isTranscribable(contentType(of: url))
  }

  /// The set an open panel offers. Deriving it from the same two parent types
  /// keeps the picker and the drop target answering identically.
  static var openPanelTypes: [UTType] { [.audio, .movie] }
}
