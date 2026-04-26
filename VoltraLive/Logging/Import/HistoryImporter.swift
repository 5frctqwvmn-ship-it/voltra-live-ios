// HistoryImporter.swift
// Reads seed/history.md (master MJ workout history, ~3400 lines) and seeds
// SwiftData with Exercise rows + imported WorkoutSession/ExerciseInstance/
// LoggedSet rows on first launch.
//
// Parser strategy:
//   - File is split into "Session N — <date> — <day type>" blocks.
//   - Within a block we scan exercise headers (titles like "Belt Squats (Voltra)")
//     followed by a Set/Label/Weight/... table.
//   - Tables are tokenized by collapsing 2+ spaces into one separator. Columns
//     are inferred from the header row of each table; `Weight`, `Eccentric`,
//     and `Reps` are the only fields the picker actually needs, but we keep
//     `Label` and `Notes` for the markdown round-trip later.
//
// The importer is IDEMPOTENT: it tags every imported session with
// `importSourceID = "history.md::Session N"`, and a record's existence skips
// re-import. This means re-running the seeder after an app update only fills
// in newly-added sessions in the file.
//
// First-launch behavior is gated by UserDefaults key `historyImportV1Done`.
// We bump this to v2 etc. if the parser meaningfully changes.

import Foundation
import SwiftData

@MainActor
enum HistoryImporter {

    private static let importDoneKey = "historyImportV1Done"
    /// Bump this whenever parser logic changes OR we want to force re-import on
    /// the next launch. v0.2.2 bumped to 2 to recover from v0.2.0/v0.2.1 stores
    /// that ended up with no leg-day exercises tagged on real devices.
    /// v0.3.1 bumped to 3 because real-device installs of build 6/7 ended up
    /// with empty history (importer marked done but no sessions/exercises
    /// inserted) — re-run unconditionally on next launch to recover.
    /// v0.3.3 bumped to 4 because v0.3.1's bump didn't fully take on devices
    /// where CloudKit had already synced the (empty) UserDefaults flag back
    /// to v3 from another device. Combined with the new empty-store
    /// recovery path in runIfNeeded.
    /// v0.3.5 bumped to 5 because the v0.3.3 fix only handled "store has zero
    /// sessions" — a real device showed 17 stub sessions (rows with
    /// importSourceID set but zero ExerciseInstance children) leftover from
    /// older buggy parser runs. Combined with stub-session purge in
    /// importMarkdown so dedup skips can't perpetuate the empty rows.
    private static let importVersion = 5

    // MARK: - Public entry point

    /// Run on app launch after the ModelContainer is ready. Parses the bundled
    /// seed/history.md and inserts any sessions not already present.
    /// Safe to call multiple times.
    static func runIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        let doneVersion = defaults.integer(forKey: importDoneKey)

        let counts = storeCounts(context: context)
        let storeIsEmpty = counts.sessions == 0
        let stubCount = stubImportedSessionCount(context: context)

        // "Looks healthy" = at version, has sessions, AND no stub sessions
        // (imported rows that have zero ExerciseInstance children). Stubs are
        // the smoking gun of an earlier broken parser run; if any exist we
        // need to redo the import.
        if doneVersion >= importVersion && !storeIsEmpty && stubCount == 0 {
            print("[HistoryImporter] already at v\(doneVersion), \(counts.sessions) sessions, no stubs — skipping")
            return
        }
        if stubCount > 0 {
            print("[HistoryImporter] detected \(stubCount) stub sessions (imported but no children) — will purge and re-run")
        }

