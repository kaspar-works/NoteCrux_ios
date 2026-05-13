import XCTest

final class NoteCruxUITests: XCTestCase {

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-appLockEnabled", "NO",
            "-nc_seedDemo", "YES",
            "-NC_SCREENSHOT_MODE"
        ]
        app.launch()

        // Dismiss the Calendar permission prompt if it surfaces during
        // splash/dashboard load — otherwise the Dashboard screenshot is
        // dominated by the system dialog.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dontAllow = springboard.buttons["Don’t Allow"]
        if dontAllow.waitForExistence(timeout: 4) {
            dontAllow.tap()
        }
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()

        // Let the splash + initial view settle
        sleep(3)

        // 1. Dashboard (Home tab, with seeded meetings + follow-ups)
        snapshot("01_Dashboard")

        // 2. Meeting detail — tap the first meeting card on the dashboard
        let firstMeeting = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Q2 Product")).firstMatch
        if firstMeeting.waitForExistence(timeout: 3) {
            firstMeeting.tap()
            sleep(2)
            snapshot("02_MeetingDetail")
            // back to dashboard
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists { backButton.tap() }
            sleep(1)
        }

        // 3. Tasks tab
        tap(app: app, label: "Tasks")
        sleep(1)
        snapshot("03_Tasks")

        // 4. Insights tab
        tap(app: app, label: "Insights")
        sleep(1)
        snapshot("04_Insights")

        // 5. Settings tab
        tap(app: app, label: "Settings")
        sleep(1)
        snapshot("05_Settings")

        // 6. Remove Ads paywall sheet
        let removeAdsButton = app.buttons["Remove Ads"]
        if removeAdsButton.waitForExistence(timeout: 3) {
            removeAdsButton.firstMatch.tap()
            sleep(1)
            snapshot("06_RemoveAds")

            // Close the paywall sheet
            let closeButton = app.buttons.matching(NSPredicate(format: "label == %@", "xmark")).firstMatch
            if closeButton.exists {
                closeButton.tap()
            } else {
                // Fallback: swipe down to dismiss sheet
                app.swipeDown(velocity: .fast)
            }
            sleep(1)
        }

        // 7. Data & Privacy detail (on-device privacy messaging)
        let dataPrivacyCell = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Data & Privacy")).firstMatch
        if dataPrivacyCell.waitForExistence(timeout: 3) {
            dataPrivacyCell.tap()
            sleep(2)
            snapshot("07_Privacy")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
        }

        // 8. Storage management
        let storageCell = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Storage")).firstMatch
        if storageCell.waitForExistence(timeout: 3) {
            storageCell.tap()
            sleep(2)
            snapshot("08_Storage")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
        }

        // 9. Theme settings
        let themeCell = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Theme")).firstMatch
        if themeCell.waitForExistence(timeout: 3) {
            themeCell.tap()
            sleep(2)
            snapshot("09_Theme")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
        }

        // 10. Back to Home — meeting detail scrolled to action items
        tap(app: app, label: "Home")
        sleep(1)
        let firstMeetingAgain = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Q2 Product")).firstMatch
        if firstMeetingAgain.waitForExistence(timeout: 3) {
            firstMeetingAgain.tap()
            sleep(2)
            // Scroll down to reveal action items / summary
            app.swipeUp(velocity: .slow)
            sleep(1)
            snapshot("10_ActionItems")
        }
    }

    private func tap(app: XCUIApplication, label: String) {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 3) {
            button.firstMatch.tap()
        }
    }
}
