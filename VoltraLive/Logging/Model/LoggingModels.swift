// LoggingModels.swift
// v0.2 SwiftData schema for the workout logging layer.
//
// Lives ALONGSIDE PastSession/PastSet (v0.1.x dashboard schema). The dashboard
// continues to read PastSession; the logging UI uses these new models. Both are
// registered in the same ModelContainer so cross-queries work and CloudKit
// syncs the lot together.
//
// CloudKit constraint: every property must be optional or have a default,
// every relationship must be optional, no @Attribute(.unique) anywhere.
// We drop .unique on `id` even though it'd be nice — UUIDs are globally
// unique by construction so there's no real safety lost.

import Foundation
import SwiftData

// MARK: - Day type

/// Top-level workout focus the user picks on the home screen.
/// Keep raw values stable — they ship to iCloud and into exported markdown.
enum DayType: String, Codable, CaseIterable, Identifiable {
    case leg     = "Leg"
    case back    = "Back"
    case chest   = "Chest"
    case arm     = "Arm"
    case custom  = "Custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leg:    return "Leg Day"
        case .back:   return "Back Day"
        case .chest:  return "Chest Day"
        case .arm:    return "Arm Day"
        case .custom: return "Custom"
        }
    }

    /// SF Symbol for the home tile.
    var symbol: String {
        switch self {
        case .leg:    return "figure.strengthtraining.traditional"
        case .back:   return "figure.rower"
        case .chest:  return "figure.archery"
        case .arm:    return "dumbbell.fill"
        case .custom: return "plus.circle"
        }
    }

    /// Heuristic mapping from the master history's free-form focus strings
    /// (e.g. "Leg Day", "Back + Triceps", "Chest + Biceps", "Arms + Shoulders")
    /// to the four canonical day types. Defaults to .custom.
    static func infer(from focus: String) -> DayType {
        let f = focus.lowercased()
        if f.contains("leg") || f.contains("squat") || f.contains("posterior") || f.contains("hamstring") || f.contains("deadlift") {
            return .leg
        }
        if f.contains("back") {
            // "Back + Triceps" still counts as Back day for picker purposes.
            return .back
        }
        if f.contains("chest") {
            return .chest
        }
        if f.contains("arm") || f.contains("shoulder") || f.contains("bicep") || f.contains("tricep") {
            return .arm
        }
        return .custom
    }
}

// MARK: - Set mode

/// Mode/modifier from the user's logs (band, eccentric, pause, etc.).
/// Stored as String so unrecognized modes from history import survive round-trip.
enum SetMode: String, Codable, CaseIterable {
    case standard
    case warmUp     = "warm_up"
    case working    = "working"
    case eccentric
    case band
    case pause
    case dropSet    = "drop_set"
    case isoHold    = "iso_hold"

    var label: String {
        switch self {
        case .standard:  return "Standard"
        case .warmUp:    return "Warm-Up"
        case .working:   return "Working"
        case .eccentric: return "Eccentric"
        case .band:      return "Band"
        case .pause:     return "Pause"
        case .dropSet:   return "Drop Set"
        case .isoHold:   return "Iso Hold"
        }
    }
}

// MARK: - Exercise (template)

/// A named exercise the user has performed before. Seeded from history.md and
/// extended by the New Exercise sheet. The picker shows these sorted by recency
/// per day type.
@Model
final class Exercise {
    var id: UUID = UUID()
    /// Display name e.g. "Belt Squat (Voltra Harness)".
    var name: String = ""
    /// Equipment vocab e.g. "Voltra", "VTS Smith", "BTS Smith", "GetRX".
    var equipment: String = ""
    /// Day type this exercise is *primarily* associated with.
    /// Note: an exercise can appear on multiple day types (rows/face pulls show
    /// up in back AND shoulder days) — `dayTypeTags` carries the full set.
    var primaryDayTypeRaw: String = DayType.custom.rawValue
    /// All day types this exercise has ever been logged under (CSV of raw
    /// values). Avoids a many-to-many table for v0.2 — fine for ~50 rows.
    var dayTypeTagsCSV: String = ""
    /// Last-seen timestamp — drives recency sort in the picker.
    var lastUsedAt: Date? = nil
    /// Free-form notes (PR markers, form cues) — surfaced under the name.
    var notes: String? = nil
    /// True if this row was created by the history seeder, false if user-added.
    var seededFromHistory: Bool = false
    /// v0.4.5: Default drop-set step percentage for this exercise.
    /// Used as the default when the user starts a drop set without
    /// explicitly configuring per-drop weights — each subsequent drop
    /// reduces by `currentLb * defaultDropPercent`, rounded to 2.5 lb.
    /// Stored as a Double so the migration is additive (existing rows
    /// decode with the default 0.20 = 20%).
    var defaultDropPercent: Double = 0.20

