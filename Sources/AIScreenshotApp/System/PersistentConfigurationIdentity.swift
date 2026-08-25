enum PersistentConfigurationIdentity {
    // These identifiers are part of the upgrade compatibility contract.
    // Changing them requires an explicit migration from the previous values.
    static let bundleIdentifier = "com.kangarooking.AIScreenshot"
    static let keychainService = "com.kangarooking.AIScreenshot.providers"
    static let multimodalProviderAccount = "openai-compatible-default"
    static let translationProviderAccount = "deepseek-translation-default"
    static let deepSeekOCRAccount = "deepseek-ocr-2"
}
