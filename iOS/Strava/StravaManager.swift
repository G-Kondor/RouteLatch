import Foundation
import OSLog
import RouteLatchCore
import Security
import UIKit

private let stravaLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RouteLatch", category: "Strava")

enum StravaRunStatus: Equatable {
    case waitingForWatch
    case ready
    case uploading
    case processing
    case uploaded(Int64)
    case notEligible(String)
    case failed(String)

    var label: String {
        switch self {
        case .waitingForWatch: "Waiting for iPhone"
        case .ready: "Ready for Strava"
        case .uploading: "Uploading to Strava…"
        case .processing: "Strava is processing — tap to check"
        case .uploaded: "Uploaded to Strava"
        case .notEligible(let message): "Not eligible for Strava: \(message)"
        case .failed(let message): "Strava error: \(message)"
        }
    }
}

private struct StravaConfiguration {
    let clientID: String
    let tokenBrokerURL: URL
    let callbackURL = URL(string: "routelatch://routelatch.app/strava-auth")!

    static func load(bundle: Bundle = .main) -> StravaConfiguration? {
        guard let clientID = bundle.object(forInfoDictionaryKey: "StravaClientID") as? String,
              !clientID.isEmpty, !clientID.contains("$("), Int(clientID) != nil,
              let brokerString = bundle.object(forInfoDictionaryKey: "StravaTokenBrokerURL") as? String,
              !brokerString.isEmpty, !brokerString.contains("$("),
              let brokerURL = URL(string: brokerString), brokerURL.scheme == "https" else { return nil }
        return .init(clientID: clientID, tokenBrokerURL: brokerURL)
    }
}

private struct StravaCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let athleteName: String?
}

private struct StravaAthlete: Decodable {
    let firstname: String?
    let lastname: String?
}

private struct StravaTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let athlete: StravaAthlete?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

private struct StravaUploadResponse: Decodable {
    let id: Int64
    let error: String?
    let status: String?
    let activityID: Int64?

    private enum CodingKeys: String, CodingKey {
        case id
        case error
        case status
        case activityID = "activity_id"
    }
}

