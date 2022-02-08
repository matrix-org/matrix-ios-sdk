import Foundation

internal extension FileManager {
    
    /**
     Get the url of the primary Matrix application group container.
     */
    @objc func applicationGroupContainerURL() -> URL? {
        guard let appGroupId = MXSDKOptions.sharedInstance().applicationGroupIdentifier else {
            return nil
        }
        return containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }
}