    // Inverse — populated automatically by ExerciseInstance.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseInstance.exercise)
    var instances: [ExerciseInstance]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        equipment: String = "",
        primaryDayType: DayType = .custom,
        dayTypeTags: Set<DayType> = [],
        lastUsedAt: Date? = nil,
        notes: String? = nil,
        seededFromHistory: Bool = false
    ) {
        self.id = id
        self.name = name
        self.equipment = equipment
        self.primaryDayTypeRaw = primaryDayType.rawValue
        self.dayTypeTagsCSV = dayTypeTags.map(\.rawValue).sorted().joined(separator: ",")
        self.lastUsedAt = lastUsedAt
        self.notes = notes
        self.seededFromHistory = seededFromHistory
    }

    var primaryDayType: DayType {
        get { DayType(rawValue: primaryDayTypeRaw) ?? .custom }
        set { primaryDayTypeRaw = newValue.rawValue }
    }

    var dayTypeTags: Set<DayType> {
        get {
            Set(dayTypeTagsCSV
                .split(separator: ",")
                .compactMap { DayType(rawValue: String($0)) })
        }
        set {
            dayTypeTagsCSV = newValue.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    func addDayType(_ d: DayType) {
        var tags = dayTypeTags
        tags.insert(d)
        dayTypeTags = tags
    }
}

// MARK: - WorkoutSession (top-level container)

/// A workout session — created when the user picks a day type from the home
/// screen. Contains one or more ExerciseInstance children. Marked `endedAt`
/// when the user taps "End Session"; sessions without `endedAt` are drafts.
@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    var dayTypeRaw: String = DayType.custom.rawValue
    /// Free-form custom-day-type label when dayType == .custom (e.g. "Push").
    var customLabel: String? = nil
    /// Imported from history.md? If true, the session lives only for compare/PR
    /// lookups — it didn't come from real telemetry.
    var importedFromHistory: Bool = false
    /// Optional source-of-truth for imports — line offset in history.md or
    /// session # so we can avoid duplicate imports across launches.
    var importSourceID: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \ExerciseInstance.session)
    var instances: [ExerciseInstance]? = nil

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        dayType: DayType = .custom,
        customLabel: String? = nil,
        importedFromHistory: Bool = false,
        importSourceID: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.dayTypeRaw = dayType.rawValue
        self.customLabel = customLabel
        self.importedFromHistory = importedFromHistory
        self.importSourceID = importSourceID
    }

    var dayType: DayType {
        get { DayType(rawValue: dayTypeRaw) ?? .custom }
        set { dayTypeRaw = newValue.rawValue }
    }

    var displayLabel: String {
        if dayType == .custom, let c = customLabel, !c.isEmpty { return c }
        return dayType.displayName
    }

    var isActive: Bool { endedAt == nil }

    /// Flat sorted list of all sets across all instances.
    var allSets: [LoggedSet] {
        (instances ?? [])
            .flatMap { $0.sets ?? [] }
            .sorted { $0.completedAt < $1.completedAt }
    }

    var totalSets: Int { allSets.count }
    var totalReps: Int { allSets.reduce(0) { $0 + $1.reps } }
    var peakLb: Double { allSets.map(\.weightLb).max() ?? 0 }
}

// MARK: - ExerciseInstance (one exercise within a session)

/// One occurrence of an exercise within a session. Carries the per-instance
/// equipment override + ordered list of sets.
@Model
final class ExerciseInstance {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date? = nil
    /// Order within the session (1-based).
    var orderIndex: Int = 0
    /// Equipment override for this instance (defaults to Exercise.equipment).
    var equipment: String = ""

