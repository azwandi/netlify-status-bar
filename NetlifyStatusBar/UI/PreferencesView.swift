// NetlifyStatusBar/UI/PreferencesView.swift
import SwiftUI

struct PreferencesView: View {
    @Environment(DeployMonitor.self) private var monitor
    @State private var token: String = ""
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Netlify Status Bar")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal Access Token")
                    .font(.system(size: 12, weight: .medium))
                SecureField("paste token here…", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Generate one at: app.netlify.com/user/applications")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Connection status feedback
            switch connectionStatus {
            case .idle:
                EmptyView()
            case .testing:
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Testing connection…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .success(let user):
                Label("Connected as \(user)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(token.isEmpty)

                Spacer()

                Button("Save") {
                    Task { await save() }
                }
                .disabled(token.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            token = (try? KeychainHelper.read()) ?? ""
        }
    }

    private func testConnection() async {
        connectionStatus = .testing
        let client = NetlifyClient(token: token)
        do {
            let user = try await client.fetchCurrentUser()
            connectionStatus = .success(user.email)
        } catch NetlifyError.unauthorized {
            connectionStatus = .failure("Invalid token")
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }

    private func save() async {
        connectionStatus = .testing
        let client = NetlifyClient(token: token)
        do {
            let user = try await client.fetchCurrentUser()
            connectionStatus = .success(user.email)
            try KeychainHelper.save(token)
            NotificationManager.shared.requestPermission()
            monitor.restart(withToken: token)
        } catch NetlifyError.unauthorized {
            connectionStatus = .failure("Invalid token — not saved")
        } catch {
            connectionStatus = .failure("Save failed: \(error.localizedDescription)")
        }
    }
}