@MainActor
final class StravaManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var athleteName: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var statuses: [UUID: StravaRunStatus] = [:]
    @Published var errorMessage: String?

    var isConfigured: Bool { configuration != nil }
    let runStore: RecordedRunFileStore

    private static let keychainAccount = "strava-oauth"
    private static let legacyAutoUploadKey = "Strava.AutoUploadEnabled"
    private static let uploadedReceiptsKey = "Strava.UploadedReceipts"
    private static let pendingUploadsKey = "Strava.PendingUploads"
    private let configuration = StravaConfiguration.load()
    private var credentials: StravaCredentials?
    private var authorizationState: String?
    private var uploadedReceipts: [String: Int64]
    private var pendingUploadIDs: [String: Int64]
    private var uploadingRunIDs: Set<UUID> = []

    init(runStore: RecordedRunFileStore) {
        self.runStore = runStore
        UserDefaults.standard.removeObject(forKey: Self.legacyAutoUploadKey)
        uploadedReceipts = Self.loadMap(forKey: Self.uploadedReceiptsKey)
        pendingUploadIDs = Self.loadMap(forKey: Self.pendingUploadsKey)
        credentials = try? KeychainStore.load(StravaCredentials.self, account: Self.keychainAccount)
        isConnected = credentials != nil
        athleteName = credentials?.athleteName
        refreshStatuses(for: runStore.loadAll().runs)
    }

    func connect() {
        guard let configuration else {
            errorMessage = "Strava is not configured yet. Add STRAVA_CLIENT_ID and STRAVA_TOKEN_BROKER_URL to the RouteLatch build settings."
            return
        }
        let state = UUID().uuidString
        authorizationState = state
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "redirect_uri", value: configuration.callbackURL.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: "activity:write"),
            .init(name: "state", value: state)
        ]
        guard let webURL = components.url else { return }
        let appURL = URL(string: webURL.absoluteString.replacingOccurrences(of: "https://www.strava.com", with: "strava:/"))
        isAuthenticating = true
        if let appURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme == "routelatch", url.host == "routelatch.app", url.path == "/strava-auth" else { return false }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value: (String) -> String? = { name in values.first(where: { $0.name == name })?.value }
        guard value("state") == authorizationState else {
            isAuthenticating = false
            errorMessage = "The Strava sign-in response could not be verified. Please try again."
            return true
        }
        authorizationState = nil
        if let error = value("error") {
            isAuthenticating = false
            errorMessage = error == "access_denied" ? "Strava access was not granted." : error
            return true
        }
        guard let code = value("code") else {
            isAuthenticating = false
            errorMessage = "Strava did not return an authorization code."
            return true
        }
        Task { await exchangeAuthorizationCode(code) }
        return true
    }

    func disconnect() {
        let refreshToken = credentials?.refreshToken
        credentials = nil
        try? KeychainStore.delete(account: Self.keychainAccount)
        isConnected = false
        athleteName = nil
        refreshStatuses(for: runStore.loadAll().runs)
        if let refreshToken { Task { try? await revoke(token: refreshToken) } }
    }

    func updateLocalStatuses(for runs: [RecordedRun]) {
        refreshStatuses(for: runs)
    }

    func upload(_ run: RecordedRun) async {
        guard uploadingRunIDs.isEmpty else {
            errorMessage = "Another manual Strava request is already in progress."
            return
        }
        if let message = Self.uploadEligibilityError(for: run) {
            pendingUploadIDs.removeValue(forKey: run.id.uuidString)
            saveMaps()
            statuses[run.id] = .notEligible(message)
            errorMessage = message
            return
        }
        guard isConnected else {
            statuses[run.id] = .ready
            errorMessage = "Connect RouteLatch to Strava before uploading."
            return
        }
        uploadingRunIDs.insert(run.id)
        defer { uploadingRunIDs.remove(run.id) }
        do {
            if let activityID = uploadedReceipts[run.id.uuidString] {
                statuses[run.id] = .uploaded(activityID)
                return
            }
            let uploadID: Int64
            if let existing = pendingUploadIDs[run.id.uuidString] {
                uploadID = existing
                statuses[run.id] = .processing
                if let activityID = try await checkUploadStatus(uploadID) {
                    markUploaded(run, activityID: activityID)
                }
            } else {
                statuses[run.id] = .uploading
                let upload = try await submit(run)
                uploadID = upload.id
                pendingUploadIDs[run.id.uuidString] = uploadID
                saveMaps()
                if let activityID = upload.activityID {
                    markUploaded(run, activityID: activityID)
                } else {
                    statuses[run.id] = .processing
                }
            }
        } catch {
            stravaLogger.error("Run upload failed: \(error.localizedDescription, privacy: .public)")
            statuses[run.id] = pendingUploadIDs[run.id.uuidString] == nil
                ? .failed(error.localizedDescription)
                : .processing
            errorMessage = error.localizedDescription
        }
    }

    func openUploadedActivity(for run: RecordedRun) {
        guard let activityID = uploadedReceipts[run.id.uuidString],
              let url = URL(string: "https://www.strava.com/activities/\(activityID)") else { return }
        UIApplication.shared.open(url)
    }

    private func exchangeAuthorizationCode(_ code: String) async {
        defer { isAuthenticating = false }
        do {
            guard let configuration else { throw StravaError.notConfigured }
            let response: StravaTokenResponse = try await brokerRequest([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": configuration.callbackURL.absoluteString
            ])
            let athleteName = [response.athlete?.firstname, response.athlete?.lastname]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let newCredentials = StravaCredentials(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date(timeIntervalSince1970: response.expiresAt),
                athleteName: athleteName.isEmpty ? nil : athleteName
            )
            try KeychainStore.save(newCredentials, account: Self.keychainAccount)
            credentials = newCredentials
            isConnected = true
            self.athleteName = newCredentials.athleteName
            updateLocalStatuses(for: runStore.loadAll().runs)
        } catch {
            stravaLogger.error("Strava authorization failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func validAccessToken() async throws -> String {
        guard var credentials else { throw StravaError.notConnected }
        if credentials.expiresAt.timeIntervalSinceNow > 600 { return credentials.accessToken }
        let response: StravaTokenResponse = try await brokerRequest([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken
        ])
        credentials = StravaCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt),
            athleteName: credentials.athleteName
        )
        try KeychainStore.save(credentials, account: Self.keychainAccount)
        self.credentials = credentials
        return credentials.accessToken
    }

    private func submit(_ run: RecordedRun) async throws -> StravaUploadResponse {
        let token = try await validAccessToken()
        let fileURL = runStore.tcxURL(for: run.id)
        if !FileManager.default.fileExists(atPath: fileURL.path) { try runStore.save(run) }
        let fileData = try Data(contentsOf: fileURL)
        let boundary = "RouteLatch-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormData(boundary: boundary)
            .field(name: "name", value: run.name)
            .field(name: "sport_type", value: "Run")
            .field(name: "data_type", value: "tcx")
            .field(name: "external_id", value: "routelatch-\(run.id.uuidString).tcx")
            .file(name: "file", filename: fileURL.lastPathComponent, mimeType: "application/vnd.garmin.tcx+xml", data: fileData)
            .encoded()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        let upload = try Self.decoder.decode(StravaUploadResponse.self, from: data)
        if let error = upload.error { throw StravaError.api(error) }
        return upload
    }

    private func checkUploadStatus(_ uploadID: Int64) async throws -> Int64? {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/uploads/\(uploadID)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        let upload = try Self.decoder.decode(StravaUploadResponse.self, from: data)
        if let error = upload.error { throw StravaError.api(error) }
        return upload.activityID
    }

    private func markUploaded(_ run: RecordedRun, activityID: Int64) {
        pendingUploadIDs.removeValue(forKey: run.id.uuidString)
        uploadedReceipts[run.id.uuidString] = activityID
        saveMaps()
        statuses[run.id] = .uploaded(activityID)
    }

    private func revoke(token: String) async throws {
        let _: EmptyBrokerResponse = try await brokerRequest(["action": "revoke", "token": token])
    }

    private func brokerRequest<Response: Decodable>(_ body: [String: String]) async throws -> Response {
        guard let configuration else { throw StravaError.notConfigured }
        var request = URLRequest(url: configuration.tokenBrokerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try Self.decoder.decode(Response.self, from: data)
    }

    private func refreshStatuses(for runs: [RecordedRun]) {
        let existingRunIDs = Set(runs.map { $0.id.uuidString })
        var removedInvalidPendingUpload = false
        let stalePendingUploadIDs = pendingUploadIDs.keys.filter { !existingRunIDs.contains($0) }
        for staleID in stalePendingUploadIDs {
            pendingUploadIDs.removeValue(forKey: staleID)
            removedInvalidPendingUpload = true
        }
        for run in runs {
            if let activityID = uploadedReceipts[run.id.uuidString] { statuses[run.id] = .uploaded(activityID) }
            else if let message = Self.uploadEligibilityError(for: run) {
                removedInvalidPendingUpload = pendingUploadIDs.removeValue(forKey: run.id.uuidString) != nil || removedInvalidPendingUpload
                statuses[run.id] = .notEligible(message)
            }
            else if pendingUploadIDs[run.id.uuidString] != nil { statuses[run.id] = .processing }
            else { statuses[run.id] = .ready }
        }
        if removedInvalidPendingUpload { saveMaps() }
    }

    private static func uploadEligibilityError(for run: RecordedRun) -> String? {
        guard run.points.count >= 2, run.distanceMeters > 0 else {
            return "The run has no measurable route. Record at least two GPS points and a non-zero distance."
        }
        guard run.activeDuration > 0 else {
            return "The run has no active duration."
        }
        return nil
    }

    private func saveMaps() {
        Self.saveMap(uploadedReceipts, forKey: Self.uploadedReceiptsKey)
        Self.saveMap(pendingUploadIDs, forKey: Self.pendingUploadsKey)
    }

    private static let decoder = JSONDecoder()

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw StravaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            if http.statusCode == 429 || message?.localizedCaseInsensitiveContains("rate limit") == true {
                throw StravaError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            }
            throw StravaError.api(message ?? "HTTP \(http.statusCode)")
        }
    }

    private static func loadMap(forKey key: String) -> [String: Int64] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Int64].self, from: data)) ?? [:]
    }

    private static func saveMap(_ map: [String: Int64], forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(map), forKey: key)
    }
}

