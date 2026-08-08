import Foundation
import IOKit

/// IORegistry 遍历与属性读取的封装。GPU 与磁盘统计都走这里。
enum IORegistry {

    /// 匹配某个类的所有服务节点，把整棵属性字典交给 `body`。
    /// 用 `IOServiceMatching` 匹配类名（含子类）。
    static func forEachService(matching className: String,
                               options: IOOptionBits = 0,
                               _ body: (io_registry_entry_t, [String: Any]) -> Void) {
        guard let matching = IOServiceMatching(className) else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, options) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            body(service, dict)
        }
    }

    /// 读取单个属性，可选沿父节点向上递归查找（磁盘的容量信息常挂在父节点上）。
    static func property(_ entry: io_registry_entry_t, _ key: String, searchParents: Bool = false) -> Any? {
        let options = searchParents ? IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents) : 0
        // 返回值是 CFTypeRef，Swift 已经帮我们接管了 +1 引用
        return IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, key as CFString, kCFAllocatorDefault, options
        )
    }

    /// 节点在 IORegistry 里的名字。
    static func name(_ entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
        return String(cBuffer: buffer)
    }
}

extension Dictionary where Key == String, Value == Any {
    /// 从 IORegistry 属性字典里取数字（CFNumber 会桥接成 NSNumber）。
    func number(_ key: String) -> Double? {
        (self[key] as? NSNumber)?.doubleValue
    }

    func integer(_ key: String) -> UInt64? {
        guard let n = self[key] as? NSNumber else { return nil }
        return n.uint64Value
    }

    /// IORegistry 里的字符串常以 `Data`（带结尾 NUL）形式出现。
    func text(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let d = self[key] as? Data {
            return String(decoding: d.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return nil
    }
}
