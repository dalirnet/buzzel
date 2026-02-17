import AppKit
import CoreImage

enum QRGenerator {

  static func generateQrPayload(prefer: String) -> (payload: Data, seed: Data)? {
    var seed = Data(count: 16)
    let result = seed.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
    }
    guard result == errSecSuccess else { return nil }

    guard let host = localIPAddress() else { return nil }
    let payload = BuzzelProtocol.generateQrPayload(seed: seed, host: host, prefer: prefer)
    return (payload, seed)
  }

  static func generateQRMatrix(from data: Data) -> [[Bool]]? {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")

    guard let ciImage = filter.outputImage else { return nil }

    let extent = ciImage.extent
    let width = Int(extent.width)
    let height = Int(extent.height)

    let rep = NSBitmapImageRep(ciImage: ciImage)
    var matrix = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)

    for y in 0..<height {
      for x in 0..<width {
        let color = rep.colorAt(x: x, y: y)
        let brightness = color?.brightnessComponent ?? 1.0
        matrix[y][x] = brightness < 0.5
      }
    }
    return matrix
  }

  static func localIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let iface = ptr.pointee
      guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

      let name = String(cString: iface.ifa_name)
      guard name == "en0" || name == "en1" else { continue }

      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(
        iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len),
        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
      address = String(cString: hostname)
      if name == "en0" { break }
    }
    return address
  }
}
