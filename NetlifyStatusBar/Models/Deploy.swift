// NetlifyStatusBar/Models/Deploy.swift
import Foundation

struct Deploy: Identifiable, Equatable {
    let id: String
    let siteId: String
    let state: DeployState
    let branch: String
    let createdAt: Date
    let deployedAt: Date?
    let commitRef: String?   // git commit SHA of the deployed commit

    init(
        id: String,
        siteId: String,
        state: DeployState,
        branch: String,
        createdAt: Date,
        deployedAt: Date?,
        commitRef: String? = nil
    ) {
        self.id = id
        self.siteId = siteId
        self.state = state
        self.branch = branch
        self.createdAt = createdAt
        self.deployedAt = deployedAt
        self.commitRef = commitRef
    }
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
