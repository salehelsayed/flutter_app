import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupId = "group.com.example.makerGenerated.share"
    private let sharedKey = "ShareKey"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var sharedItems: [[String: Any]] = []

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        if let url = data as? URL {
                            sharedItems.append([
                                "type": "url",
                                "path": url.absoluteString,
                            ])
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        if let text = data as? String {
                            sharedItems.append([
                                "type": "text",
                                "path": text,
                            ])
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        guard let self = self else { return }
                        if let url = data as? URL,
                           let destPath = self.copyToSharedContainer(url) {
                            sharedItems.append([
                                "type": "image",
                                "path": destPath,
                            ])
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.movie.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        guard let self = self else { return }
                        if let url = data as? URL,
                           let destPath = self.copyToSharedContainer(url) {
                            sharedItems.append([
                                "type": "video",
                                "path": destPath,
                            ])
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if !sharedItems.isEmpty {
                let defaults = UserDefaults(suiteName: self.appGroupId)
                if let jsonData = try? JSONSerialization.data(withJSONObject: sharedItems) {
                    defaults?.set(jsonData, forKey: self.sharedKey)
                }
            }
            self.openMainApp()
            self.completeRequest()
        }
    }

    private func copyToSharedContainer(_ sourceURL: URL) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }

        let destURL = containerURL.appendingPathComponent(sourceURL.lastPathComponent)
        try? FileManager.default.removeItem(at: destURL)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL.path
        } catch {
            return nil
        }
    }

    private func openMainApp() {
        let urlScheme = "ShareMedia-com.example.makerGenerated"
        guard let url = URL(string: "\(urlScheme)://share") else { return }
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = responder?.next
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
