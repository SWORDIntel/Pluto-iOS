//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// TODO: Confirm the exact GRDBMigration protocol used in the project if different.
// This is a standard GRDB migration pattern.

struct AddPeerExtraPublicKeyMigration: GRDB.Migration {
    static var identifier: String {
        // Generally, a timestamp or a descriptive name is used.
        // For example: "20231027000000-AddPeerExtraPublicKeyToSignalAccount"
        // For now, using a simple identifier. This might need adjustment
        // based on project conventions found in GRDBSchemaMigrator.swift.
        return "AddPeerExtraPublicKeyToSignalAccount"
    }

    func prepare(_ db: Database) throws {
        try db.alter(table: SignalAccount.databaseTableName) { t in
            // Add peerExtraPublicKey column
            // Using .blob for Data?
            t.add(column: SignalAccount.CodingKeys.peerExtraPublicKey.rawValue, .blob)

            // Add peerExtraPublicKeyTimestamp column
            // Using .integer for Int64?
            t.add(column: SignalAccount.CodingKeys.peerExtraPublicKeyTimestamp.rawValue, .integer)
        }
    }

    func revert(_ db: Database) throws {
        // This migration is not intended to be reverted in this context,
        // but providing a best-effort revert for completeness.
        // Reverting by removing columns can be destructive if not handled carefully
        // or if the SQLite version doesn't fully support it gracefully.
        // Often, for additive changes, revert might be a no-op or raise an error.
        Logger.warn("Reverting AddPeerExtraPublicKeyMigration is not fully supported and might lead to data loss if columns are dropped.")
        // Example: try db.alter(table: SignalAccount.databaseTableName) { t in
        // t.drop(column: SignalAccount.CodingKeys.peerExtraPublicKey.rawValue)
        // t.drop(column: SignalAccount.CodingKeys.peerExtraPublicKeyTimestamp.rawValue)
        // }
        // For safety, making revert a no-op unless column dropping is standard practice here.
    }
}
