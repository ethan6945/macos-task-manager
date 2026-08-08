import Foundation

extension String {
    /// 从 C 字符串缓冲区构造，截断到第一个 NUL。
    init(cBuffer: [CChar]) {
        let bytes = cBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }

    /// 从定长 C 字符数组（Swift 里会导入成元组）构造。
    init<T>(cTuple: T) {
        var value = cTuple
        self = withUnsafeBytes(of: &value) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
