//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import XCTest
import LibSignalClient

@testable import Signal
@testable import SignalServiceKit

public class ProvisioningCoordinatorTest: XCTestCase {

    typealias Mocks = ProvisioningCoordinatorImpl.Mocks

    private var provisioningCoordinator: ProvisioningCoordinatorImpl!

    private var chatConnectionManagerMock: ChatConnectionManagerMock!
    private var identityManagerMock: MockIdentityManager!
    private var accountKeyStore: AccountKeyStore!
    private var messageFactoryMock: Mocks.MessageFactory!
    private var prekeyManagerMock: MockPreKeyManager!
    private var profileManagerMock: Mocks.ProfileManager!
    private var pushRegistrationManagerMock: Mocks.PushRegistrationManager!
    private var receiptManagerMock: Mocks.ReceiptManager!
    private var registrationStateChangeManagerMock: MockRegistrationStateChangeManager!
    private var signalServiceMock: OWSSignalServiceMock!
    private var storageServiceManagerMock: FakeStorageServiceManager!
    private var svrMock: SecureValueRecoveryMock!
    private var syncManagerMock: Mocks.SyncManager!
    private var threadStoreMock: MockThreadStore!
    private var tsAccountManagerMock: MockTSAccountManager!
    private var udManagerMock: Mocks.UDManager!

    public override func setUp() async throws {

        let mockDb = InMemoryDB()

        let recipientDbTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientDbTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientIdFinder = RecipientIdFinder(
            recipientDatabaseTable: recipientDbTable,
            recipientFetcher: recipientFetcher
        )
        self.identityManagerMock = .init(recipientIdFinder: recipientIdFinder)

        self.chatConnectionManagerMock = .init()
        self.accountKeyStore = .init()
        self.messageFactoryMock = .init()
        self.prekeyManagerMock = .init()
        self.profileManagerMock = .init()
        self.pushRegistrationManagerMock = .init()
        self.receiptManagerMock = .init()
        self.registrationStateChangeManagerMock = .init()
        self.signalServiceMock = .init()
        self.storageServiceManagerMock = .init()
        self.svrMock = .init()
        self.syncManagerMock = .init()
        self.threadStoreMock = .init()
        self.tsAccountManagerMock = .init()
        self.udManagerMock = .init()

        self.provisioningCoordinator = ProvisioningCoordinatorImpl(
            chatConnectionManager: chatConnectionManagerMock,
            db: mockDb,
            deviceService: MockOWSDeviceService(),
            identityManager: identityManagerMock,
            linkAndSyncManager: MockLinkAndSyncManager(),
            accountKeyStore: accountKeyStore,
            messageFactory: messageFactoryMock,
            preKeyManager: prekeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            receiptManager: receiptManagerMock,
            registrationStateChangeManager: registrationStateChangeManagerMock,
            signalProtocolStoreManager: MockSignalProtocolStoreManager(),
            signalService: signalServiceMock,
            storageServiceManager: storageServiceManagerMock,
            svr: svrMock,
            syncManager: syncManagerMock,
            threadStore: threadStoreMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: udManagerMock
        )

        tsAccountManagerMock.registrationStateMock = { .unregistered }
    }

    public func testProvisioning() async throws {
        let aep = AccountEntropyPool()
        let provisioningMessage = LinkingProvisioningMessage(
            rootKey: .accountEntropyPool(aep),
            aci: .randomForTesting(),
            phoneNumber: "+17875550100",
            pni: .randomForTesting(),
            aciIdentityKeyPair: IdentityKeyPair.generate(),
            pniIdentityKeyPair: IdentityKeyPair.generate(),
            profileKey: .generateRandom(),
            mrbk: BackupKey.forTesting(),
            ephemeralBackupKey: nil,
            areReadReceiptsEnabled: true,
            provisioningCode: "1234"
        )
        let deviceName = "test device"
        let deviceId = DeviceId(validating: UInt32.random(in: 2...3))!

        let mockSession = UrlSessionMock()

        let verificationResponse = ProvisioningServiceResponses.VerifySecondaryDeviceResponse(
            pni: provisioningMessage.pni,
            deviceId: deviceId
        )

        mockSession.responder = { request in
            if request.url.absoluteString.hasSuffix("v1/devices/link") {
                return try! JSONEncoder().encode(verificationResponse)
            } else if request.url.absoluteString.hasSuffix("v1/devices/capabilities") {
                return Data()
            } else {
                XCTFail("Unexpected request!")
                return Data()
            }
        }

        signalServiceMock.mockUrlSessionBuilder = { (signalServiceInfo, _, _) in
            XCTAssertEqual(
                signalServiceInfo.baseUrl,
                SignalServiceType.mainSignalServiceIdentified.signalServiceInfo().baseUrl
            )
            return mockSession
        }

        pushRegistrationManagerMock.mockRegistrationId = .init(apnsToken: "apn")

        var didSetLocalIdentifiers = false
        registrationStateChangeManagerMock.didProvisionSecondaryMock = { e164, aci, pni, _, storedDeviceId in
            XCTAssertEqual(e164.stringValue, provisioningMessage.phoneNumber)
            XCTAssertEqual(aci, provisioningMessage.aci)
            XCTAssertEqual(pni, provisioningMessage.pni)
            XCTAssertEqual(storedDeviceId, deviceId)
            didSetLocalIdentifiers = true
        }

        try await provisioningCoordinator.completeProvisioning(
            provisionMessage: provisioningMessage,
            deviceName: deviceName,
            progressViewModel: LinkAndSyncSecondaryProgressViewModel()
        )

        XCTAssert(didSetLocalIdentifiers)
        XCTAssert(prekeyManagerMock.didFinalizeRegistrationPrekeys)
        XCTAssertEqual(
            profileManagerMock.localUserProfileMock?.profileKey,
            provisioningMessage.profileKey
        )
        XCTAssertEqual(
            identityManagerMock.identityKeyPairs[.aci]?.publicKey,
            provisioningMessage.aciIdentityKeyPair.asECKeyPair.publicKey
        )
        XCTAssertEqual(
            identityManagerMock.identityKeyPairs[.pni]?.publicKey,
            provisioningMessage.pniIdentityKeyPair.asECKeyPair.publicKey
        )
        let masterKey = switch provisioningMessage.rootKey {
        case .accountEntropyPool(let accountEntropyPool):
            accountEntropyPool.getMasterKey()
        case .masterKey(let masterKey):
            masterKey
        }
        XCTAssertEqual(svrMock.syncedMasterKey?.rawData, masterKey.rawData)
    }

