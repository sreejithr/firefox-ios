/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCGLogger

private let log = XCGLogger.defaultInstance()

// To keep SwiftData happy.
typealias Args = [AnyObject?]

class SQLiteBookmarkFolder: BookmarkFolder {
    private let cursor: Cursor<BookmarkNode>
    override var count: Int {
        return cursor.count
    }

    override subscript(index: Int) -> BookmarkNode {
        let bookmark = cursor[index]
        if let item = bookmark as? BookmarkItem {
            return item
        }

        // TODO: this is fragile.
        return bookmark as! BookmarkFolder
    }

    init(guid: String, title: String, children: Cursor<BookmarkNode>) {
        self.cursor = children
        super.init(guid: guid, title: title)
    }
}

public class SQLiteBookmarks: BookmarksModelFactory {
    let db: BrowserDB

    public init(db: BrowserDB) {
        self.db = db
    }

    private class func factory(row: SDRow) -> BookmarkNode {
        if let typeCode = row["type"] as? Int, type = BookmarkNodeType(rawValue: typeCode) {

            let id = row["id"] as! Int
            let guid = row["guid"] as! String
            switch type {
            case .Bookmark:
                let url = row["url"] as! String
                let title = row["title"] as? String ?? url
                let bookmark = BookmarkItem(guid: guid, title: title, url: url)

                // TODO: share this logic with SQLiteHistory.
                if let faviconUrl = row["iconURL"] as? String,
                   let date = row["iconDate"] as? Double,
                   let faviconType = row["iconType"] as? Int {
                    bookmark.favicon = Favicon(url: faviconUrl,
                        date: NSDate(timeIntervalSince1970: date),
                        type: IconType(rawValue: faviconType)!)
                }

                bookmark.id = id
                return bookmark

            case .Folder:
                let title = row["title"] as? String ?? "Untitled"     // TODO: l10n
                let folder = BookmarkFolder(guid: guid, title: title)
                folder.id = id
                return folder

            case .DynamicContainer:
                assert(false, "Should never occur.")
            case .Separator:
                assert(false, "Separators not yet supported.")
            }
        }

        assert(false, "Invalid bookmark data.")
    }

    private func getRootChildren() -> Cursor<BookmarkNode> {
        var err: NSError? = nil
        return db.withReadableConnection(&err) { (conn, err) -> Cursor<BookmarkNode> in
            let sql = "SELECT id, type, guid, url, title FROM bookmarks WHERE parent = ? AND id IS NOT ?"
            let args: Args? = [BookmarkRoots.RootID, BookmarkRoots.RootID]
            return conn.executeQuery(sql, factory: SQLiteBookmarks.factory, withArgs: args)
        }
    }

    private func getChildren(guid: String) -> Cursor<BookmarkNode> {
        var err: NSError? = nil
        return db.withReadableConnection(&err) { (conn, err) -> Cursor<BookmarkNode> in
            let sql = "SELECT id, type, guid, url, title FROM bookmarks WHERE parent IS NOT NULL AND parent = (SELECT id FROM bookmarks WHERE guid = ?)"
            let args: Args? = [guid]
            return conn.executeQuery(sql, factory: SQLiteBookmarks.factory, withArgs: args)
        }
    }

    public func modelForFolder(folder: BookmarkFolder, success: (BookmarksModel) -> (), failure: (Any) -> ()) {
        let children = getChildren(folder.guid)
        if children.status == .Failure {
            failure(children.statusMessage)
            return
        }
        let f = SQLiteBookmarkFolder(guid: folder.guid, title: folder.title, children: children)
        success(BookmarksModel(modelFactory: self, root: f))
    }

    public func modelForFolder(guid: String, success: (BookmarksModel) -> (), failure: (Any) -> ()) {
        let children = getChildren(guid)
        if children.status == .Failure {
            failure(children.statusMessage)
            return
        }
        let f = SQLiteBookmarkFolder(guid: guid, title: "", children: children)
        success(BookmarksModel(modelFactory: self, root: f))
    }

    public func modelForRoot(success: (BookmarksModel) -> (), failure: (Any) -> ()) {
        let children = getRootChildren()
        if children.status == .Failure {
            failure(children.statusMessage)
            return
        }
        let folder = SQLiteBookmarkFolder(guid: BookmarkRoots.RootGUID, title: "Root", children: children)
        success(BookmarksModel(modelFactory: self, root: folder))
    }

    public var nullModel: BookmarksModel {
        let children = Cursor<BookmarkNode>(status: .Failure, msg: "Null model")
        let folder = SQLiteBookmarkFolder(guid: "Null", title: "Null", children: children)
        return BookmarksModel(modelFactory: self, root: folder)
    }

    public func isBookmarked(url: String, success: (Bool) -> (), failure: (Any) -> ()) {
        var err: NSError?
        let sql = "SELECT id FROM bookmarks WHERE url = ? LIMIT 1"
        let args: Args? = [url]

        let c = db.withReadableConnection(&err) { (conn, err) -> Cursor<Int> in
            return conn.executeQuery(sql, factory: { $0["id"] as! Int }, withArgs: args)
        }
        if c.status == .Success {
            success(c.count > 0)
        } else {
            failure(err)
        }
    }

    private func runSQL(sql: String, args: Args?, success: (Bool) -> Void, failure: (Any) -> Void) {
        var err: NSError?
        self.db.withWritableConnection(&err) { (connection: SQLiteDBConnection, inout err: NSError?) -> Int in
            if let err = connection.executeChange(sql, withArgs: args) {
                failure(err)
                return 0
            }
            success(true)
            return 1
        }
    }

    public func removeByURL(url: String, success: (Bool) -> Void, failure: (Any) -> Void) {
        log.debug("Removing bookmark \(url).")
        let sql = "DELETE FROM bookmarks WHERE url = ?"
        let args: Args? = [url]

        self.runSQL(sql, args: args, success: success, failure: failure)
    }

    public func remove(bookmark: BookmarkNode, success: (Bool) -> (), failure: (Any) -> ()) {
        if let item = bookmark as? BookmarkItem {
            log.debug("Removing bookmark \(item.url).")
        }

        let sql: String
        let args: Args?
        if let id = bookmark.id {
            sql = "DELETE FROM bookmarks WHERE id = ?"
            args = [id]
        } else {
            sql = "DELETE FROM bookmarks WHERE guid = ?"
            args = [bookmark.guid]
        }

        self.runSQL(sql, args: args, success: success, failure: failure)
    }
}

extension SQLiteBookmarks: ShareToDestination {
    public func shareItem(item: ShareItem) {
        var err: NSError?
        self.db.withWritableConnection(&err) {  (conn, err) -> Int in
            // TODO: favicon
            let args: Args? = [Bytes.generateGUID(), BookmarkNodeType.Bookmark.rawValue, item.url, item.title ?? item.url, BookmarkRoots.MobileID]
            let sql = "INSERT INTO bookmarks (guid, type, url, title, parent) VALUES (?, ?, ?, ?, ?)"
            err = conn.executeChange(sql, withArgs: args)
            if let err = err {
                log.error("Error inserting \(item.url). Got \(err).")
                return 0
            }
            return 1
        }
    }
}