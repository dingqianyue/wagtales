import Foundation

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T?) {
        self._encode = { encoder in
            var container = encoder.singleValueContainer()
            if let value = value {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
