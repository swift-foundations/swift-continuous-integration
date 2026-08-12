extension ContinuousIntegration {
    /// The plan — tier classification, platform-support validation and
    /// filtering, leg selection, and gating derivation. Semantics mirror
    /// the swift-ci.yml plan job coordinate-for-coordinate (F4;
    /// swift-institute/.github#368); the shell is the incumbent until the
    /// F12 producer switch.
    public struct Plan: Sendable, Equatable {
        public enum Error: Swift.Error, Equatable {
            case retiredLintTier
            case unknownForcedTier(String)
            case invalidPlatformFamily(String)
            case duplicatePlatformFamily(String)
            case trailingEmptyPlatformFamily(String)
            case noRecognizedPlatformFamily(String)
            case invalidLintBundle(String)
            case noGatingBuildLeg(tier: Tier, platformSupport: String)
        }

        public struct Subject: Sendable, Equatable {
            public let repository: String
            public let ref: String
            public let sha: String

            public init(repository: String, ref: String, sha: String) {
                self.repository = repository
                self.ref = ref
                self.sha = sha
            }
        }

        /// One leg the plan removed from ``legs`` with a stated reason —
        /// the third audited state beside scheduled and absent.
        /// Descheduling is typed, never silent: the aggregate receives
        /// this list and verifies each entry actually skipped, so a
        /// descheduled leg stays distinguishable from a platform-filter
        /// drop or a plan defect.
        ///
        /// The reason is an opaque token rather than an enumeration: what
        /// makes a leg unschedulable is policy, and policy is owned a
        /// layer up. This owner records the reason and audits the
        /// consequence without interpreting either.
        public struct Descheduled: Sendable, Equatable {
            public let leg: Leg
            public let reason: String

            public init(leg: Leg, reason: String) {
                self.leg = leg
                self.reason = reason
            }
        }

        public let tier: Tier
        public let legs: [Leg]
        public let descheduled: [Descheduled]
        public let packageContentChanged: Bool
        public var gating: [Leg] { legs.filter(\.gating) }

        static let fullTierLegs = [
            "format", "lint", "swift-linter", "linux-release",
            "macos-release", "windows-release", "linux-nightly", "linux-6-4",
            "apple-simulator-build", "lint-yaml", "lint-broken-symlink",
            "lint-license-header", "lint-test-support-spine",
            "advisory-summary",
        ]

        static let primitivesAdvisoryLegs = [
            "embedded", "embedded-wasm-sdk", "android-build",
            "static-linux-musl-build",
        ]

        /// Classifies and plans one run. Parameter semantics equal the
        /// plan job's environment: `forcedTier` = the tier input;
        /// `ref` = GITHUB_REF; `headMessage` = the push head commit
        /// message (empty on PR events); `event` = the event name;
        /// `platformSupport` = the comma-separated family list;
        /// `lintBundle` = primitives|standards|institute.
        /// - Parameter packageContentChanged: false when the event diff
        ///   selected no package build work. Build legs are then dropped
        ///   and the no-gating-build-leg guard stands down, because
        ///   building nothing is the planned outcome rather than a green
        ///   over nothing.
        /// - Parameter deschedule: leg ids the caller's policy has ruled
        ///   unschedulable for this run, each with its reason. Applied
        ///   after the platform filter, so a record names only a leg this
        ///   run would otherwise have scheduled; a leg the tier or
        ///   platform filter already excluded is absent, not descheduled.
        public init(
            forcedTier: String = "",
            ref: String,
            headMessage: String = "",
            event: String,
            platformSupport: String = "",
            lintBundle: String,
            packageContentChanged: Bool = true,
            deschedule: [String: String] = [:]
        ) throws(Error) {
            guard ["primitives", "standards", "institute"].contains(lintBundle) else {
                throw .invalidLintBundle(lintBundle)
            }
            let families = try Self.validatedFamilies(platformSupport)

            var tier: Tier?
            switch forcedTier {
            case "": tier = nil
            case "lint": throw .retiredLintTier
            case "build": tier = .build
            case "full": tier = .full
            default: throw .unknownForcedTier(forcedTier)
            }
            if tier == nil, ref.hasPrefix("refs/tags/") { tier = .full }
            if tier == nil {
                if headMessage.contains("[ci full]") { tier = .full }
                else if headMessage.contains("[ci build]") { tier = .build }
            }
            if tier == nil, event == "workflow_dispatch" { tier = .full }
            if ref == "refs/heads/main" { tier = .full }
            let selected = tier ?? .build
            self.tier = selected
            // An explicit dispatch is a deliberate request to verify, so it
            // never inherits a no-work classification from the event diff.
            let packageContentChanged = packageContentChanged || event == "workflow_dispatch"
            self.packageContentChanged = packageContentChanged

            var legIds: [String]
            switch selected {
            case .build:
                let primary: String
                if families.isEmpty || families.contains(.linux) {
                    primary = "linux-release"
                } else if families.contains(.windows) {
                    primary = "windows-release"
                } else if families.contains(.apple) {
                    primary = "macos-release"
                } else {
                    throw .noRecognizedPlatformFamily(platformSupport)
                }
                legIds = ["format", "lint", "swift-linter", primary, "linux-6-4"]
            case .full:
                legIds = Self.fullTierLegs
            }
            if lintBundle == "primitives" {
                legIds += Self.primitivesAdvisoryLegs
            }
            if !packageContentChanged {
                legIds.removeAll { Leg($0).buildLeg || Self.packageWorkLegs.contains($0) }
            }
            if !families.isEmpty {
                legIds = legIds.filter { id in
                    guard let family = Leg(id).family else { return true }
                    return families.contains(family)
                }
            }
            var descheduled: [Descheduled] = []
            for id in legIds where deschedule[id] != nil {
                descheduled.append(.init(leg: Leg(id), reason: deschedule[id]!))
            }
            legIds.removeAll { deschedule[$0] != nil }
            self.descheduled = descheduled
            let legs = legIds.map(Leg.init)
            guard !packageContentChanged || legs.contains(where: { $0.gating && $0.buildLeg })
            else {
                throw .noGatingBuildLeg(tier: selected, platformSupport: platformSupport)
            }
            self.legs = legs
        }

        /// Legs that compile or cross-compile the package, beyond the
        /// release build legs ``Leg/buildLeg`` names. A run that selected
        /// no package work schedules none of them.
        static let packageWorkLegs: Set<String> = [
            "linux-6-4", "linux-nightly", "apple-simulator-build", "embedded",
            "embedded-wasm-sdk", "android-build", "static-linux-musl-build",
        ]

        static func validatedFamilies(
            _ platformSupport: String
        ) throws(Error) -> Set<Leg.Family> {
            guard !platformSupport.isEmpty else { return [] }
            if platformSupport.hasSuffix(",") {
                // The shell reports the trailing-empty case distinctly.
                // (Its per-token loop sees the empty token first; the
                // dedicated case exists for the diagnostic, matched here.)
                if platformSupport.dropLast().split(
                    separator: ",", omittingEmptySubsequences: false
                ).allSatisfy({ ["apple", "linux", "windows"].contains(String($0)) }) {
                    throw .trailingEmptyPlatformFamily(platformSupport)
                }
            }
            var seen: Set<Leg.Family> = []
            for token in platformSupport.split(
                separator: ",", omittingEmptySubsequences: false
            ) {
                guard let family = Leg.Family(rawValue: String(token)) else {
                    throw .invalidPlatformFamily(String(token))
                }
                guard seen.insert(family).inserted else {
                    throw .duplicatePlatformFamily(String(token))
                }
            }
            return seen
        }
    }
}
