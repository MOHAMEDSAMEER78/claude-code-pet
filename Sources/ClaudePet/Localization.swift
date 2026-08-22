import Foundation

/// Localization groundwork: a `Localizable.strings` table (English only for
/// now) plus this lookup helper. SPM executable targets don't localize via
/// `Bundle.main` the way an app-bundle target does, so this goes through
/// `Bundle.module` (generated because the target declares `resources:`)
/// explicitly. Not every string in the app is wrapped yet - this covers the
/// menu bar (the highest-traffic surface) as the first pass; the rest of the
/// UI can be migrated the same way incrementally.
func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: .module, comment: comment)
}
