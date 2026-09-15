import Foundation

enum AppResources {
    #if SWIFT_PACKAGE
    static let bundle = Bundle.module
    #else
    static let bundle = Bundle.main
    #endif
}
