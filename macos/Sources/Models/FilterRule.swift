import Foundation

enum FilterType: String, Codable, CaseIterable {
    case sender
    case content
}

struct FilterRule: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var enabled: Bool = true
    var type: FilterType = .sender
    var value: String = ""
}

struct FilterPreset {
    let name: String
    let filters: [FilterRule]

    static let otp = FilterPreset(
        name: "OTP / Verification",
        filters: [
            FilterRule(type: .content, value: "*OTP*"),
            FilterRule(type: .content, value: "*code*"),
            FilterRule(type: .content, value: "*verify*"),
            FilterRule(type: .content, value: "*token*")
        ]
    )

    static let banking = FilterPreset(
        name: "Banking",
        filters: [
            FilterRule(type: .sender, value: "*Bank*"),
            FilterRule(type: .content, value: "*transaction*")
        ]
    )

    static let all: [FilterPreset] = [otp, banking]
}
