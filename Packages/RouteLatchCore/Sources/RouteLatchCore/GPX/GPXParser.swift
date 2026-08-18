import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct GPXParser: Sendable {
    public static let defaultMaximumPointCount = 100_000
    public let maximumPointCount: Int

    public init(maximumPointCount: Int = Self.defaultMaximumPointCount) {
        self.maximumPointCount = maximumPointCount
    }

    public func parse(url: URL) throws -> Route {
        guard let parser = XMLParser(contentsOf: url) else { throw GPXError.unreadableFile }
        let delegate = GPXDelegate(maximumPointCount: maximumPointCount)
        parser.delegate = delegate
        let parsed = parser.parse()
        if let error = delegate.failure { throw error }
        guard parsed else { throw GPXError.malformedXML(parser.parserError?.localizedDescription ?? "Unknown XML error") }
        return try delegate.makeRoute(filename: url.lastPathComponent, fingerprint: try fingerprint(url: url))
    }

    public func parse(data: Data, filename: String = "Imported.gpx") throws -> Route {
        let parser = XMLParser(data: data)
        let delegate = GPXDelegate(maximumPointCount: maximumPointCount)
        parser.delegate = delegate
        let parsed = parser.parse()
        if let error = delegate.failure { throw error }
        guard parsed else { throw GPXError.malformedXML(parser.parserError?.localizedDescription ?? "Unknown XML error") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try delegate.makeRoute(filename: filename, fingerprint: digest)
    }

    private func fingerprint(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum GPXError: Error, LocalizedError, Equatable, Sendable {
    case unreadableFile
    case malformedXML(String)
    case missingCoordinate
    case invalidCoordinate
    case emptyRoute
    case tooManyPoints(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile: "The GPX file could not be read."
        case .malformedXML: "The GPX XML is malformed."
        case .missingCoordinate: "A route point is missing latitude or longitude."
        case .invalidCoordinate: "A route point contains an invalid coordinate."
        case .emptyRoute: "The GPX file contains no track or route points."
        case .tooManyPoints(let maximum): "This route exceeds the \(maximum)-point safety limit."
        }
    }
}

private final class GPXDelegate: NSObject, XMLParserDelegate {
    private let maximumPointCount: Int
    private var elementStack: [String] = []
    private var text = ""
    private var routeName: String?
    private var segments: [[RoutePoint]] = []
    private var currentSegment: [RoutePoint]?
    private var routeSegment: [RoutePoint] = []
    private var pointDraft: (latitude: Double, longitude: Double, elevation: Double?, timestamp: Date?)?
    private var pointCount = 0
    var failure: GPXError?

    init(maximumPointCount: Int) { self.maximumPointCount = maximumPointCount }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = normalized(elementName)
        elementStack.append(name)
        text = ""
        if name == "trkseg" { currentSegment = [] }
        if name == "trkpt" || name == "rtept" {
            guard let latText = attributeDict["lat"], let lonText = attributeDict["lon"] else { return abort(.missingCoordinate, parser) }
            guard let lat = Double(latText), let lon = Double(lonText), lat.isFinite, lon.isFinite,
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return abort(.invalidCoordinate, parser) }
            pointDraft = (lat, lon, nil, nil)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalized(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "name", elementStack.dropLast().last.map({ $0 == "trk" || $0 == "rte" || $0 == "gpx" }) == true, routeName == nil, !value.isEmpty {
            routeName = value
        } else if name == "ele", var draft = pointDraft { draft.elevation = Double(value); pointDraft = draft
        } else if name == "time", var draft = pointDraft { draft.timestamp = Self.parseDate(value); pointDraft = draft
        } else if name == "trkpt" || name == "rtept" {
            if let draft = pointDraft, let point = try? RoutePoint(latitude: draft.latitude, longitude: draft.longitude, elevation: draft.elevation, timestamp: draft.timestamp) {
                if name == "trkpt" { currentSegment?.append(point) } else { routeSegment.append(point) }
                pointCount += 1
                if pointCount > maximumPointCount { abort(.tooManyPoints(maximumPointCount), parser) }
            }
            pointDraft = nil
        } else if name == "trkseg", let segment = currentSegment {
            if !segment.isEmpty { segments.append(segment) }
            currentSegment = nil
        } else if name == "rte", !routeSegment.isEmpty {
            segments.append(routeSegment)
            routeSegment = []
        }
        if !elementStack.isEmpty { elementStack.removeLast() }
        text = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = .malformedXML(parseError.localizedDescription) }
    }

    func makeRoute(filename: String, fingerprint: String) throws -> Route {
        if !routeSegment.isEmpty { segments.append(routeSegment) }
        guard !segments.isEmpty else { throw GPXError.emptyRoute }
        let fallback = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return try Route(name: routeName ?? fallback, originalFilename: filename, segments: segments.map(RouteSegment.init), sourceFingerprint: fingerprint)
    }

    private func abort(_ error: GPXError, _ parser: XMLParser) { failure = error; parser.abortParsing() }
    private func normalized(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
    private static func parseDate(_ text: String) -> Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: text) { return date }
        standard.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return standard.date(from: text)
    }
}
