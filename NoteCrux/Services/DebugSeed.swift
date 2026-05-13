#if DEBUG
import Foundation
import SwiftData

enum DebugSeed {
    private static let seedKey = "nc_demoSeeded"

    @MainActor
    static func seedIfRequested(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "nc_seedDemo") else { return }
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }

        let calendar = Calendar.current
        let now = Date()

        let m1 = Meeting(
            title: "Q2 Product Strategy Sync",
            createdAt: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
            duration: 42 * 60,
            tags: ["Product", "Leadership"],
            transcript: "Alex: Let's talk Q2. We need to prioritize the onboarding redesign before the Launch event…",
            importance: .important,
            summary: "Product leadership aligned on Q2 priorities: onboarding redesign ships before Launch, paywall A/B starts next sprint, and team hiring pauses for two weeks to stabilize current roadmap.",
            bulletSummary: [
                "Onboarding redesign is Q2 top priority — ships before Launch",
                "Paywall A/B test starts next sprint",
                "Hiring freeze for 2 weeks to stabilize roadmap",
                "Churn investigation handed to Data team"
            ],
            highlights: [
                "If onboarding drops by 5%, we revisit pricing immediately.",
                "The AI meeting assistant is our strongest differentiator."
            ],
            importantLines: [
                "We will not ship new paid features until churn is under 4%."
            ],
            keyPoints: [
                "Q2 theme: retention over acquisition",
                "Launch event timing is fixed — May 22"
            ],
            decisions: [
                "Pause new hires until May 1",
                "Approve paywall A/B experiment"
            ],
            risks: [
                "If onboarding slips, Launch event demo is at risk"
            ]
        )

        let t1 = MeetingActionItem(
            title: "Ship onboarding redesign v2",
            detail: "Blocked on design handoff from Maya. Target merge by Apr 28.",
            owner: "Daniel",
            deadline: calendar.date(byAdding: .day, value: 4, to: now),
            priority: .high,
            confidence: .high,
            sourceQuote: "Daniel will drive onboarding redesign to ship before Launch.",
            meeting: m1
        )
        let t2 = MeetingActionItem(
            title: "Draft paywall A/B test plan",
            detail: "Two variants: yearly-first vs monthly-first. Success metric: D7 conversion.",
            owner: "Priya",
            deadline: calendar.date(byAdding: .day, value: 2, to: now),
            priority: .high,
            confidence: .high,
            sourceQuote: "Priya owns the paywall experiment spec.",
            meeting: m1
        )
        let t3 = MeetingActionItem(
            title: "Pull churn cohort data for last 90 days",
            owner: "Jordan",
            deadline: calendar.date(byAdding: .day, value: 1, to: now),
            priority: .medium,
            confidence: .high,
            sourceQuote: "Jordan will pull the churn cohort breakdown.",
            meeting: m1
        )
        m1.actionItems = [t1, t2, t3]

        let m2 = Meeting(
            title: "1:1 with Maya — Design Review",
            createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
            duration: 28 * 60,
            tags: ["1:1", "Design"],
            summary: "Weekly 1:1 focused on onboarding visual language and hiring a mid-level product designer.",
            bulletSummary: [
                "New onboarding visual language approved",
                "Mid-level product designer role opens next week"
            ],
            highlights: [
                "Maya wants the onboarding to feel 'calm, not tutorial-heavy'."
            ],
            keyPoints: ["Design system v3 is 70% complete"],
            decisions: ["Open designer role on April 24"]
        )
        let t4 = MeetingActionItem(
            title: "Post designer JD to Notion careers",
            owner: "Maya",
            deadline: calendar.date(byAdding: .day, value: 5, to: now),
            priority: .medium,
            confidence: .high,
            meeting: m2
        )
        m2.actionItems = [t4]

        let m3 = Meeting(
            title: "Customer call — Acme Corp",
            createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
            duration: 35 * 60,
            tags: ["Sales", "Customer"],
            importance: .critical,
            summary: "Discovery call with Acme's Head of Ops. They record 30+ internal meetings per week and are frustrated by Otter's cloud-only model. Strong fit for our privacy-first positioning.",
            bulletSummary: [
                "Acme records 30+ meetings/week internally",
                "Current pain: cloud storage, compliance team is blocking Otter",
                "Pilot interest confirmed for 50 seats"
            ],
            highlights: [
                "'If your transcription is truly on-device we can ship you a PO next week.'"
            ],
            importantLines: [
                "Compliance approval is a hard gate — need SOC 2 roadmap."
            ],
            decisions: ["Send pilot agreement by Friday"],
            risks: ["Compliance team may require SOC 2 Type II report"]
        )
        let t5 = MeetingActionItem(
            title: "Send pilot agreement to Acme",
            owner: "Alex",
            deadline: calendar.date(byAdding: .day, value: 2, to: now),
            priority: .high,
            confidence: .high,
            meeting: m3
        )
        m3.actionItems = [t5]

        context.insert(m1)
        context.insert(m2)
        context.insert(m3)
        try? context.save()

        UserDefaults.standard.set(true, forKey: seedKey)
    }

    @MainActor
    static func resetSeedFlag() {
        UserDefaults.standard.removeObject(forKey: seedKey)
    }
}
#endif
