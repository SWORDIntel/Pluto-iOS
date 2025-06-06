//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit // Or the appropriate module name

class SignalAccountTests: XCTestCase {

    func testEncodingDecodingWithNewFields() throws {
        let serviceId = UUID().uuidString
        let peerKey = "peerExtraPublicKey_data".data(using: .utf8)!
        let peerTimestamp = Int64(Date().timeIntervalSince1970 * 1000)

        let account = SignalAccount(
            recipientPhoneNumber: "1234567890",
            recipientServiceId: try ServiceId.parseFrom(serviceIdString: serviceId),
            multipleAccountLabelText: "Work",
            cnContactId: "cn123",
            givenName: "John",
            familyName: "Appleseed",
            nickname: "Johnny",
            fullName: "John Appleseed",
            contactAvatarHash: "avatarHash".data(using: .utf8),
            peerExtraPublicKey: peerKey,
            peerExtraPublicKeyTimestamp: peerTimestamp
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(account)

        let decoder = JSONDecoder()
        let decodedAccount = try decoder.decode(SignalAccount.self, from: data)

        XCTAssertEqual(decodedAccount.recipientPhoneNumber, "1234567890")
        XCTAssertEqual(decodedAccount.recipientServiceId?.serviceIdString, serviceId)
        XCTAssertEqual(decodedAccount.multipleAccountLabelText, "Work")
        XCTAssertEqual(decodedAccount.cnContactId, "cn123")
        XCTAssertEqual(decodedAccount.givenName, "John")
        XCTAssertEqual(decodedAccount.familyName, "Appleseed")
        XCTAssertEqual(decodedAccount.nickname, "Johnny")
        XCTAssertEqual(decodedAccount.fullName, "John Appleseed")
        XCTAssertEqual(decodedAccount.contactAvatarHash, "avatarHash".data(using: .utf8))
        XCTAssertEqual(decodedAccount.peerExtraPublicKey, peerKey)
        XCTAssertEqual(decodedAccount.peerExtraPublicKeyTimestamp, peerTimestamp)
    }

    func testEncodingDecodingWithNilNewFields() throws {
        let serviceId = UUID().uuidString
        let account = SignalAccount(
            recipientPhoneNumber: "1234567890",
            recipientServiceId: try ServiceId.parseFrom(serviceIdString: serviceId),
            multipleAccountLabelText: "Work",
            cnContactId: "cn123",
            givenName: "Jane",
            familyName: "Doe",
            nickname: "Janey",
            fullName: "Jane Doe",
            contactAvatarHash: "avatarHash2".data(using: .utf8),
            peerExtraPublicKey: nil,
            peerExtraPublicKeyTimestamp: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(account)

        let decoder = JSONDecoder()
        let decodedAccount = try decoder.decode(SignalAccount.self, from: data)

        XCTAssertEqual(decodedAccount.givenName, "Jane")
        XCTAssertNil(decodedAccount.peerExtraPublicKey)
        XCTAssertNil(decodedAccount.peerExtraPublicKeyTimestamp)
    }

    func testDecodingOldDataWithoutNewFields() throws {
        // Prepare a JSON string representing an old SignalAccount without the new fields
        let oldJsonString = """
        {
            "id": null,
            "uniqueId": "\(UUID().uuidString)",
            "contactAvatarHash": null,
            "multipleAccountLabelText": "Home",
            "recipientPhoneNumber": "0987654321",
            "recipientUUID": "\(UUID().uuidString)",
            "cnContactId": "cn456",
            "givenName": "Old",
            "familyName": "User",
            "nickname": "Oldie",
            "fullName": "Old User",
            "recordType": \(SignalAccount.recordType)
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decodedAccount = try decoder.decode(SignalAccount.self, from: oldJsonString)

        XCTAssertEqual(decodedAccount.fullName, "Old User")
        XCTAssertNil(decodedAccount.peerExtraPublicKey, "peerExtraPublicKey should be nil for old data")
        XCTAssertNil(decodedAccount.peerExtraPublicKeyTimestamp, "peerExtraPublicKeyTimestamp should be nil for old data")
    }

    func testHasSameContent() throws {
        let serviceId1 = try ServiceId.parseFrom(serviceIdString: UUID().uuidString)
        let serviceId2 = try ServiceId.parseFrom(serviceIdString: UUID().uuidString)
        let key1 = "key1".data(using: .utf8)!
        let time1 = Int64(1000)
        let key2 = "key2".data(using: .utf8)!
        let time2 = Int64(2000)

        let baseAccount = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil)

        // Same base
        let account1 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: key1, peerExtraPublicKeyTimestamp: time1)
        let account2 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: key1, peerExtraPublicKeyTimestamp: time1)
        XCTAssertTrue(account1.hasSameContent(account2))

        // Different peerExtraPublicKey
        let account3 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: key2, peerExtraPublicKeyTimestamp: time1)
        XCTAssertFalse(account1.hasSameContent(account3))

        // Different peerExtraPublicKeyTimestamp
        let account4 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: key1, peerExtraPublicKeyTimestamp: time2)
        XCTAssertFalse(account1.hasSameContent(account4))

        // One with nil, one with value
        let account5 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: nil, peerExtraPublicKeyTimestamp: nil)
        XCTAssertFalse(account1.hasSameContent(account5))
        XCTAssertFalse(account5.hasSameContent(account1))

        // Both nil
        let account6 = SignalAccount(recipientPhoneNumber: "111", recipientServiceId: serviceId1, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: nil, peerExtraPublicKeyTimestamp: nil)
        XCTAssertTrue(account5.hasSameContent(account6))

        // Different base property
        let account7 = SignalAccount(recipientPhoneNumber: "222", recipientServiceId: serviceId2, multipleAccountLabelText: "L1", cnContactId: "C1", givenName: "GN", familyName: "FN", nickname: "NN", fullName: "FLN", contactAvatarHash: nil, peerExtraPublicKey: key1, peerExtraPublicKeyTimestamp: time1)
        XCTAssertFalse(account1.hasSameContent(account7))
    }

    func testCopyWithZone() throws {
        let serviceId = UUID().uuidString
        let peerKey = "peerKeyCopy".data(using: .utf8)!
        let peerTimestamp = Int64(Date().timeIntervalSince1970 * 1000 + 12345)

        let originalAccount = SignalAccount(
            recipientPhoneNumber: "5551234",
            recipientServiceId: try ServiceId.parseFrom(serviceIdString: serviceId),
            multipleAccountLabelText: "CopyTest",
            cnContactId: "cnCopy",
            givenName: "Copy",
            familyName: "McCopyFace",
            nickname: "Copy",
            fullName: "Copy McCopyFace",
            contactAvatarHash: "copyHash".data(using: .utf8),
            peerExtraPublicKey: peerKey,
            peerExtraPublicKeyTimestamp: peerTimestamp
        )

        guard let copiedAccount = originalAccount.copy() as? SignalAccount else {
            XCTFail("Copy was not a SignalAccount instance")
            return
        }

        XCTAssertEqual(copiedAccount.recipientPhoneNumber, originalAccount.recipientPhoneNumber)
        XCTAssertEqual(copiedAccount.recipientServiceId, originalAccount.recipientServiceId)
        XCTAssertEqual(copiedAccount.multipleAccountLabelText, originalAccount.multipleAccountLabelText)
        XCTAssertEqual(copiedAccount.cnContactId, originalAccount.cnContactId)
        XCTAssertEqual(copiedAccount.givenName, originalAccount.givenName)
        XCTAssertEqual(copiedAccount.familyName, originalAccount.familyName)
        XCTAssertEqual(copiedAccount.nickname, originalAccount.nickname)
        XCTAssertEqual(copiedAccount.fullName, originalAccount.fullName)
        XCTAssertEqual(copiedAccount.contactAvatarHash, originalAccount.contactAvatarHash)
        XCTAssertEqual(copiedAccount.peerExtraPublicKey, originalAccount.peerExtraPublicKey)
        XCTAssertEqual(copiedAccount.peerExtraPublicKeyTimestamp, originalAccount.peerExtraPublicKeyTimestamp)
        XCTAssertEqual(copiedAccount.uniqueId, originalAccount.uniqueId, "UniqueId should be copied")
        XCTAssertEqual(copiedAccount.id, originalAccount.id, "RowId should be copied")
    }

    func testCopyWithZoneWithNilNewFields() throws {
        let serviceId = UUID().uuidString
        let originalAccount = SignalAccount(
            recipientPhoneNumber: "5551234",
            recipientServiceId: try ServiceId.parseFrom(serviceIdString: serviceId),
            multipleAccountLabelText: "CopyTest",
            cnContactId: "cnCopy",
            givenName: "Copy",
            familyName: "McCopyFace",
            nickname: "Copy",
            fullName: "Copy McCopyFace",
            contactAvatarHash: "copyHash".data(using: .utf8),
            peerExtraPublicKey: nil,
            peerExtraPublicKeyTimestamp: nil
        )

        guard let copiedAccount = originalAccount.copy() as? SignalAccount else {
            XCTFail("Copy was not a SignalAccount instance")
            return
        }
        XCTAssertNil(copiedAccount.peerExtraPublicKey)
        XCTAssertNil(copiedAccount.peerExtraPublicKeyTimestamp)
    }
}