private struct EmptyBrokerResponse: Decodable {}

private enum StravaError: Error, LocalizedError {
    case notConfigured
    case notConnected
    case invalidResponse
    case rateLimited(retryAfter: String?)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Strava is not configured for this build."
        case .notConnected: "RouteLatch is not connected to Strava."
        case .invalidResponse: "Strava returned an invalid response."
        case .rateLimited(let retryAfter):
            if let retryAfter, !retryAfter.isEmpty {
                "Strava rate limit reached. Try the manual action again after \(retryAfter) seconds."
            } else {
                "Strava rate limit reached. Wait a while, then try the manual action again."
            }
        case .api(let message): message
        }
    }
}

private enum KeychainStore {
    static func save<Value: Encodable>(_ value: Value, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "RouteLatch",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw StravaError.api("Keychain error \(status)") }
    }

    static func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "RouteLatch",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StravaError.api("Keychain error \(status)") }
        return try JSONDecoder().decode(type, from: data)
    }

    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "RouteLatch",
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StravaError.api("Keychain error \(status)") }
    }
}

private struct MultipartFormData {
    private let boundary: String
    private var parts: [Data] = []

    init(boundary: String) { self.boundary = boundary }

    func field(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        return copy
    }

    func file(name: String, filename: String, mimeType: String, data: Data) -> MultipartFormData {
        var copy = self
        copy.parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8) + data + Data("\r\n".utf8))
        return copy
    }

    func encoded() -> Data { parts.reduce(into: Data(), +=) + Data("--\(boundary)--\r\n".utf8) }
}
