/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Alamofire
import MessageUI
import Shared

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var browserViewController: BrowserViewController!
    var profile: Profile!

    private let appVersion = NSBundle.mainBundle().objectForInfoDictionaryKey("CFBundleShortVersionString") as! String

    func application(application: UIApplication, willFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Setup a web server that serves us static content. Do this early so that it is ready when the UI is presented.
        setupWebServer()

        // Set the Firefox UA for browsing.
        setUserAgent()

        // Start the keyboard helper to monitor and cache keyboard state.
        KeyboardHelper.defaultHelper.startObserving()

        if NSClassFromString("XCTestCase") == nil {
            profile = BrowserProfile(localName: "profile")
        } else {
            // Use a clean profile for each test session.
            profile = BrowserProfile(localName: "testProfile")
            profile.files.removeFilesInDirectory()
        }

        self.window = UIWindow(frame: UIScreen.mainScreen().bounds)
        self.window!.backgroundColor = UIColor.whiteColor()

        browserViewController = BrowserViewController(profile: profile)

        // Add restoration class, the factory that will return the ViewController we 
        // will restore with.
        browserViewController.restorationIdentifier = NSStringFromClass(BrowserViewController.self)
        browserViewController.restorationClass = AppDelegate.self

        // On iPhone we keep our main controller in a UINavigationController so that we can
        // more easily maintain a stack of viewcontrollers for the on-boarding. On iPad we
        // present the on-boarding modally on top of the BVC so we don't need it there.
        if UIDevice.currentDevice().userInterfaceIdiom == .Phone {
            let navigationController = RootViewController(rootViewController: browserViewController)
            navigationController.navigationBarHidden = true
            if let introViewController = IntroViewController(profile: profile) {
                introViewController.delegate = self
                navigationController.pushViewController(introViewController, animated: false)
            }
            self.window!.rootViewController = navigationController
        } else {
            self.window!.rootViewController = browserViewController
        }

        self.window!.backgroundColor = UIColor(red: 0.21, green: 0.23, blue: 0.25, alpha: 1)


#if MOZ_CHANNEL_AURORA
        checkForAuroraUpdate()
        registerFeedbackNotification()
#endif
        return true
    }

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
        self.window!.makeKeyAndVisible()
        return true
    }

#if MOZ_CHANNEL_AURORA
    var naggedAboutAuroraUpdate = false
    func applicationDidBecomeActive(application: UIApplication) {
        if !naggedAboutAuroraUpdate {
            checkForAuroraUpdate()
        }
    }

    func application(application: UIApplication, applicationWillTerminate app: UIApplication) {
        unregisterFeedbackNotification()
    }
    
    func applicationWillResignActive(application: UIApplication) {
        unregisterFeedbackNotification()
    }

    private func registerFeedbackNotification() {
        NSNotificationCenter.defaultCenter().addObserverForName(
            UIApplicationUserDidTakeScreenshotNotification,
            object: nil,
            queue: NSOperationQueue.mainQueue()) { (notification) -> Void in
                if let window = self.window {
                    UIGraphicsBeginImageContext(window.bounds.size)
                    window.drawViewHierarchyInRect(window.bounds, afterScreenUpdates: true)
                    let image = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    self.sendFeedbackMailWithImage(image)
                }
        }
    }
    
    private func unregisterFeedbackNotification() {
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: UIApplicationUserDidTakeScreenshotNotification, object: nil)
    }
#endif

    private func setupWebServer() {
        let server = WebServer.sharedInstance
        ReaderModeHandlers.register(server)
        server.start()
    }

    private func setUserAgent() {
        let webView = UIWebView()
        let userAgent = webView.stringByEvaluatingJavaScriptFromString("navigator.userAgent")!

        // Extract the WebKit version and use it as the Safari version.
        let webKitVersionRegex = NSRegularExpression(pattern: "AppleWebKit/([^ ]+) ", options: nil, error: nil)!
        let match = webKitVersionRegex.firstMatchInString(userAgent, options: nil, range: NSRange(location: 0, length: count(userAgent)))
        if match == nil {
            println("Error: Unable to determine WebKit version")
            return
        }
        let webKitVersion = (userAgent as NSString).substringWithRange(match!.rangeAtIndex(1))

        // Insert "FxiOS/<version>" before the Mobile/ section.
        let mobileRange = (userAgent as NSString).rangeOfString("Mobile/")
        if mobileRange.location == NSNotFound {
            println("Error: Unable to find Mobile section")
            return
        }

        let mutableUA = NSMutableString(string: userAgent)
        mutableUA.insertString("FxiOS/\(appVersion) ", atIndex: mobileRange.location)
        let firefoxUA = "\(mutableUA) Safari/\(webKitVersion)"
        NSUserDefaults.standardUserDefaults().registerDefaults(["UserAgent": firefoxUA])
    }
}


#if MOZ_CHANNEL_AURORA
private let AuroraBundleIdentifier = "org.mozilla.ios.FennecAurora"
private let AuroraPropertyListURL = "https://pvtbuilds.mozilla.org/ios/FennecAurora.plist"
private let AuroraDownloadPageURL = "https://pvtbuilds.mozilla.org/ios/index.html"