    // Owning relationships — both optional for CloudKit compatibility.
    var session: WorkoutSession? = nil
    var exercise: Exercise? = nil

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.instance)
    var sets: [LoggedSet]? = nil

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        orderIndex: Int = 0,
        equipment: String = "",
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.orderIndex = orderIndex
        self.equipment = equipment
        self.session = session
        self.exercise = exercise
    }

    var orderedSets: [LoggedSet] {
        (sets ?? []).sorted { $0.completedAt < $1.completedAt }
    }
}

// MARK: - LoggedSet (single set with full telemetry context)

/// One set logged by the user. Numeric fields auto-fill from telemetry; the
/// user can override before tapping "Log".
@Model
final class LoggedSet {
    var id: UUID = UUID()
    /// When the user tapped Log (final commit).
    var completedAt: Date = Date()
    /// Set boundaries from telemetry (when available).
    var startedAt: Date? = nil
    var endedAt: Date? = nil
    /// Order within the instance (1-based).
    var orderIndex: Int = 0

    // Numeric fields
    var weightLb: Double = 0
    /// Eccentric overload in lbs (Voltra-specific). Optional — many machines
    /// have no separate eccentric load.
    var eccentricLb: Double? = nil
    var reps: Int = 0
    /// Manual chains entry — pounds of added chain weight.
    /// Retained for back-compat with v0.3.x rows and history.md imports.
    /// New code should prefer `addedLoadLb` + `addedLoadType` which generalize
    /// this to any external load (chains, plates on a Voltra harness, weighted
    /// vest, accommodating band, etc.).
    var chainsLb: Double? = nil

    /// v0.4.0: generalized "non-Voltra weight added to this set" in lb.
    /// Combined with `addedLoadType` to render UI like "+45 lb chains".
    /// Optional + nil-safe so the SwiftData migration is additive.
    var addedLoadLb: Double? = nil
    /// v0.4.0: free-form type tag for the added load. Stored as String so we
    /// can extend the set of valid values without a model migration. Common
    /// values: "chains", "plates", "vest", "band", "other".
    var addedLoadType: String? = nil
    /// Voltra control-frame additions (v0.3 prototype port).
    /// All optional w/ defaults so the SwiftData migration is additive and
    /// safe to land mid-CloudKit-rollout: existing rows decode with nil/false
    /// and the writer treats nil as "not engaged".
    /// True if the chains weight was sent as inverse-chains (PARAM_FITNESS_INVERSE_CHAIN=1)
    /// rather than additive chains. Mutually exclusive with positive chainsLb meaning.
    var inverseChains: Bool = false
    /// Damper level 0..9 if this set was logged in damper mode. Nil for weight/band.
    var damperLevel: Int? = nil
    /// Resistance-band max force in lb if this set was logged in band mode. Nil otherwise.
    var bandMaxForceLb: Double? = nil

    // Telemetry-derived
    var peakForceLb: Double = 0
    var avgForceLb: Double? = nil

    // Mode + label + free-form notes
    var modeRaw: String = SetMode.standard.rawValue
    var labelText: String = ""    // "Warm-Up" | "Working" | ""
    var notes: String? = nil

    /// True if values were autofilled from telemetry; used for UI highlight.
    var autofilledFromTelemetry: Bool = false
    /// True if this set was reconstructed from the history.md import.
    var importedFromHistory: Bool = false

    /// v0.4.5: Drop-set chain. Empty (or nil) = normal single set; non-empty
    /// = drop set, where the parent's weight/reps/peak/avg represent DROP #1
    /// and `drops` carries drops 2..N (or 1..N including a mirror — both
    /// patterns are tolerated; see `orderedDrops`/`isDropSet` helpers below).
    /// Optional + cascade-delete so the migration is additive and removing
    /// a drop set cleans up its children.
    @Relationship(deleteRule: .cascade, inverse: \Drop.loggedSet)
    var drops: [Drop]? = nil

