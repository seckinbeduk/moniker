import Foundation

/// Which model names files.
public enum Engine: String, Sendable, CaseIterable, Codable {
    /// Hearth when it's running (github.com/seckinbeduk/hearth), Apple Intelligence directly otherwise.
    case auto
    /// Apple Intelligence directly, never Hearth.
    case apple
    /// Hearth only.
    case hearth
}