    func testCompleteProvisioning_setLocalKeys_storesPeerExtraPublicKey() async throws {
        let primaryAci = Aci.randomForTesting()
        let primaryPni = Pni.randomForTesting()
        let primaryPhoneNumber = "+11112223333"
        let deviceId = DeviceId(validating: 2)! // Secondary device ID

        let peerKeyData = "primaryPeerExtraKey".data(using: .utf8)!

        let provisionMessage = LinkingProvisioningMessage(
            rootKey: .masterKey(try MasterKey(data: Randomness.generateRandomBytes(32))),
            aci: primaryAci,
            phoneNumber: primaryPhoneNumber,
            pni: primaryPni,
            aciIdentityKeyPair: try IdentityKeyPair.generate(),
            pniIdentityKeyPair: try IdentityKeyPair.generate(),
            profileKey: Aes256Key.generateRandom(),
            mrbk: try BackupKey.generateRandom(),
            ephemeralBackupKey: nil,
            areReadReceiptsEnabled: true,
            provisioningCode: "test-code",
            peerExtraPublicKey: peerKeyData // Key from primary
        )

        let authedDevice = AuthedDevice.Explicit(
            aci: primaryAci, // This is the ACI of the account being linked to (primary)
            phoneNumber: E164(primaryPhoneNumber)!,
            pni: primaryPni,
            deviceId: deviceId, // This is the new device's ID
            authPassword: "testAuthPassword"
        )

        // Mock TSAccountManager to return a SignalAccount for the primary device
        let primarySignalAccount = SignalAccount(
            recipientPhoneNumber: primaryPhoneNumber,
            recipientServiceId: primaryAci,
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "Primary",
            familyName: "Device",
            nickname: "",
            fullName: "Primary Device",
            contactAvatarHash: nil
        )

        var updatedAccount: SignalAccount?
        tsAccountManagerMock.fetchSignalAccountMock = { aci, tx in
            if aci == primaryAci {
                return primarySignalAccount
            }
            return nil
        }
        // Capture the account that is saved
        SignalAccount.anyOverwritingUpdateHook = { account, tx in
            updatedAccount = account
        }
        defer { SignalAccount.anyOverwritingUpdateHook = nil }


        // Call the method under test
        _ = try await provisioningCoordinator.completeProvisioning_setLocalKeys(
            provisionMessage: provisionMessage,
            prekeyBundles: RegistrationPreKeyUploadBundles(aciBundle: .forTesting(), pniBundle: .forTesting()),
            authedDevice: authedDevice
        )

        // Verification
        XCTAssertNotNil(updatedAccount, "SignalAccount for primary device should have been updated")
        XCTAssertEqual(updatedAccount?.peerExtraPublicKey, peerKeyData)
        XCTAssertNotNil(updatedAccount?.peerExtraPublicKeyTimestamp, "Timestamp should be set")
        XCTAssertEqual(updatedAccount?.recipientServiceId, primaryAci) // Ensure it's the primary's account
    }

