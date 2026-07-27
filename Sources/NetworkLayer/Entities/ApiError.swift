//
//  ApiError.swift
//  Qonversion
//
//  Created by Kamo Spertsyan on 22.04.2024.
//

import Foundation

/// The v4 error envelope member:
/// `{"error": {"type", "code", "message", "details": [{"field", "message"}]}}`.
///
/// Every member is decoded tolerantly. Two shapes exist in production and both
/// have to yield whatever they carry:
/// - the main surface sends all of `type`, `code`, `message` and, on a
///   validation failure, a `details` array;
/// - the `/v4/web` surface sends the same envelope without `type`.
///
/// `details` is intentionally not surfaced: it names request fields the
/// integrator did not write (the SDK builds the body), so it would be noise on
/// the public error. It must not fail the decode either — the code is what
/// drives the typed mapping.
struct ApiError : Decodable {

    /// The backend error code. Absent from partial error bodies.
    let code: String?
    /// The backend message. Absent from bodies that carry only a code.
    let message: String?
    /// The backend error class (internal | logical | request | resource).
    /// Absent from the `/v4/web` envelope and from partial error bodies.
    let type: String?

    init(code: String?, message: String?, type: String?) {
        self.code = code
        self.message = message
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        // A body carrying only some of the fields must still yield what it
        // does carry: the code drives the typed error mapping. It arrives as
        // a slug in v4 and as a bare number in the previous generation.
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringCode
        } else if let numericCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(numericCode)
        } else {
            code = nil
        }
        type = try? container.decodeIfPresent(String.self, forKey: .type)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case type
    }
}

struct ApiErrorWrapper : Decodable {

    let error: ApiError

    init(error: ApiError) {
        self.error = error
    }
}
