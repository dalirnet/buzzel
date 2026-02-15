import Foundation

enum MessageType {
    static let sms = "sms"
    static let configSync = "config_sync"
    static let configAck = "config_ack"
    static let ready = "ready"
    static let goodbye = "goodbye"
    static let ping = "ping"
    static let pong = "pong"
    static let queueFlush = "queue_flush"
    static let status = "status"
    static let pairingRequest = "pairing_request"
    static let pairingResponse = "pairing_response"
    static let unpair = "unpair"
}

struct SmsPayload {
    let sender: String
    let contactName: String?
    let body: String
    let receivedAt: Int64
}

enum BleUuids {
    static let service = "0000BF01-0000-1000-8000-00805F9B34FB"
    static let configChar = "0000BF02-0000-1000-8000-00805F9B34FB"
    static let smsChar = "0000BF03-0000-1000-8000-00805F9B34FB"
    static let statusChar = "0000BF04-0000-1000-8000-00805F9B34FB"
}

enum BuzzelProtocol {

    static func createMessage(type: String, payload: [String: Any]? = nil) -> Data? {
        var dict: [String: Any] = [
            "type": type,
            "id": UUID().uuidString,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let payload = payload {
            dict["payload"] = payload
        }
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    static func createReady() -> Data? {
        createMessage(type: MessageType.ready)
    }

    static func createGoodbye() -> Data? {
        createMessage(type: MessageType.goodbye)
    }

    static func createPong() -> Data? {
        createMessage(type: MessageType.pong)
    }

    static func createUnpair() -> Data? {
        createMessage(type: MessageType.unpair)
    }

    static func createConfigSync(transport: String, wifiHost: String?, wifiPort: Int, filters: [FilterRule]) -> Data? {
        let filterDicts: [[String: Any]] = filters.map { f in
            [
                "id": f.id,
                "enabled": f.enabled,
                "type": f.type.rawValue,
                "value": f.value
            ]
        }
        var payload: [String: Any] = [
            "transport": transport,
            "wifiPort": wifiPort,
            "filters": filterDicts
        ]
        if let host = wifiHost {
            payload["wifiHost"] = host
        }
        return createMessage(type: MessageType.configSync, payload: payload)
    }

    static func createPairingRequest(code: String) -> Data? {
        createMessage(type: MessageType.pairingRequest, payload: ["code": code])
    }

    static func parseType(_ data: Data) -> String? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict["type"] as? String
    }

    static func parseSms(_ data: Data) -> SmsPayload? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = dict["payload"] as? [String: Any],
              let sender = payload["sender"] as? String,
              let body = payload["body"] as? String
        else { return nil }

        let receivedAt = (payload["receivedAt"] as? NSNumber)?.int64Value ?? 0

        return SmsPayload(
            sender: sender,
            contactName: payload["contactName"] as? String,
            body: body,
            receivedAt: receivedAt
        )
    }

    static func parseQueueFlush(_ data: Data) -> [SmsPayload] {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = dict["payload"] as? [String: Any],
              let messages = payload["messages"] as? [[String: Any]]
        else { return [] }

        return messages.compactMap { msg in
            guard let sender = msg["sender"] as? String,
                  let body = msg["body"] as? String
            else { return nil }

            let receivedAt = (msg["receivedAt"] as? NSNumber)?.int64Value ?? 0

            return SmsPayload(
                sender: sender,
                contactName: msg["contactName"] as? String,
                body: body,
                receivedAt: receivedAt
            )
        }
    }
}
