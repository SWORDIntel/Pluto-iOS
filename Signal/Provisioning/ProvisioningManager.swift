//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
public import LibSignalClient

public class ProvisioningManager {

    private let accountKeyStore: AccountKeyStore
    private let db: any DB
    private let deviceManager: OWSDeviceManager
    private let deviceProvisioningService: DeviceProvisioningService
    private let identityManager: OWSIdentityManager
    private let linkAndSyncManager: LinkAndSyncManager
    private let profileManager: Shims.ProfileManager
    private let receiptManager: Shims.ReceiptManager
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        db: any DB,
        deviceManager: OWSDeviceManager,
        deviceProvisioningService: DeviceProvisioningService,
        identityManager: OWSIdentityManager,
        linkAndSyncManager: LinkAndSyncManager,
        profileManager: Shims.ProfileManager,
        receiptManager: Shims.ReceiptManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.db = db
        self.deviceManager = deviceManager
        self.deviceProvisioningService = deviceProvisioningService
        self.identityManager = identityManager
        self.linkAndSyncManager = linkAndSyncManager
        self.profileManager = profileManager
        self.receiptManager = receiptManager
        self.tsAccountManager = tsAccountManager
    }

    public func provision(
        with deviceProvisioningUrl: DeviceProvisioningURL,
        shouldLinkNSync: Bool
    ) async throws -> (BackupKey?, DeviceProvisioningTokenId) {
        struct ProvisioningState {
            var localIdentifiers: LocalIdentifiers
            var aciIdentityKeyPair: ECKeyPair
            var pniIdentityKeyPair: ECKeyPair
            var areReadReceiptsEnabled: Bool
            var rootKey: LinkingProvisioningMessage.RootKey
            var mediaRootBackupKey: BackupKey
            var profileKey: Aes256Key
        }

        let ephemeralBackupKey: BackupKey?
        if
            shouldLinkNSync,
            deviceProvisioningUrl.capabilities.contains(where: { $0 == .linknsync })
        {
            ephemeralBackupKey = linkAndSyncManager.generateEphemeralBackupKey()
        } else {
            ephemeralBackupKey = nil
        }

        let provisioningState = await db.awaitableWrite { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else { owsFail("Can't provision without an aci & phone number.")
            }
            guard let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx) else {
                owsFail("Can't provision without an aci identity.")
            }
            guard let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx) else {
                owsFail("Can't provision without a pni identity.")
            }
            let areReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled(tx: tx)
            let rootKey: LinkingProvisioningMessage.RootKey
            guard let accountEntropyPool = accountKeyStore.getAccountEntropyPool(tx: tx) else {
                // This should be impossible; the only times you don't have
                // an AEP are during registration.
                owsFail("Can't provision without account entropy pool.")
            }
            rootKey = .accountEntropyPool(accountEntropyPool)
            let mrbk = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)
            guard let profileKey = profileManager.localUserProfile(tx: tx)?.profileKey else {
                owsFail("Can't provision without a profile key.")
            }
            return ProvisioningState(
                localIdentifiers: localIdentifiers,
                aciIdentityKeyPair: aciIdentityKeyPair,
                pniIdentityKeyPair: pniIdentityKeyPair,
                areReadReceiptsEnabled: areReadReceiptsEnabled,
                rootKey: rootKey,
                mediaRootBackupKey: mrbk,
                profileKey: profileKey
            )
        }

        let myAci = provisioningState.localIdentifiers.aci
        let myPhoneNumber = provisioningState.localIdentifiers.phoneNumber
        guard let myPni = provisioningState.localIdentifiers.pni else {
            owsFail("Can't provision without a pni.")
        }

        // TODO: Implement actual HKDF-SHA256 derivation as per DESIGN_NOTES_MollyExtraLock.md
        // For now, using a placeholder.
        var derivedPeerExtraPublicKey: Data? = nil
        let aciPrivateKey = provisioningState.aciIdentityKeyPair.privateKey
        do {
            // Placeholder for deriving peerExtraPrivateKey from aciPrivateKey
            // let peerExtraPrivateKey = try KeyDerivation.derivePeerExtraPrivateKey(from: aciPrivateKey.serialize())
            // Placeholder for deriving peerExtraPublicKey from peerExtraPrivateKey
            // derivedPeerExtraPublicKey = try KeyDerivation.derivePeerExtraPublicKey(from: peerExtraPrivateKey)
            Logger.warn("Placeholder: Peer Extra Key derivation is not yet implemented.")
        } catch {
            Logger.error("Error deriving peer extra public key: \(error)")
            // Decide if provisioning should fail or continue without this key
        }

        let provisioningCode = try await deviceProvisioningService.requestDeviceProvisioningCode()

        let provisioningMessage = LinkingProvisioningMessage(
            rootKey: provisioningState.rootKey,
            aci: myAci,
            phoneNumber: myPhoneNumber,
            pni: myPni,
            aciIdentityKeyPair: provisioningState.aciIdentityKeyPair.identityKeyPair,
            pniIdentityKeyPair: provisioningState.pniIdentityKeyPair.identityKeyPair,
            profileKey: provisioningState.profileKey,
            mrbk: provisioningState.mediaRootBackupKey,
            ephemeralBackupKey: ephemeralBackupKey,
            areReadReceiptsEnabled: provisioningState.areReadReceiptsEnabled,
            provisioningCode: provisioningCode.verificationCode,
            peerExtraPublicKey: derivedPeerExtraPublicKey
        )

        let theirPublicKey = deviceProvisioningUrl.publicKey
        let messageBody = try provisioningMessage.buildEncryptedMessageBody(theirPublicKey: theirPublicKey)
        try await deviceProvisioningService.provisionDevice(
            messageBody: messageBody,
            ephemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId
        )
        return (ephemeralBackupKey, provisioningCode.tokenId)
    }
}
