// NetlifyStatusBar/Models/Site.swift
import Foundation

struct Site: Identifiable, Equatable {
    let id: String
    let name: String        // slug, e.g. "my-portfolio"
    let adminURL: URL       // https://app.netlify.com/sites/<name>
}
