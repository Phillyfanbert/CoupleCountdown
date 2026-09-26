// BackgroundRefreshScheduler.swift — BGAppRefreshTask scheduling + firing-frequency instrumentation (DESIGN.md §5.2 #3, §10)

import Foundation
import BackgroundTasks
import WidgetKit
import FirebaseAuth
import CoupleCountdownKit

/// Schedules the opportunistic background refresh from DESIGN.md §5.2 #3
/// and logs every actual firing so real-world frequency can be measured
/// against §10's pre-committed threshold: drop this mechanism from v1 if
/// real data shows meaningfully fewer than ~2 firings/day on average.
final class BackgroundRefreshScheduler {
    static let taskIdentifier = "com.couplecountdown.refresh"

    private let defaults: UserDefaults
    private let firingLogKey = "backgroundRefreshFiringLog"
    private let onRefresh: () async -> Void

    init(defaults: UserDefaults = .standard, onRefresh: @escaping () async -> Void) {
        self.defaults = defaults
        self.onRefresh = onRefresh
    }

    /// Call once at app launch, before `scheduleNext()`.
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else { return }
            self.handle(refreshTask)
        }
    }

    func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        logFiring()
        scheduleNext() // always reschedule, whether this run succeeds or not

        let work = Task {
            await onRefresh()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// What a background refresh does: the latest state of this device's
    /// pairing into the widget's cache, then a widget reload — a launch fetch
    /// without the app on screen.
    static func refreshWidgetData() async {
        guard Auth.auth().currentUser != nil,
              let coupleId = UserDefaults(suiteName: SharedIdentifiers.appGroup)?.string(forKey: "coupleId"),
              !coupleId.isEmpty,
              let state = try? await FirestoreService().fetchCouple(coupleId: coupleId)
        else { return }
        AppGroupCache(suiteName: SharedIdentifiers.appGroup).write(state)
        WidgetCenter.shared.reloadTimelines(ofKind: "CountdownWidget")
    }

    private func logFiring() {
        var log = defaults.array(forKey: firingLogKey) as? [Double] ?? []
        log.append(Date().timeIntervalSince1970)
        defaults.set(log, forKey: firingLogKey)
    }

    /// Timestamps of every observed firing — read this to compute the
    /// real-world frequency for §10's decision.
    func firingHistory() -> [Date] {
        let log = defaults.array(forKey: firingLogKey) as? [Double] ?? []
        return log.map(Date.init(timeIntervalSince1970:))
    }
}
