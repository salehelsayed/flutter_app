#if canImport(receive_sharing_intent)
import receive_sharing_intent
#endif

class ShareViewController: RSIShareViewController {
    override func shouldAutoRedirect() -> Bool {
        true
    }
}
