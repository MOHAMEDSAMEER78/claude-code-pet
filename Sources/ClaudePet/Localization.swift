import Foundation

func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: .module, comment: comment)
}
