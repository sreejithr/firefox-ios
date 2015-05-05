/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

import Storage

private let ThumbnailIdentifier = "Thumbnail"
private let RowIdentifier = "Row"
private let SeparatorKind = "separator"
private let SeparatorIdentifier = "separator"

private let ThumbnailSectionPadding: CGFloat = 8
private let SeparatorColor = UIColor(rgb: 0xffffff)
private let DefaultImage = "defaultFavicon"

class TopSitesPanel: UIViewController, UICollectionViewDelegate, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate?

    private var collection: TopSitesCollectionView!
    private var dataSource: TopSitesDataSource!
    private let layout = TopSitesLayout()

    var profile: Profile! {
        didSet {
            // This needs to run on the main thread so that our dataSource is ready.
            profile.history.getSitesByFrecencyWithLimit(100).uponQueue(dispatch_get_main_queue()) { result in
                if let data = result.successValue {
                    self.dataSource.data = data
                    self.dataSource.profile = self.profile
                    self.collection.reloadData()
                }
                // TODO: error handling.
            }
        }
    }

    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        layout.setupForOrientation(toInterfaceOrientation)
        collection.setNeedsLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = TopSitesDataSource(profile: profile, data: Cursor(status: .Failure, msg: "Nothing loaded yet"))

        layout.registerClass(TopSitesSeparator.self, forDecorationViewOfKind: SeparatorKind)

        collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = AppConstants.PanelBackgroundColor
        collection.delegate = self
        collection.dataSource = dataSource
        collection.registerClass(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.registerClass(TwoLineCollectionViewCell.self, forCellWithReuseIdentifier: RowIdentifier)
        collection.keyboardDismissMode = .OnDrag
        view.addSubview(collection)
        collection.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
            return
        }
    }

    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if let site = dataSource?.data[indexPath.item] {
            homePanelDelegate?.homePanel(self, didSelectURL: NSURL(string: site.url)!)
        }
    }
}

private class TopSitesCollectionView: UICollectionView {
    private override func touchesBegan(touches: Set<NSObject>, withEvent event: UIEvent) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, withEvent: event)
    }
}

private class TopSitesLayout: UICollectionViewLayout {
    private let AspectRatio: CGFloat = 1.25 // Ratio of width:height.

    private var thumbnailRows = 3
    private var thumbnailCols = 2
    private var thumbnailCount: Int { return thumbnailRows * thumbnailCols }
    private var width: CGFloat { return self.collectionView?.frame.width ?? 0 }
    private var thumbnailWidth: CGFloat { return width / CGFloat(thumbnailCols) - (ThumbnailSectionPadding * 2) / CGFloat(thumbnailCols) }
    private var thumbnailHeight: CGFloat { return thumbnailWidth / AspectRatio }

    private var count: Int {
        if let dataSource = self.collectionView?.dataSource as? TopSitesDataSource {
            return dataSource.data.count
        }
        return 0
    }

