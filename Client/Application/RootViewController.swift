/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

/// This UINavigationController subclass is used as the root of the application. It only overrides
/// rotation logic to make sure that the IntroViewController will only be displayed in portrait. This
/// has to be done here because for a UINavigationController, it's child view controllers inherit the
/// supported interface orientations. And since the BrowserViewController and IntroViewController have
/// different requirements, we have to special case those here. On iPad we don't use this at all.

class RootViewController: UINavigationController {
    override func supportedInterfaceOrientations() -> Int {
        if UIDevice.currentDevice().userInterfaceIdiom == .Phone && topViewController is IntroViewController {
            return Int(UIInterfaceOrientationMask.Portrait.rawValue)
        }
        return Int(UIInterfaceOrientationMask.AllButUpsideDown.rawValue)
    }

    override func shouldAutorotate() -> Bool {
        return true
    }
}
