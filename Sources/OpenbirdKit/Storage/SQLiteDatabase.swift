import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteValue: Sendable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null
}

public enum SQLiteError: Error, CustomStringConvertible, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)
    case generic(String)

    public var description: String {
        switch self {
        case .open(let message),
             .prepare(let message),
             .step(let message),
             .bind(let message),
             .generic(let message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(url: URL) throws {
        try OpenbirdPaths.ensureApplicationSupportDirectory()
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &db, flags, nil) != SQLITE_OK || db == nil {
            throw SQLiteError.open("Failed to open database at \(url.path)")
        }
        self.handle = db!
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
        try seedDefaultsIfNeeded()
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(lastErrorMessage())
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw SQLiteError.step(lastErrorMessage())
            }
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    public func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw SQLiteError.generic("Invalid UTF-8 payload")
        }
        return try decoder.decode(type, from: data)
    }

    public func loadSettings() throws -> AppSettings {
        let rows = try query("SELECT key, value FROM app_settings;")
        guard rows.isEmpty == false else { return AppSettings() }
        var dict: [String: String] = [:]
        for row in rows {
            dict[row.stringValue(for: "key")] = row.stringValue(for: "value")
        }
        var settings = AppSettings()
        settings.capturePaused = dict["capturePaused"] == "true"
        if let capturePauseUntil = normalizeOptionalSetting(dict["capturePauseUntil"]),
           let timestamp = Double(capturePauseUntil) {
            settings.capturePauseUntil = Date(timeIntervalSince1970: timestamp)
        }
        settings.capturePauseSessionID = normalizeOptionalSetting(dict["capturePauseSessionID"])
        settings.retentionDays = Int(dict["retentionDays"] ?? "14") ?? 14
        settings.activeProviderID = normalizeOptionalSetting(dict["activeProviderID"])
        settings.selectedProviderID = normalizeOptionalSetting(dict["selectedProviderID"])
        if let heartbeat = normalizeOptionalSetting(dict["lastCollectorHeartbeat"]), let timestamp = Double(heartbeat) {
            settings.lastCollectorHeartbeat = Date(timeIntervalSince1970: timestamp)
        }
        settings.collectorStatus = CollectorStatus(rawValue: dict["collectorStatus"] ?? "stopped") ?? .stopped
        settings.collectorOwnerID = normalizeOptionalSetting(dict["collectorOwnerID"])
        settings.collectorOwnerName = normalizeOptionalSetting(dict["collectorOwnerName"])
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let values: [(String, String)] = [
            ("capturePaused", settings.capturePaused ? "true" : "false"),
            ("capturePauseUntil", settings.capturePauseUntil.map { String($0.timeIntervalSince1970) } ?? ""),
            ("capturePauseSessionID", settings.capturePauseSessionID ?? ""),
            ("retentionDays", String(settings.retentionDays)),
            ("activeProviderID", settings.activeProviderID ?? ""),
            ("selectedProviderID", settings.selectedProviderID ?? ""),
            ("lastCollectorHeartbeat", settings.lastCollectorHeartbeat.map { String($0.timeIntervalSince1970) } ?? ""),
            ("collectorStatus", settings.collectorStatus.rawValue),
            ("collectorOwnerID", settings.collectorOwnerID ?? ""),
            ("collectorOwnerName", settings.collectorOwnerName ?? ""),
        ]
        for (key, value) in values {
            try execute(
                """
                INSERT INTO app_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """,
                bindings: [.text(key), .text(value)]
            )
        }
    }

    public func claimCollectorLease(ownerID: String, ownerName: String, now: Date, timeout: TimeInterval) throws -> Bool {
        try withImmediateTransaction {
            var settings = try loadSettings()
            settings.normalizeCapturePause(now: now, sessionID: ownerID)
            let currentOwnerID = settings.collectorOwnerID
            let heartbeatAge = settings.lastCollectorHeartbeat.map { now.timeIntervalSince($0) } ?? .infinity
            let hasFreshOwner = currentOwnerID != nil && heartbeatAge <= timeout
            if hasFreshOwner, currentOwnerID != ownerID {
                return false
            }
            if currentOwnerID != ownerID {
                settings.collectorStatus = settings.isCapturePaused(now: now, sessionID: ownerID) ? .paused : .idle
            }
            settings.collectorOwnerID = ownerID
            settings.collectorOwnerName = ownerName
            settings.lastCollectorHeartbeat = now
            try saveSettings(settings)
            return true
        }
    }

    public func updateCollectorStatus(ownerID: String, status: CollectorStatus, heartbeat: Date) throws -> Bool {
        try withImmediateTransaction {
            var settings = try loadSettings()
            guard settings.collectorOwnerID == ownerID else {
                return false
            }
            settings.collectorStatus = status
            settings.lastCollectorHeartbeat = heartbeat
            try saveSettings(settings)
            return true
        }
    }

    public func releaseCollectorLease(ownerID: String) throws {
        try withImmediateTransaction {
            var settings = try loadSettings()
            settings.normalizeCapturePause(sessionID: ownerID)
            guard settings.collectorOwnerID == ownerID else {
                return
            }
            settings.collectorOwnerID = nil
            settings.collectorOwnerName = nil
            settings.lastCollectorHeartbeat = nil
            settings.collectorStatus = settings.isCapturePaused(sessionID: ownerID) ? .paused : .stopped
            try saveSettings(settings)
        }
    }

    public func saveProviderConfig(_ config: ProviderConfig) throws {
        let headers = try encode(config.customHeaders)
        try execute(
            """
            INSERT OR REPLACE INTO provider_configs
            (id, name, kind, base_url, api_key, chat_model, embedding_model, is_enabled, headers_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(config.id),
                .text(config.name),
                .text(config.kind.rawValue),
                .text(config.baseURL),
                .text(config.apiKey),
                .text(config.chatModel),
                .text(config.embeddingModel),
                .integer(config.isEnabled ? 1 : 0),
                .text(headers),
                .double(config.createdAt.timeIntervalSince1970),
                .double(config.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadProviderConfigs() throws -> [ProviderConfig] {
        try query("SELECT * FROM provider_configs ORDER BY created_at ASC;").map { row in
            ProviderConfig(
                id: row.stringValue(for: "id"),
                name: row.stringValue(for: "name"),
                kind: ProviderKind(rawValue: row.stringValue(for: "kind")) ?? .ollama,
                baseURL: row.stringValue(for: "base_url"),
                apiKey: row.stringValue(for: "api_key"),
                chatModel: row.stringValue(for: "chat_model"),
                embeddingModel: row.stringValue(for: "embedding_model"),
                isEnabled: row.intValue(for: "is_enabled") == 1,
                customHeaders: (try? decode([String: String].self, from: row.stringValue(for: "headers_json"))) ?? [:],
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
                updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
            )
        }
    }

    public func saveExclusion(_ exclusion: ExclusionRule) throws {
        try execute(
            """
            INSERT OR REPLACE INTO exclusions (id, kind, pattern, is_enabled, created_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(exclusion.id),
                .text(exclusion.kind.rawValue),
                .text(exclusion.pattern),
                .integer(exclusion.isEnabled ? 1 : 0),
                .double(exclusion.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadExclusions() throws -> [ExclusionRule] {
        try query("SELECT * FROM exclusions ORDER BY created_at ASC;").map { row in
            ExclusionRule(
                id: row.stringValue(for: "id"),
                kind: ExclusionKind(rawValue: row.stringValue(for: "kind")) ?? .bundleID,
                pattern: row.stringValue(for: "pattern"),
                isEnabled: row.intValue(for: "is_enabled") == 1,
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at"))
            )
        }
    }

    public func deleteExclusion(id: String) throws {
        try execute("DELETE FROM exclusions WHERE id = ?;", bindings: [.text(id)])
    }

    public func saveActivityEvent(_ event: ActivityEvent) throws -> ActivityEvent {
        try withImmediateTransaction {
            let overlappingDuplicates = try query(
                """
                SELECT * FROM activity_events
                WHERE content_hash = ?
                  AND is_excluded = ?
                  AND started_at <= ?
                  AND ended_at >= ?
                ORDER BY started_at ASC, ended_at DESC;
                """,
                bindings: [
                    .text(event.contentHash),
                    .integer(event.isExcluded ? 1 : 0),
                    .double(event.endedAt.timeIntervalSince1970),
                    .double(event.startedAt.timeIntervalSince1970),
                ]
            ).map(ActivityEvent.init(row:))

            let mergedEvent = mergeActivityEvent(event, with: overlappingDuplicates)
            for duplicate in overlappingDuplicates where duplicate.id != mergedEvent.id {
                try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(duplicate.id)])
                try execute("DELETE FROM activity_events WHERE id = ?;", bindings: [.text(duplicate.id)])
            }

            try execute(
                """
                INSERT OR REPLACE INTO activity_events
                (id, started_at, ended_at, bundle_id, app_name, window_title, url, visible_text, source, content_hash, is_excluded)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(mergedEvent.id),
                    .double(mergedEvent.startedAt.timeIntervalSince1970),
                    .double(mergedEvent.endedAt.timeIntervalSince1970),
                    .text(mergedEvent.bundleId),
                    .text(mergedEvent.appName),
                    .text(mergedEvent.windowTitle),
                    mergedEvent.url.map(SQLiteValue.text) ?? .null,
                    .text(mergedEvent.visibleText),
                    .text(mergedEvent.source),
                    .text(mergedEvent.contentHash),
                    .integer(mergedEvent.isExcluded ? 1 : 0),
                ]
            )
            try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(mergedEvent.id)])
            try execute(
                """
                INSERT INTO activity_events_fts (id, app_name, window_title, url, visible_text)
                VALUES (?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(mergedEvent.id),
                    .text(mergedEvent.appName),
                    .text(mergedEvent.windowTitle),
                    mergedEvent.url.map(SQLiteValue.text) ?? .text(""),
                    .text(mergedEvent.visibleText),
                ]
            )

            return mergedEvent
        }
    }

    public func loadActivityEvents(in range: ClosedRange<Date>, includeExcluded: Bool = false) throws -> [ActivityEvent] {
        let sql = """
        SELECT * FROM activity_events
        WHERE started_at <= ? AND ended_at >= ?
        \(includeExcluded ? "" : "AND is_excluded = 0")
        ORDER BY started_at ASC;
        """
        return try query(
            sql,
            bindings: [
                .double(range.upperBound.timeIntervalSince1970),
                .double(range.lowerBound.timeIntervalSince1970),
            ]
        ).map(ActivityEvent.init(row:))
    }

    public func searchActivityEvents(
        query searchTerm: String,
        in range: ClosedRange<Date>,
        appFilters: [String],
        topK: Int
    ) throws -> [ActivityEvent] {
        guard let ftsQuery = makeFTSQuery(from: searchTerm) else {
            return []
        }

        var sql = """
        SELECT activity_events.*
        FROM activity_events
        JOIN activity_events_fts ON activity_events.id = activity_events_fts.id
        WHERE activity_events_fts MATCH ?
        AND activity_events.started_at <= ?
        AND activity_events.ended_at >= ?
        AND activity_events.is_excluded = 0
        """
        var bindings: [SQLiteValue] = [
            .text(ftsQuery),
            .double(range.upperBound.timeIntervalSince1970),
            .double(range.lowerBound.timeIntervalSince1970),
        ]
        if appFilters.isEmpty == false {
            sql += " AND activity_events.bundle_id IN (\(Array(repeating: "?", count: appFilters.count).joined(separator: ",")))"
            bindings += appFilters.map(SQLiteValue.text)
        }
        sql += " ORDER BY activity_events.started_at DESC LIMIT ?;"
        bindings.append(.integer(Int64(topK)))
        return try query(sql, bindings: bindings).map(ActivityEvent.init(row:))
    }

    public func saveJournal(_ journal: DailyJournal) throws {
        let sections = try encode(journal.sections)
        try execute(
            """
            INSERT OR REPLACE INTO daily_journals
            (id, day, markdown, sections_json, provider_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(journal.id),
                .text(journal.day),
                .text(journal.markdown),
                .text(sections),
                journal.providerID.map(SQLiteValue.text) ?? .null,
                .double(journal.createdAt.timeIntervalSince1970),
                .double(journal.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadJournal(for day: String) throws -> DailyJournal? {
        try query("SELECT * FROM daily_journals WHERE day = ? LIMIT 1;", bindings: [.text(day)]).first.flatMap {
            DailyJournal(row: $0, database: self)
        }
    }

    public func saveThread(_ thread: ChatThread) throws {
        try execute(
            """
            INSERT OR REPLACE INTO chat_threads (id, title, start_day, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(thread.id),
                .text(thread.title),
                .text(thread.startDay),
                .double(thread.createdAt.timeIntervalSince1970),
                .double(thread.updatedAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadThreads() throws -> [ChatThread] {
        try query("SELECT * FROM chat_threads ORDER BY updated_at DESC;").map { row in
            ChatThread(
                id: row.stringValue(for: "id"),
                title: row.stringValue(for: "title"),
                startDay: row.stringValue(for: "start_day"),
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
                updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
            )
        }
    }

    public func saveMessage(_ message: ChatMessage) throws {
        let citations = try encode(message.citations)
        try execute(
            """
            INSERT OR REPLACE INTO chat_messages (id, thread_id, role, content, citations_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(message.id),
                .text(message.threadID),
                .text(message.role.rawValue),
                .text(message.content),
                .text(citations),
                .double(message.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func loadMessages(threadID: String) throws -> [ChatMessage] {
        try query(
            "SELECT * FROM chat_messages WHERE thread_id = ? ORDER BY created_at ASC;",
            bindings: [.text(threadID)]
        ).map { row in
            ChatMessage(
                id: row.stringValue(for: "id"),
                threadID: row.stringValue(for: "thread_id"),
                role: ChatRole(rawValue: row.stringValue(for: "role")) ?? .assistant,
                content: row.stringValue(for: "content"),
                citations: (try? decode([Citation].self, from: row.stringValue(for: "citations_json"))) ?? [],
                createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at"))
            )
        }
    }

    public func deleteEvents(since date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        let rows = try query(
            "SELECT id FROM activity_events WHERE ended_at >= ?;",
            bindings: [.double(timestamp)]
        )
        for row in rows {
            let eventID = row.stringValue(for: "id")
            try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(eventID)])
            try execute("DELETE FROM embedding_chunks WHERE event_id = ?;", bindings: [.text(eventID)])
        }
        try execute("DELETE FROM activity_events WHERE ended_at >= ?;", bindings: [.double(timestamp)])
    }

    public func deleteEvents(since date: Date, affectedDays: Set<String>) throws {
        try deleteEvents(since: date)
        try deleteJournalsAndChats(for: affectedDays)
    }

    public func deleteEventsBefore(_ date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        let rows = try query(
            "SELECT id FROM activity_events WHERE ended_at < ?;",
            bindings: [.double(timestamp)]
        )
        for row in rows {
            let eventID = row.stringValue(for: "id")
            try execute("DELETE FROM activity_events_fts WHERE id = ?;", bindings: [.text(eventID)])
            try execute("DELETE FROM embedding_chunks WHERE event_id = ?;", bindings: [.text(eventID)])
        }
        try execute("DELETE FROM activity_events WHERE ended_at < ?;", bindings: [.double(timestamp)])
    }

    public func deleteAllEvents() throws {
        try execute("DELETE FROM activity_events_fts;")
        try execute("DELETE FROM activity_events;")
        try execute("DELETE FROM daily_journals;")
        try execute("DELETE FROM embedding_chunks;")
        try execute("DELETE FROM chat_messages;")
        try execute("DELETE FROM chat_threads;")
    }

    func deleteJournalsAndChatsBefore(day: String) throws {
        let threads = try query(
            "SELECT id FROM chat_threads WHERE start_day < ?;",
            bindings: [.text(day)]
        )
        for thread in threads {
            if case .text(let threadID) = thread["id"] {
                try execute("DELETE FROM chat_messages WHERE thread_id = ?;", bindings: [.text(threadID)])
                try execute("DELETE FROM chat_threads WHERE id = ?;", bindings: [.text(threadID)])
            }
        }
        try execute("DELETE FROM daily_journals WHERE day < ?;", bindings: [.text(day)])
    }

    func deletePreparedActivityEventsBefore(day: String) throws {
        try execute("DELETE FROM prepared_activity_days WHERE day < ?;", bindings: [.text(day)])
    }

    func deleteJournalsAndChats(for days: Set<String>) throws {
        for day in days {
            try execute("DELETE FROM daily_journals WHERE day = ?;", bindings: [.text(day)])
            let threads = try query(
                "SELECT id FROM chat_threads WHERE start_day = ?;",
                bindings: [.text(day)]
            )
            for thread in threads {
                let threadID = thread.stringValue(for: "id")
                try execute("DELETE FROM chat_messages WHERE thread_id = ?;", bindings: [.text(threadID)])
                try execute("DELETE FROM chat_threads WHERE id = ?;", bindings: [.text(threadID)])
            }
        }
    }

    public func saveEmbeddingChunk(id: String, eventID: String, providerID: String, model: String, vector: [Double], snippet: String) throws {
        let vectorString = try encode(vector)
        try execute(
            """
            INSERT OR REPLACE INTO embedding_chunks (id, event_id, provider_id, model, vector_json, snippet, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(id),
                .text(eventID),
                .text(providerID),
                .text(model),
                .text(vectorString),
                .text(snippet),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    public func loadEmbeddingChunks(providerID: String, model: String) throws -> [(eventID: String, vector: [Double], snippet: String)] {
        try query(
            "SELECT event_id, vector_json, snippet FROM embedding_chunks WHERE provider_id = ? AND model = ?;",
            bindings: [.text(providerID), .text(model)]
        ).compactMap { row in
            guard let vector = try? decode([Double].self, from: row.stringValue(for: "vector_json")) else { return nil }
            return (row.stringValue(for: "event_id"), vector, row.stringValue(for: "snippet"))
        }
    }

    public func loadActivityChunks(for day: String) throws -> [ActivityChunk] {
        try query(
            "SELECT * FROM activity_chunks WHERE day = ? ORDER BY started_at ASC;",
            bindings: [.text(day)]
        ).compactMap { row in
            ActivityChunk(row: row, database: self)
        }
    }

    public func searchActivityChunks(
        query searchTerm: String,
        in range: ClosedRange<Date>,
        appFilters: [String],
        topK: Int
    ) throws -> [ActivityChunk] {
        guard let ftsQuery = makeFTSQuery(from: searchTerm) else {
            return []
        }

        var sql = """
        SELECT activity_chunks.*
        FROM activity_chunks
        JOIN activity_chunks_fts ON activity_chunks.id = activity_chunks_fts.id
        WHERE activity_chunks_fts MATCH ?
        AND activity_chunks.started_at <= ?
        AND activity_chunks.ended_at >= ?
        AND activity_chunks.is_excluded = 0
        """
        var bindings: [SQLiteValue] = [
            .text(ftsQuery),
            .double(range.upperBound.timeIntervalSince1970),
            .double(range.lowerBound.timeIntervalSince1970),
        ]

        if appFilters.isEmpty == false {
            sql += " AND activity_chunks.bundle_id IN (\(Array(repeating: "?", count: appFilters.count).joined(separator: ",")))"
            bindings += appFilters.map(SQLiteValue.text)
        }

        sql += " ORDER BY bm25(activity_chunks_fts), activity_chunks.started_at DESC LIMIT ?;"
        bindings.append(.integer(Int64(topK)))

        return try query(sql, bindings: bindings).compactMap { row in
            ActivityChunk(row: row, database: self)
        }
    }

    public func saveActivityChunks(_ chunks: [ActivityChunk], for day: String) throws {
        try withImmediateTransaction {
            try execute(
                "DELETE FROM activity_chunks_fts WHERE id IN (SELECT id FROM activity_chunks WHERE day = ?);",
                bindings: [.text(day)]
            )
            try execute("DELETE FROM activity_chunks WHERE day = ?;", bindings: [.text(day)])

            for chunk in chunks {
                let sourceEventIDs = try encode(chunk.sourceEventIDs)
                try execute(
                    """
                    INSERT INTO activity_chunks
                    (id, day, started_at, ended_at, bundle_id, app_name, title, url, excerpt, is_excluded, source_event_ids_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(chunk.id),
                        .text(chunk.day),
                        .double(chunk.startedAt.timeIntervalSince1970),
                        .double(chunk.endedAt.timeIntervalSince1970),
                        .text(chunk.bundleId),
                        .text(chunk.appName),
                        .text(chunk.title),
                        chunk.url.map(SQLiteValue.text) ?? .null,
                        .text(chunk.excerpt),
                        .integer(chunk.isExcluded ? 1 : 0),
                        .text(sourceEventIDs),
                    ]
                )
                try execute(
                    """
                    INSERT INTO activity_chunks_fts (id, app_name, title, url, excerpt)
                    VALUES (?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(chunk.id),
                        .text(chunk.appName),
                        .text(chunk.title),
                        chunk.url.map(SQLiteValue.text) ?? .text(""),
                        .text(chunk.excerpt),
                    ]
                )
            }
        }
    }

    public func loadPreparedActivityEvents(for day: String) throws -> [GroupedActivityEvent]? {
        guard let row = try query(
            "SELECT grouped_events_json FROM prepared_activity_days WHERE day = ? LIMIT 1;",
            bindings: [.text(day)]
        ).first,
        let payload = row.optionalStringValue(for: "grouped_events_json")
        else {
            return nil
        }

        return try decode([GroupedActivityEvent].self, from: payload)
    }

    public func savePreparedActivityEvents(_ events: [GroupedActivityEvent], for day: String) throws {
        let payload = try encode(events)
        try execute(
            """
            INSERT INTO prepared_activity_days (day, grouped_events_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(day) DO UPDATE
            SET grouped_events_json = excluded.grouped_events_json,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(day),
                .text(payload),
                .double(Date().timeIntervalSince1970),
            ]
        )
    }

    public func deletePreparedActivityEvents(for days: Set<String>) throws {
        guard days.isEmpty == false else {
            return
        }

        let placeholders = Array(repeating: "?", count: days.count).joined(separator: ",")
        let sql = "DELETE FROM prepared_activity_days WHERE day IN (\(placeholders));"
        try execute(sql, bindings: days.sorted().map(SQLiteValue.text))
    }

    public func deleteAllPreparedActivityEvents() throws {
        try execute("DELETE FROM prepared_activity_days;")
    }

    public func deleteActivityChunks(for days: Set<String>) throws {
        guard days.isEmpty == false else {
            return
        }

        let placeholders = Array(repeating: "?", count: days.count).joined(separator: ",")
        let bindings = days.sorted().map(SQLiteValue.text)
        try execute(
            "DELETE FROM activity_chunks_fts WHERE id IN (SELECT id FROM activity_chunks WHERE day IN (\(placeholders)));",
            bindings: bindings
        )
        try execute("DELETE FROM activity_chunks WHERE day IN (\(placeholders));", bindings: bindings)
    }

    public func deleteActivityChunksBefore(day: String) throws {
        try execute(
            "DELETE FROM activity_chunks_fts WHERE id IN (SELECT id FROM activity_chunks WHERE day < ?);",
            bindings: [.text(day)]
        )
        try execute("DELETE FROM activity_chunks WHERE day < ?;", bindings: [.text(day)])
    }

    public func deleteAllActivityChunks() throws {
        try execute("DELETE FROM activity_chunks_fts;")
        try execute("DELETE FROM activity_chunks;")
    }

    private func migrate() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                window_title TEXT NOT NULL,
                url TEXT,
                visible_text TEXT NOT NULL,
                source TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                is_excluded INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_activity_events_day
            ON activity_events(started_at, ended_at, is_excluded);
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS activity_events_fts
            USING fts5(id UNINDEXED, app_name, window_title, url, visible_text, tokenize='unicode61');
            """,
            """
            CREATE TABLE IF NOT EXISTS provider_configs (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                base_url TEXT NOT NULL,
                api_key TEXT NOT NULL,
                chat_model TEXT NOT NULL,
                embedding_model TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                headers_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS exclusions (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                pattern TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS daily_journals (
                id TEXT PRIMARY KEY,
                day TEXT UNIQUE NOT NULL,
                markdown TEXT NOT NULL,
                sections_json TEXT NOT NULL,
                provider_id TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_threads (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                start_day TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY,
                thread_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                citations_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS embedding_chunks (
                id TEXT PRIMARY KEY,
                event_id TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                model TEXT NOT NULL,
                vector_json TEXT NOT NULL,
                snippet TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS prepared_activity_days (
                day TEXT PRIMARY KEY,
                grouped_events_json TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS activity_chunks (
                id TEXT PRIMARY KEY,
                day TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                title TEXT NOT NULL,
                url TEXT,
                excerpt TEXT NOT NULL,
                is_excluded INTEGER NOT NULL DEFAULT 0,
                source_event_ids_json TEXT NOT NULL
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_activity_chunks_day
            ON activity_chunks(day, started_at, is_excluded);
            """,
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS activity_chunks_fts
            USING fts5(id UNINDEXED, app_name, title, url, excerpt, tokenize='unicode61');
            """,
        ]

        for statement in statements {
            try execute(statement)
        }
    }

    private func seedDefaultsIfNeeded() throws {
        let countRows = try query("SELECT COUNT(*) AS value FROM provider_configs;")
        let count = countRows.first?.intValue(for: "value") ?? 0
        guard count == 0 else { return }
        try saveProviderConfig(.defaultPreset(for: .ollama))
        try saveProviderConfig(.defaultPreset(for: .openAICompatible))
        try saveSettings(AppSettings())
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(lastErrorMessage())
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let parameter = Int32(index + 1)
            let result: Int32
            switch value {
            case .integer(let value):
                result = sqlite3_bind_int64(statement, parameter, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, parameter, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, parameter, value, -1, sqliteTransient)
            case .null:
                result = sqlite3_bind_null(statement, parameter)
            }
            guard result == SQLITE_OK else {
                throw SQLiteError.bind(lastErrorMessage())
            }
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func withImmediateTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func normalizeOptionalSetting(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    private func mergeActivityEvent(_ event: ActivityEvent, with duplicates: [ActivityEvent]) -> ActivityEvent {
        guard let canonical = duplicates.first else {
            return event
        }

        var merged = canonical
        let overlappingEvents = duplicates + [event]
        merged.startedAt = overlappingEvents.map(\.startedAt).min() ?? canonical.startedAt
        merged.endedAt = overlappingEvents.map(\.endedAt).max() ?? canonical.endedAt
        if overlappingEvents.contains(where: { $0.source == "accessibility" }) {
            merged.source = "accessibility"
        }
        return merged
    }

    private func makeFTSQuery(from rawQuery: String) -> String? {
        let tokens = rawQuery
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }

        guard tokens.isEmpty == false else { return nil }
        return tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " OR ")
    }
}

private extension ActivityEvent {
    init(row: [String: SQLiteValue]) {
        self.init(
            id: row.stringValue(for: "id"),
            startedAt: Date(timeIntervalSince1970: row.doubleValue(for: "started_at")),
            endedAt: Date(timeIntervalSince1970: row.doubleValue(for: "ended_at")),
            bundleId: row.stringValue(for: "bundle_id"),
            appName: row.stringValue(for: "app_name"),
            windowTitle: row.stringValue(for: "window_title"),
            url: row.optionalStringValue(for: "url"),
            visibleText: row.stringValue(for: "visible_text"),
            source: row.stringValue(for: "source"),
            contentHash: row.stringValue(for: "content_hash"),
            isExcluded: row.intValue(for: "is_excluded") == 1
        )
    }
}

private extension DailyJournal {
    init?(row: [String: SQLiteValue], database: SQLiteDatabase) {
        guard let sectionsJSON = row.optionalStringValue(for: "sections_json"),
              let sections = try? database.decode([JournalSection].self, from: sectionsJSON)
        else {
            return nil
        }
        self.init(
            id: row.stringValue(for: "id"),
            day: row.stringValue(for: "day"),
            markdown: row.stringValue(for: "markdown"),
            sections: sections,
            providerID: row.optionalStringValue(for: "provider_id"),
            createdAt: Date(timeIntervalSince1970: row.doubleValue(for: "created_at")),
            updatedAt: Date(timeIntervalSince1970: row.doubleValue(for: "updated_at"))
        )
    }
}

private extension ActivityChunk {
    init?(row: [String: SQLiteValue], database: SQLiteDatabase) {
        guard let sourceEventIDsJSON = row.optionalStringValue(for: "source_event_ids_json"),
              let sourceEventIDs = try? database.decode([String].self, from: sourceEventIDsJSON)
        else {
            return nil
        }

        self.init(
            id: row.stringValue(for: "id"),
            day: row.stringValue(for: "day"),
            startedAt: Date(timeIntervalSince1970: row.doubleValue(for: "started_at")),
            endedAt: Date(timeIntervalSince1970: row.doubleValue(for: "ended_at")),
            bundleId: row.stringValue(for: "bundle_id"),
            appName: row.stringValue(for: "app_name"),
            title: row.stringValue(for: "title"),
            url: row.optionalStringValue(for: "url"),
            excerpt: row.stringValue(for: "excerpt"),
            isExcluded: row.intValue(for: "is_excluded") == 1,
            sourceEventIDs: sourceEventIDs
        )
    }
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func stringValue(for key: String) -> String {
        switch self[key] {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .null, .none:
            return ""
        }
    }

    func optionalStringValue(for key: String) -> String? {
        let value = stringValue(for: key)
        return value.isEmpty ? nil : value
    }

    func intValue(for key: String) -> Int {
        switch self[key] {
        case .integer(let value):
            return Int(value)
        case .double(let value):
            return Int(value)
        case .text(let value):
            return Int(value) ?? 0
        case .null, .none:
            return 0
        }
    }

    func doubleValue(for key: String) -> TimeInterval {
        switch self[key] {
        case .integer(let value):
            return TimeInterval(value)
        case .double(let value):
            return TimeInterval(value)
        case .text(let value):
            return TimeInterval(value) ?? 0
        case .null, .none:
            return 0
        }
    }
}
