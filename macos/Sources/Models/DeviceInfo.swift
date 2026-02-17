import Foundation

struct DeviceInfo: Codable, Equatable {
  var name: String
  var address: String
  var peripheralIdentifier: String?
}
