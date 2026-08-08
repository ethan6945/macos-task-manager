import Foundation

/// 极简互斥包装。（`Synchronization.Mutex` 要 macOS 15，这里保持 macOS 14 兼容。）
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
