import AppKit
import SwiftUI

/// 进程表格的排序键。
///
/// 不用 `KeyPathComparator`：它走存在类型，实测按名称排 690 行要 20 ms。
enum ProcessSortKey: String, CaseIterable, Sendable {
    case name, cpu, memory, disk, threads, ports, energy, pid, ppid, user
    case nice, pageIns, contextSwitches, startTime, path, status, architecture, cpuTime

    /// 数值列默认降序（大的在前），文本列默认升序。
    var defaultAscending: Bool {
        switch self {
        case .name, .user, .path, .pid, .ppid, .startTime, .status, .architecture: true
        default: false
        }
    }
}

struct ProcessSort: Equatable, Sendable {
    var key: ProcessSortKey = .cpu
    var ascending: Bool = false

    /// 点同一列切换升降序，点新列用该列的默认方向。
    mutating func toggle(_ key: ProcessSortKey) {
        if self.key == key { ascending.toggle() }
        else { self = ProcessSort(key: key, ascending: key.defaultAscending) }
    }
}

/// 一列的定义。
struct ProcessColumn {
    var key: ProcessSortKey
    var title: String
    var width: CGFloat
    var minWidth: CGFloat = 40
    var alignment: NSTextAlignment = .left
    var showsIcon: Bool = false
    var text: (ProcessRow) -> String
    /// 返回 true 表示这一格用次要颜色显示
    var dimmed: (ProcessRow) -> Bool = { _ in true }
}

/// NSTableView 支持的进程表格。
///
/// SwiftUI 的 `Table` 每次替换数据都有约 15% CPU 的固定开销（实测与行数无关），
/// 700 行、每 2 秒一刷的场景扛不住；NSTableView 只为可见行创建单元格，
/// 同样的负载下开销可以忽略。
struct ProcessTable: NSViewRepresentable {

    var groups: GroupedProcesses
    /// 数据版本。只有它变了才真正 reloadData —— updateNSView 会被 SwiftUI 调用得比采样频繁得多。
    var key: ProcessTableKey
    var columns: [ProcessColumn]
    var grouped: Bool
    @Binding var selection: Set<pid_t>
    @Binding var sort: ProcessSort
    var menuBuilder: (Set<pid_t>) -> NSMenu?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.rowSizeStyle = .custom
        table.rowHeight = 20
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAutomaticRowHeights = false
        table.floatsGroupRows = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.menu = {
            let menu = NSMenu()
            menu.delegate = context.coordinator
            return menu
        }()

