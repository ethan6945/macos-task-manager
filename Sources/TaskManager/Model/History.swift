import Foundation

/// 定长环形缓冲，给图表存历史采样点。旧点自动挤出。
struct History: Sendable {
    private(set) var values: [Double]
    let capacity: Int

    init(capacity: Int = 120) {
        self.capacity = capacity
        self.values = []
        self.values.reserveCapacity(capacity)
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    mutating func reset() { values.removeAll(keepingCapacity: true) }

    var latest: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
    var isEmpty: Bool { values.isEmpty }

    /// 把历史点右对齐成定长数组（左侧用 0 补齐），画图时坐标才不会随点数漂移。
    func padded(to count: Int) -> [Double] {
        if values.count >= count { return Array(values.suffix(count)) }
        return Array(repeating: 0, count: count - values.count) + values
    }
}
