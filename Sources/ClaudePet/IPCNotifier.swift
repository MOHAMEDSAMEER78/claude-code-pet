import Foundation
import Darwin

final class IPCNotifier {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let socketURL: URL

    init(socketName: String) {
        socketURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/pet/\(socketName)", isDirectory: false)
    }

    func start(onPing: @escaping () -> Void) {
        try? FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: socketURL)

        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLength else {
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { rawPath in
            rawPath.withMemoryRebound(to: CChar.self, capacity: maxLength) { cPath in
                _ = path.withCString { strncpy(cPath, $0, maxLength - 1) }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            return
        }

        fileDescriptor = fd
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.main)
        readSource.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 64)
            _ = recv(fd, &buffer, buffer.count, 0)
            onPing()
        }
        readSource.setCancelHandler { close(fd) }
        readSource.resume()
        source = readSource
    }

    deinit {
        source?.cancel()
        try? FileManager.default.removeItem(at: socketURL)
    }
}