        for column in columns {
            let item = NSTableColumn(identifier: .init(column.key.rawValue))
            item.title = column.title
            item.width = column.width
            item.minWidth = column.minWidth
            item.maxWidth = 800
            item.sortDescriptorPrototype = NSSortDescriptor(key: column.key.rawValue, ascending: true)
            if column.alignment == .right { item.headerCell.alignment = .right }
            table.addTableColumn(item)
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false

        context.coordinator.table = table
        context.coordinator.apply(groups: groups, key: key, grouped: grouped, columns: columns)
        context.coordinator.applySortIndicator(sort)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // 语言切换后列标题要跟着变
        if let table = scroll.documentView as? NSTableView {
            for column in columns {
                table.tableColumns.first { $0.identifier.rawValue == column.key.rawValue }?.title = column.title
            }
        }
        context.coordinator.apply(groups: groups, key: key, grouped: grouped, columns: columns)
        context.coordinator.applySortIndicator(sort)
        context.coordinator.applySelection(selection)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        enum Item {
            case header(String)
            case process(ProcessRow)
        }

        var parent: ProcessTable
        weak var table: NSTableView?
        private(set) var items: [Item] = []
        private var columns: [ProcessColumn] = []
        private var isApplyingSelection = false
        private var lastSort: ProcessSort?
        private var lastKey: ProcessTableKey?

        init(_ parent: ProcessTable) {
            self.parent = parent
            super.init()
        }

        func apply(groups: GroupedProcesses, key: ProcessTableKey, grouped: Bool, columns: [ProcessColumn]) {
            guard lastKey != key || items.isEmpty else { return }
            let isFirstLoad = items.isEmpty
            lastKey = key
            self.columns = columns
            var items: [Item] = []
            if grouped {
                items.reserveCapacity(groups.apps.count + groups.background.count + 2)
                items.append(.header(L("应用（%d）", groups.apps.count)))
                items.append(contentsOf: groups.apps.map(Item.process))
                items.append(.header(L("后台进程（%d）", groups.background.count)))
                items.append(contentsOf: groups.background.map(Item.process))
            } else {
                items = groups.all.map(Item.process)
            }
            let previousHeaders = headerPositions
            let previousCount = self.items.count
            self.items = items

            guard let table else { return }
            if isFirstLoad {
                table.reloadData()
                return
            }
            // reloadData 会 purge 掉全部 703 个 row view 再重建（实测这一项就吃掉几十 % CPU）。
            // 行数与分组位置没变时，只重载可见的那二十来行即可。
            // 选中要屏蔽回调：重载会清空选中并回调 selectionDidChange，
            // 那次回调会把空选中写回 SwiftUI 状态，触发又一轮刷新。
            let selectedPIDs = currentSelectionPIDs()
            isApplyingSelection = true

            if previousHeaders != headerPositions {
                // 分组标题换行号了：某些行的「是不是分组行」变了，而 row view 的类型
                // 是创建时定下来的，只重载单元格会留下空白行，必须整表重建。
                // 好在这只在应用数量变化时才发生，很少见。
                table.reloadData()
            } else {
                if previousCount != items.count {
                    table.noteNumberOfRowsChanged()
                }
                let visible = table.rows(in: table.visibleRect)
                if visible.length > 0 {
                    table.reloadData(
                        forRowIndexes: IndexSet(integersIn: visible.location..<min(items.count, visible.location + visible.length)),
                        columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)
                    )
                }
            }
            restore(selectedPIDs)
            isApplyingSelection = false
        }

        /// 分组标题所在的行号。它变了说明表格结构变了，必须整表重载。
        private var headerPositions: [Int] {
            items.enumerated().compactMap { index, item in
                if case .header = item { return index }
                return nil
            }
        }

        func applySortIndicator(_ sort: ProcessSort) {
            guard let table, lastSort != sort else { return }
            lastSort = sort
            for column in table.tableColumns {
                table.setIndicatorImage(nil, in: column)
            }
            if let column = table.tableColumns.first(where: { $0.identifier.rawValue == sort.key.rawValue }) {
                table.setIndicatorImage(
                    NSImage(named: sort.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"),
                    in: column
                )
                table.highlightedTableColumn = column
            }
        }

        func applySelection(_ pids: Set<pid_t>) {
            guard currentSelectionPIDs() != pids else { return }
            restore(pids)
        }

        private func currentSelectionPIDs() -> Set<pid_t> {
            guard let table else { return [] }
            var result: Set<pid_t> = []
            for index in table.selectedRowIndexes {
                if case .process(let row) = items[index] { result.insert(row.pid) }
            }
            return result
        }

        private func restore(_ pids: Set<pid_t>) {
            guard let table else { return }
            let wasApplying = isApplyingSelection
            isApplyingSelection = true
            defer { isApplyingSelection = wasApplying }

            guard !pids.isEmpty else {
                if !table.selectedRowIndexes.isEmpty { table.deselectAll(nil) }
                return
            }
            var indexes = IndexSet()
            for (index, item) in items.enumerated() {
                if case .process(let row) = item, pids.contains(row.pid) { indexes.insert(index) }
            }
            guard indexes != table.selectedRowIndexes else { return }
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = items[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            !self.tableView(tableView, isGroupRow: row)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch items[row] {
            case .header(let title):
                let cell = reusableCell(tableView, identifier: "header", withIcon: false)
                cell.textField?.stringValue = title
                cell.textField?.alignment = .left
                cell.textField?.font = .systemFont(ofSize: 11, weight: .semibold)
                cell.textField?.textColor = .secondaryLabelColor
                cell.imageView?.isHidden = true
                return cell

            case .process(let process):
                guard let tableColumn,
                      let column = columns.first(where: { $0.key.rawValue == tableColumn.identifier.rawValue })
                else { return nil }

                let cell = reusableCell(tableView, identifier: tableColumn.identifier.rawValue, withIcon: column.showsIcon)
                cell.textField?.stringValue = column.text(process)
                cell.textField?.alignment = column.alignment
                cell.textField?.font = column.alignment == .right
                    ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                    : .systemFont(ofSize: 11)
                cell.textField?.textColor = column.dimmed(process) ? .secondaryLabelColor : .labelColor
                if column.showsIcon {
                    cell.imageView?.isHidden = false
                    cell.imageView?.image = IconCache.shared.icon(
                        bundlePath: process.bundlePath, executablePath: process.path
                    )
                }
                return cell
            }
        }

        /// NSTableView 的单元格复用 —— 这是它比 SwiftUI Table 快的关键。
        private func reusableCell(_ tableView: NSTableView, identifier: String, withIcon: Bool) -> NSTableCellView {
            let id = NSUserInterfaceItemIdentifier(withIcon ? "\(identifier).icon" : identifier)
            if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
                return existing
            }
            let cell = ProcessCellView(withIcon: withIcon)
            cell.identifier = id
            return cell
        }

        // MARK: Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            // 直接写回 SwiftUI 状态会同步触发 updateNSView，构成对 NSTableView 的重入调用
            // （AppKit 会打警告，将来会变成断言）。推迟到下一个 runloop。
            let pids = currentSelectionPIDs()
            Task { @MainActor [weak self] in
                self?.parent.selection = pids
            }
        }

