import Foundation
import WebKit

enum WebsiteDataBox {
    static func store(for appId: UUID) -> WKWebsiteDataStore {
        if #available(iOS 17.0, *) {
            return WKWebsiteDataStore(forIdentifier: appId)
        }
        return .default()
    }

    static func wipe(appId: UUID, completion: @escaping () -> Void) {
        let store = store(for: appId)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                completion()
            }
        }
    }

    static func estimatedBytes(appId: UUID, completion: @escaping (Int) -> Void) {
        if #available(iOS 17.0, *) {
            let store = store(for: appId)
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                completion(records.count)
            }
        } else {
            completion(0)
        }
    }
}
