import Foundation

/// ~/.hyper-typer/hyper-typer.log 에 한 줄 추가하는 공용 디버그 로거.
func htLog(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hyper-typer/hyper-typer.log")
    guard let data = "\(Date()) \(msg)\n".data(using: .utf8) else { return }
    if let fh = try? FileHandle(forWritingTo: url) {
        defer { try? fh.close() }
        fh.seekToEndOfFile()
        fh.write(data)
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}
