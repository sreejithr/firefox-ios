/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCGLogger

private let TableHistory = "history"
private let TableVisits = "visits"
private let TableFaviconSites = "faviconSites"
private let ViewWidestFaviconsForSites = "view_favicons_widest"
private let ViewHistoryIDsWithWidestFavicons = "view_history_id_favicon"

// All of these insane type declarations are to make SwiftData happy.
private let AllTables: [AnyObject?] = [
    TableFaviconSites,
    TableVisits,
    TableHistory,
]

private let AllViews: [AnyObject?] = [
    ViewHistoryIDsWithWidestFavicons,
    ViewWidestFaviconsForSites,
]

private let AllTablesAndViews: [AnyObject?] = AllViews + AllTables

private let log = XCGLogger.defaultInstance()

/**
 * The monolithic class that manages the inter-related history etc. tables.
 * We rely on SQLiteHistory having initialized the favicon table first.
 */
public class BrowserTable: Table {
    var name: String { return "BROWSER" }
    var version: Int { return 8 }

    public init() {
    }

    func run(db: SQLiteDBConnection, sql: String) -> Bool {
        let err = db.executeChange(sql, withArgs: nil)
        if err != nil {
            log.error("Error running SQL in BrowserTable. \(err?.localizedDescription)")
            log.error("SQL was \(sql)")
        }
        return err == nil
    }

    // TODO: transaction.
    func run(db: SQLiteDBConnection, queries: [String]) -> Bool {
        for sql in queries {
            if !run(db, sql: sql) {
                return false
            }
        }
        return true
    }

    func create(db: SQLiteDBConnection, version: Int) -> Bool {
        // We ignore the version.
        let history =
        "CREATE TABLE IF NOT EXISTS \(TableHistory) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "guid TEXT NOT NULL UNIQUE, " +
        "url TEXT NOT NULL UNIQUE, " +
        "title TEXT NOT NULL " +
        ") "

        let visits =
        "CREATE TABLE IF NOT EXISTS \(TableVisits) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "siteID INTEGER NOT NULL REFERENCES \(TableHistory)(id) ON DELETE CASCADE, " +
        "date REAL NOT NULL, " +
        "type INTEGER NOT NULL " +
        ") "

        let faviconSites =
        "CREATE TABLE IF NOT EXISTS \(TableFaviconSites) (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "siteID INTEGER NOT NULL REFERENCES \(TableHistory)(id) ON DELETE CASCADE, " +
        "faviconID INTEGER NOT NULL REFERENCES favicons(id) ON DELETE CASCADE, " +
        "UNIQUE (siteID, faviconID) " +
        ") "

        let widestFavicons =
        "CREATE VIEW IF NOT EXISTS \(ViewWidestFaviconsForSites) AS " +
        "SELECT " +
        "faviconSites.siteID AS siteID, " +
        "favicons.id AS iconID, " +
        "favicons.url AS iconURL, " +
        "favicons.date AS iconDate, " +
        "favicons.type AS iconType, " +
        "MAX(favicons.width) AS iconWidth " +
        "FROM faviconSites, favicons WHERE " +
        "faviconSites.faviconID = favicons.id " +
        "GROUP BY siteID "

        let historyIDsWithIcon =
        "CREATE VIEW IF NOT EXISTS \(ViewHistoryIDsWithWidestFavicons) AS " +
        "SELECT history.id AS id, " +
        "iconID, iconURL, iconDate, iconType, iconWidth " +
        "FROM history " +
        "LEFT OUTER JOIN " +
        "\(ViewWidestFaviconsForSites) ON history.id = \(ViewWidestFaviconsForSites).siteID "

        let queries = [
            history, visits, faviconSites, widestFavicons, historyIDsWithIcon,
        ]
        assert(queries.count == AllTablesAndViews.count, "Did you forget to add your table or view to the list?")
        return self.run(db, queries: queries)
    }

    func updateTable(db: SQLiteDBConnection, from: Int, to: Int) -> Bool {
        if from == to {
            log.debug("Skipping update from \(from) to \(to).")
            return true
        }
        return drop(db) && create(db, version: to)
    }

    func exists(db: SQLiteDBConnection) -> Bool {
        let tablesSQL = "SELECT name FROM sqlite_master WHERE type = 'table' AND (name = ? OR name= ?)"
        let res = db.executeQuery(tablesSQL, factory: StringFactory, withArgs: AllTables)
        log.debug("\(res.count) tables exist. Expected \(AllTables.count)")
        return res.count == AllTables.count
    }

    func drop(db: SQLiteDBConnection) -> Bool {
        let queries = AllViews.map { "DROP VIEW \($0)" } + AllTables.map { "DROP TABLE \($0)" }
        return self.run(db, queries: queries)
    }
}