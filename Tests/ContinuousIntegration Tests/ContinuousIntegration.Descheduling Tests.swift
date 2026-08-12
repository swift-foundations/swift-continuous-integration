import ContinuousIntegration
import Testing

/// The two capabilities a policy layer composes over: narrowing a plan
/// when nothing in the diff can affect package work, and withdrawing a
/// leg with a recorded reason.
///
/// The reason vocabulary is open by design, so these controls use a
/// spelling of their own rather than any one policy's — what is owned
/// here is the mechanism, not the policy.
@Suite
struct ContinuousIntegrationDeschedulingTests {
    static let testReason = ContinuousIntegration.Plan.Descheduled.Reason(
        rawValue: "test-reason")

    /// A descheduled leg leaves `legs` and appears in `descheduled` with
    /// its reason — the third audited state, distinct from scheduled and
    /// from absent.
    @Test func deschedulingWithdrawsAScheduledLegWithItsReason() throws {
        let plan = try ContinuousIntegration.Plan(
            forcedTier: "full", ref: "refs/heads/x", event: "push",
            lintBundle: "standards",
            descheduling: [.init(leg: .init("linux-nightly"), reason: Self.testReason)])
        #expect(!plan.legs.map(\.id).contains("linux-nightly"))
        #expect(
            plan.descheduled == [.init(leg: .init("linux-nightly"), reason: Self.testReason)])
        // Withdrawal is surgical: the gating build leg is untouched.
        #expect(plan.gating.map(\.id).contains("linux-release"))
    }

    /// A leg this run would not have scheduled is absent, not
    /// descheduled: the record may only name legs the plan actually held,
    /// or the audit downstream would demand a skip from a job that never
    /// existed.
    @Test func deschedulingAnUnscheduledLegRecordsNothing() throws {
        let plan = try ContinuousIntegration.Plan(
            ref: "refs/heads/x", event: "push", lintBundle: "standards",
            descheduling: [.init(leg: .init("linux-nightly"), reason: Self.testReason)])
        #expect(plan.descheduled.isEmpty)
        #expect(
            plan.legs.map(\.id) == [
                "format", "lint", "swift-linter", "linux-release", "linux-6-4",
            ])
    }

    /// A diff that cannot affect package work drops every build leg, and
    /// the "something must have built" guard stands down with it — that
    /// combination is the one legitimate way to plan no build at all.
    @Test func nonPackageContentNarrowsThePlanAndStandsTheBuildGuardDown() throws {
        let plan = try ContinuousIntegration.Plan(
            forcedTier: "full", ref: "refs/heads/x", event: "push",
            lintBundle: "standards", packageContentChanged: false)
        #expect(!plan.packageContentChanged)
        #expect(!plan.legs.contains { $0.buildLeg })
        #expect(!plan.legs.map(\.id).contains("linux-6-4"))
        #expect(plan.legs.map(\.id).contains("format"))
    }

    /// A manual run is a request to build, so it forces package content
    /// true however the caller classified the diff.
    @Test func manualDispatchForcesPackageContent() throws {
        let plan = try ContinuousIntegration.Plan(
            ref: "refs/heads/x", event: "workflow_dispatch", lintBundle: "standards",
            packageContentChanged: false)
        #expect(plan.packageContentChanged)
        #expect(plan.legs.contains { $0.buildLeg })
    }

    /// The aggregate audits the third state rather than trusting it: a
    /// descheduled leg must have skipped, and may never be gating.
    @Test func aggregateAuditsTheDescheduledRecord() {
        let ran = ContinuousIntegration.AggregateVerdict(
            planResult: "success",
            results: ["linux-release": "success", "linux-nightly": "success"],
            gating: ["linux-release"],
            subjectRepository: "o/r",
            subjectSha: "0".repeated(40),
            tier: "full",
            requireFullTier: false,
            descheduled: ["linux-nightly"])
        #expect(!ran.pass)
        #expect(
            ran.findings.contains(
                .descheduledLegRan(job: "linux-nightly", result: "success")))

        let gating = ContinuousIntegration.AggregateVerdict(
            planResult: "success",
            results: ["linux-release": "skipped"],
            gating: ["linux-release"],
            subjectRepository: "o/r",
            subjectSha: "0".repeated(40),
            tier: "full",
            requireFullTier: false,
            descheduled: ["linux-release"])
        #expect(!gating.pass)
        #expect(gating.findings.contains(.descheduledGatingLeg(job: "linux-release")))
    }

    /// Building nothing is a defect only when the plan said package
    /// content changed.
    @Test func nothingBuiltIsAcceptedOnlyForNonPackageContent() {
        let verdict = ContinuousIntegration.AggregateVerdict(
            planResult: "success",
            results: ["format": "success"],
            gating: ["format"],
            subjectRepository: "o/r",
            subjectSha: "0".repeated(40),
            tier: "build",
            requireFullTier: false,
            packageContentChanged: false)
        #expect(verdict.pass)
        #expect(verdict.built.isEmpty)
    }
}

extension String {
    fileprivate func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