        // Empty-store recovery path: UserDefaults says we've imported, but
        // SwiftData has zero sessions. Could be (a) genuinely lost data, or
        // (b) CloudKit hasn't replicated yet on a freshly-installed device.
        // Wait 6 seconds and re-check before re-importing to avoid creating
        // duplicates that CloudKit will then conflict-merge with the
        // already-synced rows.
        if storeIsEmpty && doneVersion >= importVersion {
            print("[HistoryImporter] doneVersion=\(doneVersion) but store is EMPTY — waiting 6s for CloudKit")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let recheck = storeCounts(context: context)
                if recheck.sessions == 0 {
                    print("[HistoryImporter] still empty after CloudKit window — forcing re-import")
                    do {
                        try forceReimport(context: context)
                    } catch {
                        print("[HistoryImporter] recovery re-import FAILED: \(error)")
                    }
                } else {
                    print("[HistoryImporter] CloudKit populated \(recheck.sessions) sessions, no re-import needed")
                }
            }
            return
        }

        print("[HistoryImporter] running (current v\(doneVersion) -> target v\(importVersion))")

        do {
            let url = Bundle.main.url(forResource: "history", withExtension: "md", subdirectory: "seed")
                   ?? Bundle.main.url(forResource: "history", withExtension: "md")
            guard let url else {
                print("[HistoryImporter] seed/history.md missing in bundle — skipping")
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            try importMarkdown(text, context: context)
            defaults.set(importVersion, forKey: importDoneKey)
            print("[HistoryImporter] Import complete (v\(importVersion))")
        } catch {
            print("[HistoryImporter] FAILED: \(error)")
            // Don't mark as done — we'll retry next launch.
        }
    }

    /// Diagnostic: counts (sessions, exercises, sets, leg-tagged exercises)
    /// for the Debug screen.
    static func storeCounts(context: ModelContext) -> (sessions: Int, exercises: Int, sets: Int, legTagged: Int) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let sets = (try? context.fetch(FetchDescriptor<LoggedSet>())) ?? []
        let legTagged = exercises.filter { $0.dayTypeTags.contains(.leg) }.count
        return (sessions.count, exercises.count, sets.count, legTagged)
    }

    /// Force re-import (used by debug menu / tests).
    static func forceReimport(context: ModelContext) throws {
        UserDefaults.standard.removeObject(forKey: importDoneKey)
        runIfNeeded(context: context)
    }

    /// Nuclear option: delete every row that came from history.md — sessions,
    /// instances, sets — then run the importer fresh. Used by the Debug
    /// "Wipe & re-import" button. Live (non-imported) sessions are untouched.
    /// Returns the number of imported sessions deleted.
    @discardableResult
    static func wipeAndReimport(context: ModelContext) throws -> Int {
        let removed = try wipeImportedRows(context: context)
        UserDefaults.standard.removeObject(forKey: importDoneKey)
        runIfNeeded(context: context)
        return removed
    }

    /// Delete every WorkoutSession with `importedFromHistory: true`. Cascades
    /// to ExerciseInstance + LoggedSet via SwiftData relationship deletion if
    /// configured; otherwise we walk children explicitly.
    private static func wipeImportedRows(context: ModelContext) throws -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var removed = 0
        for session in sessions where session.importedFromHistory {
            // Walk children defensively in case the relationship cascade isn't
            // configured to delete on parent removal.
            for inst in session.instances ?? [] {
                for set in inst.sets ?? [] {
                    context.delete(set)
                }
                context.delete(inst)
            }
            context.delete(session)
            removed += 1
        }
        // Also delete Exercise rows that came purely from the seed and have no
        // remaining instances after the wipe — otherwise re-import re-uses the
        // existing names with stale dayTypeTags.
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for ex in exercises where ex.seededFromHistory {
            let liveInstances = (ex.instances ?? []).filter { inst in
                (inst.session?.importedFromHistory ?? false) == false
            }
            if liveInstances.isEmpty {
                context.delete(ex)
            }
        }
        try context.save()
        print("[HistoryImporter] wiped \(removed) imported sessions")
        return removed
    }

    /// Count sessions that claim to come from the import but have zero
    /// ExerciseInstance children. These are the smoking-gun rows from earlier
    /// buggy parser runs that shipped to real devices.
    static func stubImportedSessionCount(context: ModelContext) -> Int {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return sessions.filter {
            $0.importedFromHistory && ($0.instances?.count ?? 0) == 0
        }.count
    }

    // MARK: - Markdown parser

    /// Parse the full history markdown into model rows and insert them.
    /// Visible (internal) for unit testing.
    static func importMarkdown(_ text: String, context: ModelContext) throws {
        let parsed = parse(text)

        // 1. Build / reuse Exercise rows keyed by name+equipment.
        var exerciseCache: [String: Exercise] = [:]
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for ex in existing {
            exerciseCache[ex.cacheKey] = ex
        }

        // 2. Look up which sessions have already been imported.
        var existingSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []

        // 2a. Purge stub imported sessions (rows with importSourceID set but
        // zero exercise instances). These came from earlier buggy parser runs
        // and would otherwise dedup-skip forever, leaving the user with a
        // permanently empty history. Once we delete them the loop below will
        // recreate them properly.
        var stubsPurged = 0
        for s in existingSessions where s.importedFromHistory && (s.instances?.count ?? 0) == 0 {
            context.delete(s)
            stubsPurged += 1
        }
        if stubsPurged > 0 {
            print("[HistoryImporter] purged \(stubsPurged) stub imported sessions before re-import")
            try context.save()
            existingSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        }

        let importedSourceIDs: Set<String> = Set(existingSessions.compactMap(\.importSourceID))

        var insertedSessions = 0

        for sessionDoc in parsed {
            let sourceID = "history.md::Session \(sessionDoc.number)"
            if importedSourceIDs.contains(sourceID) { continue }

            let session = WorkoutSession(
                startedAt: sessionDoc.date,
                endedAt: sessionDoc.date.addingTimeInterval(sessionDoc.durationSeconds ?? 3600),
                dayType: sessionDoc.dayType,
                customLabel: sessionDoc.dayType == .custom ? sessionDoc.rawDayLabel : nil,
                importedFromHistory: true,
                importSourceID: sourceID
            )
            context.insert(session)

            for (exIdx, exDoc) in sessionDoc.exercises.enumerated() {
                let key = exDoc.cacheKey
                let exercise: Exercise
                if let hit = exerciseCache[key] {
                    exercise = hit
                } else {
                    exercise = Exercise(
                        name: exDoc.name,
                        equipment: exDoc.equipment,
                        primaryDayType: sessionDoc.dayType,
                        dayTypeTags: [sessionDoc.dayType],
                        lastUsedAt: sessionDoc.date,
                        seededFromHistory: true
                    )
                    context.insert(exercise)
                    exerciseCache[key] = exercise
                }
                exercise.addDayType(sessionDoc.dayType)
                if exercise.lastUsedAt == nil || exercise.lastUsedAt! < sessionDoc.date {
                    exercise.lastUsedAt = sessionDoc.date
                }

                let instance = ExerciseInstance(
                    startedAt: sessionDoc.date,
                    endedAt: nil,
                    orderIndex: exIdx + 1,
                    equipment: exDoc.equipment,
                    session: session,
                    exercise: exercise
                )
                context.insert(instance)

                for (setIdx, setDoc) in exDoc.sets.enumerated() {
                    let logged = LoggedSet(
                        completedAt: sessionDoc.date.addingTimeInterval(Double(setIdx) * 60),
                        startedAt: nil,
                        endedAt: nil,
                        orderIndex: setIdx + 1,
                        weightLb: setDoc.weightLb ?? 0,
                        eccentricLb: setDoc.eccentricLb,
                        reps: setDoc.reps ?? 0,
                        chainsLb: nil,
                        peakForceLb: 0,
                        avgForceLb: nil,
                        mode: setDoc.mode,
                        labelText: setDoc.label,
                        notes: setDoc.notes,
                        autofilledFromTelemetry: false,
                        importedFromHistory: true,
                        instance: instance
                    )
                    context.insert(logged)
                }
            }

            insertedSessions += 1
        }

        try context.save()
        print("[HistoryImporter] Inserted \(insertedSessions) sessions; cache has \(exerciseCache.count) exercises")
    }

    // MARK: - Parsing internals

    /// One parsed session (intermediate doc — not a SwiftData model yet).
    struct ParsedSession {
        let number: Int
        let date: Date
        let rawDayLabel: String
        let dayType: DayType
        let durationSeconds: TimeInterval?
        var exercises: [ParsedExercise]
    }

    struct ParsedExercise {
        let name: String
        let equipment: String
        var sets: [ParsedSet]

        var cacheKey: String {
            "\(name.lowercased())|\(equipment.lowercased())"
        }
    }

    struct ParsedSet {
        var label: String = ""
        var weightLb: Double? = nil
        var eccentricLb: Double? = nil
        var reps: Int? = nil
        var notes: String? = nil
        var mode: SetMode = .standard
    }

    /// Top-level: split on Session headers, parse each block.
    static func parse(_ text: String) -> [ParsedSession] {
        // Match BOTH em-dash and en-dash because the source uses U+2014 (—).
        let pattern = #"(?m)^Session\s+(\d+)\s*—\s*([^—\n]+?)\s*—\s*([^\n]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: fullRange)

        var sessions: [ParsedSession] = []
        for (i, m) in matches.enumerated() {
            let blockStart = m.range.location
            let blockEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: blockStart, length: blockEnd - blockStart))

            let number = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let dateStr = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            let dayLabel = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)

            guard let date = parseDate(dateStr) else { continue }

            var session = ParsedSession(
                number: number,
                date: date,
                rawDayLabel: dayLabel,
                dayType: DayType.infer(from: dayLabel),
                durationSeconds: extractDuration(block),
                exercises: []
            )

            session.exercises = parseExercises(in: block)
            sessions.append(session)
        }
        return sessions
    }

    // MARK: - Date / duration parsing

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy"
        f.timeZone = TimeZone(identifier: "America/Chicago")  // user's tz
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        // Format in file is "February 24, 2025"
        if let d = dateFormatter.date(from: s) { return d }
        // Some sessions might be "Feb 24, 2025" — fallback
        let alt = DateFormatter()
        alt.locale = Locale(identifier: "en_US_POSIX")
        alt.dateFormat = "MMM d, yyyy"
        alt.timeZone = TimeZone(identifier: "America/Chicago")
        return alt.date(from: s)
    }

    /// "53 minutes, 46 seconds" / "1 hour, 5 minutes" / "1h 14m 6s"
    private static func extractDuration(_ block: String) -> TimeInterval? {
        // e.g. "Duration: 53 minutes, 46 seconds"
        if let range = block.range(of: #"Duration:\s*([^\n]+)"#, options: .regularExpression) {
            let line = String(block[range])
                .replacingOccurrences(of: "Duration:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return parseHumanDuration(line)
        }
        return nil
    }

    private static func parseHumanDuration(_ s: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var matched = false
        let patterns: [(String, Double)] = [
            (#"(\d+)\s*hour"#, 3600),
            (#"(\d+)\s*h\b"#,  3600),
            (#"(\d+)\s*minute"#, 60),
            (#"(\d+)\s*m\b"#,    60),
            (#"(\d+)\s*second"#, 1),
            (#"(\d+)\s*s\b"#,    1),
        ]
        for (p, mult) in patterns {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let nr = Range(m.range(at: 1), in: s),
               let n = Double(s[nr]) {
                total += n * mult
                matched = true
            }
        }
        return matched ? total : nil
    }

    // MARK: - Exercise + set parsing within a session block

    /// Parse exercise blocks within a session block.
    /// An exercise block looks like:
    ///   Belt Squats (Voltra)
    ///
    ///
    ///    Set     Label            Weight   Eccentric        Reps      Notes
    ///    1         Warm-Up        33 lbs       —             12
    ///    ...
    private static func parseExercises(in block: String) -> [ParsedExercise] {
        // Strip control chars (form feed U+000C, etc.) that PDFs / pasted text
        // sneak in. These break the leading-digit detection in the row loop.
        let cleaned = block.unicodeScalars
            .filter { scalar -> Bool in
                if scalar == "\n" || scalar == "\r" || scalar == "\t" { return true }
                return !CharacterSet.controlCharacters.contains(scalar)
            }
            .map(Character.init)
        let lines = String(cleaned).components(separatedBy: "\n")
        var exercises: [ParsedExercise] = []

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Skip header / metadata noise we already consumed.
            if line.isEmpty || line.hasPrefix("Session ") || line.hasPrefix("Focus:")
                || line.hasPrefix("Duration:") || line.hasPrefix("Active kcal")
                || line.hasPrefix("Avg HR:") || line.hasPrefix("Range:")
                || line.hasPrefix("Insights:") || line.hasPrefix("Note:")
                || line.hasPrefix("Equipment:")
            {
                i += 1
                continue
            }

            // An exercise header is a non-table, non-bullet line that has "Set"
            // table within ~5 lines below it. Detect by looking ahead.
            if isExerciseHeader(at: i, in: lines) {
                let (name, equipment) = splitExerciseTitle(line)
                var ex = ParsedExercise(name: name, equipment: equipment, sets: [])

                // Skip blank lines
                var j = i + 1
                while j < lines.count && lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                guard j < lines.count else { break }

                let headerLine = lines[j]
                let columns = parseTableHeader(headerLine)
                guard !columns.isEmpty, columns.contains("Set") else {
                    i += 1
                    continue
                }
                j += 1

                // Consume rows until a blank line followed by either another
                // exercise header or end of block.
                var blankRun = 0
                while j < lines.count {
                    let raw = lines[j]
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        blankRun += 1
                        // Two+ blanks = end of table.
                        if blankRun >= 2 { break }
                        j += 1
                        continue
                    }
                    blankRun = 0

                    // Insights / notes prefix break out.
                    if trimmed.hasPrefix("Insights:") || trimmed.hasPrefix("Note:") {
                        break
                    }

                    // Lines with no leading digit usually mean we've crossed
                    // into the next exercise's title.
                    if let firstChar = trimmed.first, !firstChar.isNumber {
                        // Probably next exercise title — stop.
                        break
                    }

                    if let parsed = parseTableRow(trimmed, columns: columns) {
                        ex.sets.append(parsed)
                    }
                    j += 1
                }

                if !ex.sets.isEmpty { exercises.append(ex) }
                i = j
                continue
            }

            i += 1
        }

        // Fallback: many sessions in the master history use an INLINE-PROSE
        // format instead of the Set/Label/Weight table. We try the table
        // parser first (above) and only fall through to the inline parser
        // if that yielded nothing.
        if exercises.isEmpty {
            exercises = parseInlineProseExercises(lines: lines)
        }

        return exercises
    }

    /// Inline-prose format examples seen in seed/history.md:
    ///   Belt Squats (Voltra Harness)
    ///
    ///   WU1: 50+18 ecc x 10. WU2: 90+32 ecc x 17. Working: 130+46 ecc x 9,
    ///   200+20 ecc x 10, 240+48 ecc x 10, 260+52 ecc x 8
    ///
    /// Heuristic: a non-numeric, non-metadata line followed within ~3 lines
    /// by a line containing `WU`, `Working`, `Set 1`, or a digits-x-digits
    /// pattern is treated as an exercise header. We then collect every
    /// `<weight>+<ecc> ecc x <reps>` or `<weight> x <reps>` token as a set.
    private static func parseInlineProseExercises(lines: [String]) -> [ParsedExercise] {
        var exercises: [ParsedExercise] = []

        // Pattern: optional sign + integer/decimal weight, optional `+ecc`,
        // mandatory ` x <reps>`. Examples: `50+18 ecc x 10`, `200+20 ecc x 8`,
        // `120 x 12`, `BW x 8`.
        let setRegex = try? NSRegularExpression(
            pattern: #"(\d+(?:\.\d+)?)(?:\s*\+\s*(\d+(?:\.\d+)?)\s*ecc)?\s*[x×]\s*(\d+)"#,
            options: [.caseInsensitive]
        )
        guard let setRegex else { return [] }

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            i += 1
            if line.isEmpty { continue }
            if isMetadataLine(line) { continue }
            // Title-like: contains '(' and ')' and is not numeric, not a heading
            guard line.contains("("), line.contains(")"),
                  !line.hasPrefix("Session "), !line.hasSuffix(":")
            else { continue }

            // Look ahead for a body line within next 4 non-empty lines that
            // contains at least one set token.
            var bodyLines: [String] = []
            var look = i
            var nonEmptySeen = 0
            while look < lines.count, nonEmptySeen < 12 {
                let t = lines[look].trimmingCharacters(in: .whitespaces)
                look += 1
                if t.isEmpty {
                    if !bodyLines.isEmpty { break }
                    continue
                }
                nonEmptySeen += 1
                // Stop if we hit another title-like line.
                if t.contains("(") && t.contains(")") && !bodyLines.isEmpty { break }
                if isMetadataLine(t) { continue }
                bodyLines.append(t)
            }
            guard !bodyLines.isEmpty else { continue }
            let body = bodyLines.joined(separator: " ")
            let nsBody = body as NSString
            let matches = setRegex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
            guard !matches.isEmpty else { continue }

            let (name, equipment) = splitExerciseTitle(line)
            var ex = ParsedExercise(name: name, equipment: equipment, sets: [])
            for (idx, m) in matches.enumerated() {
                var set = ParsedSet()
                set.weightLb = Double(nsBody.substring(with: m.range(at: 1)))
                if m.range(at: 2).location != NSNotFound {
                    set.eccentricLb = Double(nsBody.substring(with: m.range(at: 2)))
                }
                set.reps = Int(nsBody.substring(with: m.range(at: 3)))
                // Best-effort label: WU1/WU2/WU = warm-up, otherwise working.
                let surrounding = nsBody.substring(with: NSRange(
                    location: max(0, m.range.location - 8),
                    length: min(8, m.range.location)
                )).lowercased()
                if surrounding.contains("wu") {
                    set.mode = .warmUp
                    set.label = "Warm-Up"
                } else {
                    set.mode = .working
                    set.label = "Working"
                }
                _ = idx
                ex.sets.append(set)
            }
            if !ex.sets.isEmpty { exercises.append(ex) }
            i = look
        }
        return exercises
    }

    /// Lines we should never treat as exercise titles or set rows.
    private static func isMetadataLine(_ line: String) -> Bool {
        let prefixes = [
            "Session ", "Focus:", "Duration:", "Time:", "Active kcal",
            "Avg HR:", "Range:", "Insights:", "Note:", "NOTE:",
            "Equipment:", "Vitals:",
        ]
        for p in prefixes where line.hasPrefix(p) { return true }
        return false
    }

    /// An exercise header: non-empty line whose next non-blank line within 4
    /// lines starts with the column header "Set".
    private static func isExerciseHeader(at idx: Int, in lines: [String]) -> Bool {
        let line = lines[idx].trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return false }
        // Avoid matching obvious metadata lines.
        if line.hasPrefix("|") || line.hasSuffix(":") { return false }
        if line.first?.isNumber == true { return false }

        var look = idx + 1
        var seen = 0
        while look < lines.count, seen < 6 {
            let l = lines[look].trimmingCharacters(in: .whitespaces)
            if !l.isEmpty {
                if l.hasPrefix("Set ") || l == "Set" || l.lowercased().hasPrefix("set ") {
                    return true
                }
                // First non-empty next line is something else — not a header.
                return false
            }
            seen += 1
            look += 1
        }
        return false
    }

    /// "Belt Squats (Voltra)" -> (name: "Belt Squats", equipment: "Voltra")
    /// "Pull-Ups" -> (name: "Pull-Ups", equipment: "")
    private static func splitExerciseTitle(_ s: String) -> (String, String) {
        guard let open = s.lastIndex(of: "("),
              let close = s.lastIndex(of: ")"),
              open < close else {
            return (s, "")
        }
        let name = s[..<open].trimmingCharacters(in: .whitespaces)
        let equip = s[s.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return (name, equip)
    }

    /// Tokenize a table header like "Set Label Weight Eccentric Reps Notes".
    private static func parseTableHeader(_ s: String) -> [String] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        // Split on 2+ whitespace OR single whitespace if columns look short.
        let chunks = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Recombine header tokens that are single words.
        return chunks
    }

    /// Parse one table row given the column ordering.
    private static func parseTableRow(_ row: String, columns: [String]) -> ParsedSet? {
        // Tokens separated by 2+ spaces.
        let tokens = splitOnBigSpaces(row)
        guard !tokens.isEmpty else { return nil }
        // First token is the set number.
        guard Int(tokens[0]) != nil else { return nil }

        var set = ParsedSet()
        let bodyTokens = Array(tokens.dropFirst())

        // Map by column count match: header may have N columns; we have N-1
        // body tokens. Walk the columns and consume tokens.
        var ti = 0
        for col in columns where col != "Set" {
            guard ti < bodyTokens.count else { break }
            let tok = bodyTokens[ti]
            switch col {
            case "Label":
                set.label = tok
                set.mode = inferMode(label: tok)
                ti += 1
            case "Weight":
                set.weightLb = parseLbs(tok)
                // "60 lbs band mode" — combine with next tokens until we hit
                // a number-only column (Eccentric or Reps).
                if tok.lowercased().contains("band") { set.mode = .band }
                ti += 1
            case "Eccentric":
                set.eccentricLb = parseEccentric(tok)
                ti += 1
            case "Reps":
                set.reps = parseReps(tok)
                ti += 1
            case "Notes":
                // Glue remaining tokens.
                let rest = bodyTokens.dropFirst(ti).joined(separator: " ")
                set.notes = rest.isEmpty ? nil : rest
                ti = bodyTokens.count
            default:
                ti += 1
            }
        }

        // Require at minimum reps OR weight to count as a row.
        if set.reps == nil && set.weightLb == nil { return nil }
        return set
    }

    /// Split a row on runs of 2+ whitespace.
    private static func splitOnBigSpaces(_ s: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\s{2,}"#) else {
            return s.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        // Replace 2+ whitespace runs with a unit separator (U+001F) we can
        // safely split on.
        let replaced = regex.stringByReplacingMatches(
            in: s,
            options: [],
            range: range,
            withTemplate: "\u{1F}"
        )
        return replaced
            .split(separator: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// "85 lbs", "60 lbs band mode", "BW + 30 lbs" → 85 / 60 / 30
    /// "—" → nil
    private static func parseLbs(_ s: String) -> Double? {
        if s.contains("—") || s.isEmpty { return nil }
        // Find first number sequence.
        let pattern = #"-?\d+(\.\d+)?"#
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(m.range, in: s) else { return nil }
        return Double(s[range])
    }

    /// "+27 ecc" → 27, "—" → nil, "" → nil
    private static func parseEccentric(_ s: String) -> Double? {
        if s.contains("—") || s.isEmpty { return nil }
        return parseLbs(s)
    }

    /// "12" → 12, "6.5" → 6 (round down — half-rep notation), "10 (PR)" → 10
    private static func parseReps(_ s: String) -> Int? {
        let pattern = #"-?\d+(\.\d+)?"#
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(m.range, in: s) else { return nil }
        return Int(Double(s[range]) ?? 0)
    }

    private static func inferMode(label: String) -> SetMode {
        let l = label.lowercased()
        if l.contains("warm") { return .warmUp }
        if l.contains("work") { return .working }
        if l.contains("ecc")  { return .eccentric }
        if l.contains("band") { return .band }
        if l.contains("pause") { return .pause }
        if l.contains("drop") { return .dropSet }
        return .standard
    }
}

// MARK: - Exercise convenience

private extension Exercise {
    var cacheKey: String { "\(name.lowercased())|\(equipment.lowercased())" }
}