        func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
            guard let key = ProcessSortKey(rawValue: tableColumn.identifier.rawValue) else { return }
            var sort = parent.sort
            sort.toggle(key)
            parent.sort = sort
        }

        // MARK: 右键菜单

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            // 右键点在未选中的行上时，先把该行选中（与 Finder 行为一致）
            let clicked = table.clickedRow
            if clicked >= 0, case .process(let row) = items[clicked], !currentSelectionPIDs().contains(row.pid) {
                restore([row.pid])
                parent.selection = [row.pid]
            }
            guard let built = parent.menuBuilder(currentSelectionPIDs()) else { return }
            for item in built.items {
                built.removeItem(item)
                menu.addItem(item)
            }
        }
    }
}

/// 表格单元格。**刻意不用 Auto Layout**：几百个单元格各带几条约束会让
/// `-[NSWindow layoutIfNeeded]` 成为主线程最大的开销（实测占了三分之一的忙时间）。
final class ProcessCellView: NSTableCellView {
    private let hasIcon: Bool

    init(withIcon: Bool) {
        self.hasIcon = withIcon
        super.init(frame: .zero)

        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell?.truncatesLastVisibleLine = true
        addSubview(text)
        textField = text

        if withIcon {
            let image = NSImageView()
            image.imageScaling = .scaleProportionallyDown
            addSubview(image)
            imageView = image
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let height = bounds.height
        let textHeight: CGFloat = 15
        let y = ((height - textHeight) / 2).rounded()

        if hasIcon {
            imageView?.frame = NSRect(x: 2, y: ((height - 15) / 2).rounded(), width: 15, height: 15)
            textField?.frame = NSRect(x: 22, y: y, width: max(0, bounds.width - 26), height: textHeight)
        } else {
            textField?.frame = NSRect(x: 4, y: y, width: max(0, bounds.width - 8), height: textHeight)
        }
    }
}

/// 把 SwiftUI 的按钮描述转换成 NSMenu，供上面的表格使用。
struct MenuAction {
    var title: String
    var handler: () -> Void
    var isSeparator: Bool = false

    static var separator: MenuAction { MenuAction(title: "", handler: {}, isSeparator: true) }
}

@MainActor
func buildMenu(_ actions: [MenuAction]) -> NSMenu {
    let menu = NSMenu()
    for action in actions {
        if action.isSeparator {
            menu.addItem(.separator())
            continue
        }
        let item = NSMenuItem(title: action.title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
        let target = MenuTarget(action.handler)
        item.target = target
        item.representedObject = target      // 让 target 活到菜单消失
        menu.addItem(item)
    }
    return menu
}

@MainActor
final class MenuTarget: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}
