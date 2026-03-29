// NetlifyStatusBar/Models/Deploy.swift
import Foundation

struct Deploy: Identifiable, Equatable {
    let id: String
    let siteId: String
    let state: DeployState
    let branch: String
    let createdAt: Date
    let deployedAt: Date?
}

enum DeployState: String, Equatable {
    case enqueued, building, processing, ready, error, cancelled, unknown

    var isActive: Bool {
        self == .building || self == .enqueued || self == .processing
    }

    /// Safe init from raw API string — falls back to .unknown
    init(apiString: String) {
        self = DeployState(rawValue: apiString) ?? .unknown
    }
}