    private var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        return thumbnailHeight * CGFloat(rows) + ThumbnailSectionPadding * 2
    }

    override init() {
        super.init()
        setupForOrientation(UIApplication.sharedApplication().statusBarOrientation)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupForOrientation(orientation: UIInterfaceOrientation) {
        if orientation.isLandscape {
            thumbnailRows = 2
            thumbnailCols = 3
        } else {
            thumbnailRows = 3
            thumbnailCols = 2
        }
    }

    private func getIndexAtPosition(#y: CGFloat) -> Int {
        if y < topSectionHeight {
            let row = Int(y / thumbnailHeight)
            return min(count - 1, max(0, row * thumbnailCols))
        }
        return min(count - 1, max(0, Int((y - topSectionHeight) / AppConstants.DefaultRowHeight + CGFloat(thumbnailCount))))
    }

    override func collectionViewContentSize() -> CGSize {
        if count <= thumbnailCount {
            let row = floor(Double(count / thumbnailCols))
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * AppConstants.DefaultRowHeight
        return CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
    }

    override func layoutAttributesForElementsInRect(rect: CGRect) -> [AnyObject]? {
        let start = getIndexAtPosition(y: rect.origin.y)
        let end = getIndexAtPosition(y: rect.origin.y + rect.height)

        var attrs = [UICollectionViewLayoutAttributes]()
        if start == -1 || end == -1 {
            return attrs
        }

        for i in start...end {
            let indexPath = NSIndexPath(forItem: i, inSection: 0)
            let attr = layoutAttributesForItemAtIndexPath(indexPath)
            attrs.append(attr)

            if i >= thumbnailCount - 1 {
                let decoration = layoutAttributesForDecorationViewOfKind(SeparatorKind, atIndexPath: indexPath)
                attrs.append(decoration)
            }
        }
        return attrs
    }

    // Set the frames for the row separators.
    override func layoutAttributesForDecorationViewOfKind(elementKind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionViewLayoutAttributes! {
        let decoration = UICollectionViewLayoutAttributes(forDecorationViewOfKind: elementKind, withIndexPath: indexPath)
        let rowIndex = indexPath.item - thumbnailCount + 1
        let rowYOffset = CGFloat(rowIndex) * AppConstants.DefaultRowHeight
        let y = topSectionHeight + rowYOffset
        decoration.frame = CGRectMake(0, y, width, 0.5)
        return decoration
    }

    override func layoutAttributesForItemAtIndexPath(indexPath: NSIndexPath) -> UICollectionViewLayoutAttributes! {
        let attr = UICollectionViewLayoutAttributes(forCellWithIndexPath: indexPath)

        let i = indexPath.item
        if i < thumbnailCount {
            // Set the top thumbnail frames.
            let row = floor(Double(i / thumbnailCols))
            let col = i % thumbnailCols
            let x = CGFloat(thumbnailWidth * CGFloat(col)) + ThumbnailSectionPadding
            let y = CGFloat(row) * thumbnailHeight + ThumbnailSectionPadding
            attr.frame = CGRectMake(x, y, thumbnailWidth, thumbnailHeight)
        } else {
            // Set the bottom row frames.
            let rowYOffset = CGFloat(i - thumbnailCount) * AppConstants.DefaultRowHeight
            let y = CGFloat(topSectionHeight + rowYOffset)
            attr.frame = CGRectMake(0, y, width, AppConstants.DefaultRowHeight)
        }

        return attr
    }

    override func shouldInvalidateLayoutForBoundsChange(newBounds: CGRect) -> Bool {
        return true
    }
}

class TopSitesDataSource: NSObject, UICollectionViewDataSource {
    var data: Cursor<Site>
    var profile: Profile

    init(profile: Profile, data: Cursor<Site>) {
        self.data = data
        self.profile = profile
    }

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return data.count
    }

    private func setDefaultThumbnailBackground(cell: ThumbnailCell) {
        cell.imageView.image = UIImage(named: "defaultFavicon")!
        cell.imageView.contentMode = UIViewContentMode.Center
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let site = data[indexPath.item]!

        // Cells for the top site thumbnails.
        if indexPath.item < 6 {
            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(ThumbnailIdentifier, forIndexPath: indexPath) as! ThumbnailCell
            cell.textLabel.text = site.title.isEmpty ? site.url : site.title
            if let thumbs = profile.thumbnails as? SDWebThumbnails {
                cell.imageView.moz_getImageFromCache(site.url, cache: thumbs.cache, completed: { (img, err, type, url) -> Void in
                    if img != nil {
                        return
                    }
                    self.setDefaultThumbnailBackground(cell)
                })
            } else {
                setDefaultThumbnailBackground(cell)
            }
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = cell.textLabel.text
            return cell
        }

        // Cells for the remainder of the top sites list.
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(RowIdentifier, forIndexPath: indexPath) as! TwoLineCollectionViewCell
        cell.textLabel.text = site.title.isEmpty ? site.url : site.title
        cell.detailTextLabel.text = site.url
        cell.mergeAccessibilityLabels()
        if let icon = site.icon {
            cell.imageView.sd_setImageWithURL(NSURL(string: icon.url)!)
        } else {
            cell.imageView.image = UIImage(named: DefaultImage)
        }
        return cell
    }
    
    func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        return collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: SeparatorIdentifier, forIndexPath: indexPath) as! UICollectionReusableView
    }
}

private class TopSitesSeparator: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = SeparatorColor
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