    func testCompleteProvisioning_setLocalKeys_handlesNilPeerExtraPublicKey() async throws {
        let primaryAci = Aci.randomForTesting()
        let primaryPni = Pni.randomForTesting()
        let primaryPhoneNumber = "+12223334444"
        let deviceId = DeviceId(validating: 3)!

        let provisionMessage = LinkingProvisioningMessage(
            rootKey: .masterKey(try MasterKey(data: Randomness.generateRandomBytes(32))),
            aci: primaryAci,
            phoneNumber: primaryPhoneNumber,
            pni: primaryPni,
            aciIdentityKeyPair: try IdentityKeyPair.generate(),
            pniIdentityKeyPair: try IdentityKeyPair.generate(),
            profileKey: Aes256Key.generateRandom(),
            mrbk: try BackupKey.generateRandom(),
            ephemeralBackupKey: nil,
            areReadReceiptsEnabled: true,
            provisioningCode: "test-code-nil",
            peerExtraPublicKey: nil // Key is nil
        )

        let authedDevice = AuthedDevice.Explicit(
            aci: primaryAci,
            phoneNumber: E164(primaryPhoneNumber)!,
            pni: primaryPni,
            deviceId: deviceId,
            authPassword: "testAuthPassword"
        )

        let primarySignalAccount = SignalAccount(
            recipientPhoneNumber: primaryPhoneNumber,
            recipientServiceId: primaryAci,
            multipleAccountLabelText: nil,
            cnContactId: nil,
            givenName: "PrimaryNil",
            familyName: "DeviceNil",
            nickname: "",
            fullName: "PrimaryNil DeviceNil",
            contactAvatarHash: nil,
            peerExtraPublicKey: "existingKey".data(using: .utf8), // Pre-existing key
            peerExtraPublicKeyTimestamp: 1000 // Pre-existing timestamp
        )

        var updatedAccount: SignalAccount? = nil
        tsAccountManagerMock.fetchSignalAccountMock = { aci, tx in
            if aci == primaryAci {
                return primarySignalAccount
            }
            return nil
        }
        SignalAccount.anyOverwritingUpdateHook = { account, tx in
             updatedAccount = account
        }
        defer { SignalAccount.anyOverwritingUpdateHook = nil }

        _ = try await provisioningCoordinator.completeProvisioning_setLocalKeys(
            provisionMessage: provisionMessage,
            prekeyBundles: RegistrationPreKeyUploadBundles(aciBundle: .forTesting(), pniBundle: .forTesting()),
            authedDevice: authedDevice
        )

        // If peerExtraPublicKey is nil in the message, we expect no update to these fields.
        // The current implementation in ProvisioningCoordinatorImpl will log "No peerExtraPublicKey received".
        // We need to verify that the existing values (if any) on SignalAccount are not wiped.
        // Or, if the intent is to clear them if not present, that needs to be tested.
        // Based on the added code `if let receivedPeerKey = provisionMessage.peerExtraPublicKey`,
        // if `receivedPeerKey` is nil, the block is skipped, so existing values should remain.

        XCTAssertNotNil(updatedAccount, "SignalAccount should still be 'updated' (or re-saved with no changes to peer keys)")
        XCTAssertEqual(updatedAccount?.peerExtraPublicKey, "existingKey".data(using: .utf8), "Existing peerExtraPublicKey should not be wiped if incoming is nil")
        XCTAssertEqual(updatedAccount?.peerExtraPublicKeyTimestamp, 1000, "Existing peerExtraPublicKeyTimestamp should not be wiped if incoming is nil")
    }

    private func keyPairForTesting() throws -> ECKeyPair {
        let privateKey = try PrivateKey(Array(repeating: 0, count: 31) + [.random(in: 0..<0x48)])
        return ECKeyPair(IdentityKeyPair(publicKey: privateKey.publicKey, privateKey: privateKey))
    }
}

extension ProvisioningCoordinatorTest {

    class UrlSessionMock: BaseOWSURLSessionMock {

        var responder: ((TSRequest) -> Data)?

        override func performRequest(_ rawRequest: TSRequest) async throws -> any HTTPResponse {
            let responseBody = responder!(rawRequest)
            return HTTPResponseImpl(
                requestUrl: rawRequest.url,
                status: 200,
                headers: HttpHeaders(),
                bodyData: responseBody
            )
        }
    }
}

private class MockLinkAndSyncManager: LinkAndSyncManager {

    func isLinkAndSyncEnabledOnPrimary(tx: DBReadTransaction) -> Bool {
        true
    }

    func setIsLinkAndSyncEnabledOnPrimary(_ isEnabled: Bool, tx: DBWriteTransaction) {}

    func generateEphemeralBackupKey() -> BackupKey {
        return .forTesting()
    }

    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) {
        return
    }

    func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        return
    }
}

private class MockOWSDeviceService: OWSDeviceService {

    init() {}

    func refreshDevices() async throws -> Bool {
        return true
    }

    func renameDevice(device: SignalServiceKit.OWSDevice, toEncryptedName encryptedName: String) async throws {
        // do nothing
    }

    func unlinkDevice(deviceId: DeviceId, auth: SignalServiceKit.ChatServiceAuth) async throws {
        // do nothing
    }
}

private class MockSignalProtocolStoreManager: SignalProtocolStoreManager {
    private let aciProtocolStore = MockSignalProtocolStore(identity: .aci)
    private let pniProtocolStore = MockSignalProtocolStore(identity: .pni)

    init() {}

    func signalProtocolStore(for identity: SignalServiceKit.OWSIdentity) -> any SignalServiceKit.SignalProtocolStore {
        switch identity {
        case .aci: aciProtocolStore
        case .pni: pniProtocolStore
        }
    }

    func removeAllKeys(tx: DBWriteTransaction) {}
}
