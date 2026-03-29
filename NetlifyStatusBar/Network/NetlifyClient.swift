// NetlifyStatusBar/Network/NetlifyClient.swift
import Foundation

enum NetlifyError: Error, Equatable {
    case unauthorized
    case rateLimited
    case networkError(String)
    case decodingError(String)
}

actor NetlifyClient {
    private let token: String
    let session: URLSession
    private let baseURL = URL(string: "https://api.netlify.com")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Core request

    func request<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw NetlifyError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetlifyError.networkError("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299: break
        case 401: throw NetlifyError.unauthorized
        case 429: throw NetlifyError.rateLimited
        default: throw NetlifyError.networkError("HTTP \(http.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetlifyError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - User endpoint

    func fetchCurrentUser() async throws -> NetlifyUser {
        try await request("api/v1/user")
    }

    // MARK: - Sites

    func fetchAllSites(perPage: Int = 100) async throws -> [Site] {
        var all: [Site] = []
        var page = 1
        while true {
            let batch: [APISite] = try await request(
                "api/v1/sites",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "\(perPage)"),
                    URLQueryItem(name: "page", value: "\(page)")
                ]
            )
            all += batch.map { $0.toSite() }
            if batch.count < perPage { break }
            page += 1
        }
        return all
    }
}

// MARK: - API response types

struct NetlifyUser: Decodable {
    let id: String
    let email: String
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
    }
}

private struct APISite: Decodable {
    let id: String
    let name: String

    func toSite() -> Site {
        Site(
            id: id,
            name: name,
            adminURL: URL(string: "https://app.netlify.com/sites/\(name)")!
        )
    }
}
