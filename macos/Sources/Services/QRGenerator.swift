import AppKit
import CoreImage

enum QRGenerator {
    static func generateQRCodePayload(preferredTransport: String) -> (payload: Data, seed: Data)? {
        var seed = Data(count: 16)
        let result = seed.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard result == errSecSuccess else { return nil }

        guard let host = localIPAddress() else { return nil }
        let payload = BuzzelProtocol.generateQRCodePayload(
            seed: seed, host: host, preferredTransport: preferredTransport
        )
        return (payload, seed)
    }

    static func generateQRCodeMatrix(from data: Data) -> [[Bool]]? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let extent = ciImage.extent
        let width = Int(extent.width)
        let height = Int(extent.height)

        let bitmapRepresentation = NSBitmapImageRep(ciImage: ciImage)
        var matrix = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)

        for row in 0..<height {
            for column in 0..<width {
                let color = bitmapRepresentation.colorAt(x: column, y: row)
                let brightness = color?.brightnessComponent ?? 1.0
                matrix[row][column] = brightness < 0.5
            }
        }
        return matrix
    }

    private static let primaryNetworkInterface = "en0"
    private static let secondaryNetworkInterface = "en1"

    static func localIPAddress() -> String? {
        var address: String?
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return nil
        }
        defer { freeifaddrs(interfaceAddresses) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let networkInterface = pointer.pointee
            guard networkInterface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let interfaceName = String(cString: networkInterface.ifa_name)
            guard
                interfaceName == primaryNetworkInterface
                    || interfaceName == secondaryNetworkInterface
            else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                networkInterface.ifa_addr, socklen_t(networkInterface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST
            )
            address = String(cString: hostname)
            if interfaceName == primaryNetworkInterface { break }
        }
        return address
    }
}