private let AppUpdateTitle = NSLocalizedString("New version available", comment: "Prompt title for application update")
private let AppUpdateMessage = NSLocalizedString("There is a new version available of Firefox Aurora. Tap OK to go to the download page.", comment: "Prompt message for application update")
private let AppUpdateCancel = NSLocalizedString("Not Now", comment: "Label for button to cancel application update prompt")
private let AppUpdateOK = NSLocalizedString("OK", comment: "Label for OK button in the application update prompt")

extension AppDelegate: UIAlertViewDelegate {
    private func checkForAuroraUpdate() {
        if isAuroraChannel() {
            if let localVersion = localVersion() {
                fetchLatestAuroraVersion() { version in
                    if let remoteVersion = version {
                        if localVersion.compare(remoteVersion as String, options: NSStringCompareOptions.NumericSearch) == NSComparisonResult.OrderedAscending {
                            self.naggedAboutAuroraUpdate = true

                            let alert = UIAlertView(title: AppUpdateTitle, message: AppUpdateMessage, delegate: self, cancelButtonTitle: AppUpdateCancel, otherButtonTitles: AppUpdateOK)
                            alert.show()
                        }
                    }
                }
            }
        }
    }

    private func isAuroraChannel() -> Bool {
        return NSBundle.mainBundle().bundleIdentifier == AuroraBundleIdentifier
    }

    private func localVersion() -> NSString? {
        return NSBundle.mainBundle().objectForInfoDictionaryKey(String(kCFBundleVersionKey)) as? NSString
    }

    private func fetchLatestAuroraVersion(completionHandler: NSString? -> Void) {
        Alamofire.request(.GET, AuroraPropertyListURL).responsePropertyList(options: NSPropertyListReadOptions.allZeros, completionHandler: { (_, _, object, _) -> Void in
            if let plist = object as? NSDictionary {
                if let items = plist["items"] as? NSArray {
                    if let item = items[0] as? NSDictionary {
                        if let metadata = item["metadata"] as? NSDictionary {
                            if let remoteVersion = metadata["bundle-version"] as? String {
                                completionHandler(remoteVersion)
                                return
                            }
                        }
                    }
                }
            }
            completionHandler(nil)
        })
    }

    func alertView(alertView: UIAlertView, clickedButtonAtIndex buttonIndex: Int) {
        if buttonIndex == 1 {
            UIApplication.sharedApplication().openURL(NSURL(string: AuroraDownloadPageURL)!)
        }
    }
}
    
extension AppDelegate: MFMailComposeViewControllerDelegate {
    func sendFeedbackMailWithImage(image: UIImage) {
        if (MFMailComposeViewController.canSendMail()) {
            if let buildNumber = NSBundle.mainBundle().objectForInfoDictionaryKey(String(kCFBundleVersionKey)) as? NSString {
                let mailComposeViewController = MFMailComposeViewController()
                mailComposeViewController.mailComposeDelegate = self
                mailComposeViewController.setSubject("Feedback on iOS client version v\(appVersion) (\(buildNumber))")
                mailComposeViewController.setToRecipients(["ios-feedback@mozilla.com"])
                
                let imageData = UIImagePNGRepresentation(image)
                mailComposeViewController.addAttachmentData(imageData, mimeType: "image/png", fileName: "feedback.png")
                window?.rootViewController?.presentViewController(mailComposeViewController, animated: true, completion: nil)
            }
        }
    }
    
    func mailComposeController(mailComposeViewController: MFMailComposeViewController!, didFinishWithResult result: MFMailComposeResult, error: NSError!) {
        mailComposeViewController.dismissViewControllerAnimated(true, completion: nil)
    }
}
#endif

extension AppDelegate: UIApplicationDelegate {
    func application(application: UIApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        return true
    }

    func application(application: UIApplication, shouldRestoreApplicationState code: NSCoder) -> Bool {
        return true
    }
}

extension AppDelegate: UIViewControllerRestoration {
    class func viewControllerWithRestorationIdentifierPath(identifierComponents: [AnyObject], coder: NSCoder) -> UIViewController? {
        // There is only one restorationIdentifier in circulation.
        if let appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate {
            return appDelegate.window!.rootViewController
        }
        return nil
    }
}

extension AppDelegate: IntroViewControllerDelegate {
    func introViewControllerDidFinish(introViewController: IntroViewController) {
        introViewController.navigationController?.popToRootViewControllerAnimated(false)
    }

    func introViewControllerDidRequestToLogin(introViewController: IntroViewController) {
        // TODO When bug 1161151 has been resolved we can jump directly to the sign in screen
        let settingsNavigationController = SettingsNavigationController()
        settingsNavigationController.profile = profile
        settingsNavigationController.tabManager = browserViewController.tabManager
        window?.rootViewController?.presentViewController(settingsNavigationController, animated: true, completion: { () -> Void in
            introViewController.navigationController?.popToRootViewControllerAnimated(false)
        })
    }
}
