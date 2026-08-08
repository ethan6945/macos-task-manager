import SwiftUI

/// 对应 Win11 的「用户」页：登录会话 + 按用户聚合的资源占用，可展开看进程。
struct UsersView: View {
    @Environment(SystemMonitor.self) private var monitor
    @State private var expanded: Set<String> = []

    private struct UserBucket: Identifiable {
        var id: String { user }
        var user: String
        var uid: uid_t
        var cpu: Double
        var memory: UInt64
        var processes: [ProcessRow]
        var sessions: [LoginSession]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(buckets) { bucket in
                    VStack(alignment: .leading, spacing: 8) {
                        header(bucket)
                        if expanded.contains(bucket.user) {
                            processList(bucket)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }

                Text(L("会话信息来自 utmpx；资源占用是把该 uid 名下的所有进程加总得到的。"))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .onAppear {
            if monitor.sessions.isEmpty { monitor.refreshSlowData() }
            if expanded.isEmpty, let first = buckets.first { expanded.insert(first.user) }
        }
    }

    private func header(_ bucket: UserBucket) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bucket.sessions.isEmpty ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                .font(.title)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.user).font(.headline)
                Text(sessionSummary(bucket)).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            MetricGrid(metrics: [
                Metric("CPU", Fmt.percent(bucket.cpu)),
                Metric(L("内存"), Fmt.bytes(bucket.memory)),
                Metric(L("进程"), "\(bucket.processes.count)")
            ], columns: 3)
            .frame(width: 260)

            Button {
                if expanded.contains(bucket.user) { expanded.remove(bucket.user) }
                else { expanded.insert(bucket.user) }
            } label: {
                Image(systemName: expanded.contains(bucket.user) ? "chevron.down" : "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private func processList(_ bucket: UserBucket) -> some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(bucket.processes.prefix(50)) { row in
                HStack(spacing: 8) {
                    ProcessIcon(bundlePath: row.bundlePath, executablePath: row.path)
                    Text(row.name).lineLimit(1)
                    Spacer()
                    Text(verbatim: String(row.pid)).font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    Text(Fmt.percent(row.cpuPercent)).frame(width: 62, alignment: .trailing).monospacedDigit()
                    Text(Fmt.bytes(row.memory)).frame(width: 80, alignment: .trailing).monospacedDigit()
                }
                .font(.callout)
                .padding(.vertical, 3)
            }
            if bucket.processes.count > 50 {
                Text(L("……还有 %d 个进程", bucket.processes.count - 50))
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func sessionSummary(_ bucket: UserBucket) -> String {
        guard !bucket.sessions.isEmpty else { return L("无交互式登录会话（后台/系统用户）") }
        return bucket.sessions
            .map { L("%@ · 登录于 %@", $0.kind, Fmt.time($0.loginTime)) }
            .joined(separator: "   |   ")
    }

    private var buckets: [UserBucket] {
        var grouped: [String: UserBucket] = [:]
        for row in monitor.processes {
            var bucket = grouped[row.user] ?? UserBucket(
                user: row.user, uid: row.uid, cpu: 0, memory: 0, processes: [], sessions: []
            )
            bucket.cpu += row.cpuPercent
            bucket.memory += row.memory
            bucket.processes.append(row)
            grouped[row.user] = bucket
        }
        for session in monitor.sessions {
            grouped[session.user]?.sessions.append(session)
        }
        return grouped.values
            .map { bucket in
                var copy = bucket
                copy.processes.sort { $0.cpuPercent > $1.cpuPercent }
                return copy
            }
            .sorted { lhs, rhs in
                if lhs.sessions.isEmpty != rhs.sessions.isEmpty { return !lhs.sessions.isEmpty }
                return lhs.cpu > rhs.cpu
            }
    }
}