    var instance: ExerciseInstance? = nil

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        orderIndex: Int = 0,
        weightLb: Double = 0,
        eccentricLb: Double? = nil,
        reps: Int = 0,
        chainsLb: Double? = nil,
        peakForceLb: Double = 0,
        avgForceLb: Double? = nil,
        mode: SetMode = .standard,
        labelText: String = "",
        notes: String? = nil,
        autofilledFromTelemetry: Bool = false,
        importedFromHistory: Bool = false,
        inverseChains: Bool = false,
        damperLevel: Int? = nil,
        bandMaxForceLb: Double? = nil,
        addedLoadLb: Double? = nil,
        addedLoadType: String? = nil,
        instance: ExerciseInstance? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.orderIndex = orderIndex
        self.weightLb = weightLb
        self.eccentricLb = eccentricLb
        self.reps = reps
        self.chainsLb = chainsLb
        self.peakForceLb = peakForceLb
        self.avgForceLb = avgForceLb
        self.modeRaw = mode.rawValue
        self.labelText = labelText
        self.notes = notes
        self.autofilledFromTelemetry = autofilledFromTelemetry
        self.importedFromHistory = importedFromHistory
        self.inverseChains = inverseChains
        self.damperLevel = damperLevel
        self.bandMaxForceLb = bandMaxForceLb
        self.addedLoadLb = addedLoadLb
        self.addedLoadType = addedLoadType
        self.instance = instance
    }

    var mode: SetMode {
        get { SetMode(rawValue: modeRaw) ?? .standard }
        set { modeRaw = newValue.rawValue }
    }

    /// Total effective weight = weight + chains (eccentric is reported separately).
    var totalLb: Double { weightLb + (chainsLb ?? 0) }

    // MARK: - v0.4.5: Drop-set helpers

    /// True if this set has a multi-drop chain attached.
    var isDropSet: Bool { (drops?.count ?? 0) > 0 }

    /// All drops sorted by order. The parent set itself represents drop #1
    /// (mirrored), so `orderedDrops` returns ONLY the additional drops 2..N
    /// stored as `Drop` rows. UI that wants the full chain (including drop #1)
    /// should call `fullDropChain`.
    var orderedDrops: [Drop] {
        (drops ?? []).sorted { $0.order < $1.order }
    }

    /// Full chain including a synthetic Drop #1 built from the parent fields.
    /// Use this when rendering the chain in UI / markdown / charts so we
    /// don't have to special-case drop #1 everywhere.
    var fullDropChain: [Drop] {
        guard isDropSet else { return [] }
        let head = Drop(
            order: 1,
            weightLb: weightLb,
            addedPlatesLb: addedLoadLb,
            eccentricLb: eccentricLb,
            reps: reps,
            startedAt: startedAt,
            endedAt: endedAt,
            peakForceLb: peakForceLb,
            avgForceLb: avgForceLb,
            loggedSet: self
        )
        // Filter out any stored drop with order==1 (defensive — head is the
        // canonical mirror) and prepend the synthesized head.
        let tail = orderedDrops.filter { $0.order > 1 }
        return [head] + tail
    }
}

// MARK: - PR record (cached, derived)

/// Cached PR per (exercise, repsBucket). Recomputed on-demand from LoggedSet;
/// stored to keep the picker fast. Optional — skip in v0.2.0 if it slows us
/// down.
@Model
final class PRRecord {
    var id: UUID = UUID()
    var exerciseID: UUID = UUID()
    var loadLb: Double = 0
    var eccentricLb: Double? = nil
    var reps: Int = 0
    var achievedAt: Date = Date()
    var notes: String? = nil

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        loadLb: Double,
        eccentricLb: Double? = nil,
        reps: Int,
        achievedAt: Date,
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.loadLb = loadLb
        self.eccentricLb = eccentricLb
        self.reps = reps
        self.achievedAt = achievedAt
        self.notes = notes
    }
}

// MARK: - Schema bundle

/// All v0.2 logging models — register in ModelContainer alongside v0.1 models.
enum LoggingSchema {
    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        WorkoutSession.self,
        ExerciseInstance.self,
        LoggedSet.self,
        Drop.self,            // v0.4.5
        PRRecord.self,
    ]
}
