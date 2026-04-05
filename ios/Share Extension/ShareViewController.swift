#if canImport(receive_sharing_intent)
import receive_sharing_intent
#endif
import UIKit

final class ShareViewController: UIViewController {
    private var hostAppBundleIdentifier = ""
    private var appGroupId = ""
    private var sharedMedia: [SharedMediaFile] = []
    private var isProcessingShare = false
    private var hasCompleted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
        configureLoadingView()
        beginProcessingShare()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginProcessingShare()
    }

    private func beginProcessingShare() {
        guard !isProcessingShare else { return }
        isProcessingShare = true
        processIncomingItems()
    }

    private func configureLoadingView() {
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.startAnimating()

        let label = UILabel()
        label.text = "Preparing share..."
        label.textColor = UIColor.white.withAlphaComponent(0.82)
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func processIncomingItems() {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = content.attachments,
              !attachments.isEmpty else {
            dismissWithError()
            return
        }

        let dispatchGroup = DispatchGroup()
        let stateQueue = DispatchQueue(label: "com.mknoon.shareextension.state")
        var collectedMedia: [Int: SharedMediaFile] = [:]
        var didFail = false
        var supportedAttachmentCount = 0

        for (index, attachment) in attachments.enumerated() {
            guard let type = matchingShareType(for: attachment) else {
                continue
            }

            supportedAttachmentCount += 1
            dispatchGroup.enter()
            loadSharedMedia(from: attachment, type: type) { media in
                defer { dispatchGroup.leave() }
                stateQueue.sync {
                    guard let media else {
                        didFail = true
                        return
                    }
                    collectedMedia[index] = media
                }
            }
        }

        guard supportedAttachmentCount > 0 else {
            dismissWithError()
            return
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let orderedMedia = stateQueue.sync {
                attachments.indices.compactMap { collectedMedia[$0] }
            }
            guard !didFail, orderedMedia.count == supportedAttachmentCount else {
                self.dismissWithError()
                return
            }

            self.sharedMedia = orderedMedia
            self.saveAndRedirect()
        }
    }

    private func matchingShareType(for attachment: NSItemProvider) -> SharedMediaType? {
        for type in SharedMediaType.allCases where attachment.hasItemConformingToTypeIdentifier(type.toUTTypeIdentifier) {
            return type
        }
        return nil
    }

    private func loadSharedMedia(
        from attachment: NSItemProvider,
        type: SharedMediaType,
        completion: @escaping (SharedMediaFile?) -> Void
    ) {
        switch type {
        case .text:
            attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { data, error in
                guard error == nil, let text = data as? String else {
                    completion(nil)
                    return
                }
                completion(
                    SharedMediaFile(
                        path: text,
                        mimeType: "text/plain",
                        type: .text
                    )
                )
            }
        case .url:
            attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { data, error in
                guard error == nil, let url = data as? URL else {
                    completion(nil)
                    return
                }
                completion(SharedMediaFile(path: url.absoluteString, type: .url))
            }
        case .image, .video, .file:
            loadFileBackedRepresentation(from: attachment, type: type, completion: completion)
        }
    }

    private func loadFileBackedRepresentation(
        from attachment: NSItemProvider,
        type: SharedMediaType,
        completion: @escaping (SharedMediaFile?) -> Void
    ) {
        attachment.loadInPlaceFileRepresentation(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] url, _, error in
            guard let self else {
                completion(nil)
                return
            }
            if error == nil, let url {
                completion(self.sharedMediaFile(fromFileURL: url, type: type))
                return
            }

            attachment.loadFileRepresentation(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] url, error in
                guard let self else {
                    completion(nil)
                    return
                }
                if error == nil, let url {
                    completion(self.sharedMediaFile(fromFileURL: url, type: type))
                    return
                }
                self.loadBinaryItemFallback(from: attachment, type: type, completion: completion)
            }
        }
    }

    private func loadBinaryItemFallback(
        from attachment: NSItemProvider,
        type: SharedMediaType,
        completion: @escaping (SharedMediaFile?) -> Void
    ) {
        attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] data, error in
            guard let self, error == nil else {
                completion(nil)
                return
            }
            if let url = data as? URL {
                completion(self.sharedMediaFile(fromFileURL: url, type: type))
                return
            }
            if let image = data as? UIImage, type == .image {
                completion(self.sharedMediaFile(fromImage: image))
                return
            }
            completion(nil)
        }
    }

    private func sharedMediaFile(fromImage image: UIImage) -> SharedMediaFile? {
        let hasAlpha = imageHasAlpha(image)
        let data = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 1)
        let fileExtension = hasAlpha ? "png" : "jpg"
        let mimeType = hasAlpha ? "image/png" : "image/jpeg"
        return writeSharedImageData(data, fileExtension: fileExtension, mimeType: mimeType)
    }

    private func sharedMediaFile(fromFileURL url: URL, type: SharedMediaType) -> SharedMediaFile? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            return nil
        }

        let fileName = getFileName(from: url, type: type)
        let destinationURL = containerURL.appendingPathComponent(fileName)
        guard copyFile(at: url, to: destinationURL),
              let decodedPath = destinationURL.absoluteString.removingPercentEncoding else {
            return nil
        }

        return SharedMediaFile(
            path: decodedPath,
            mimeType: url.mimeType(),
            type: type
        )
    }

    private func writeSharedImageData(
        _ data: Data?,
        fileExtension: String,
        mimeType: String
    ) -> SharedMediaFile? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ),
        let data else {
            return nil
        }

        let destinationURL = containerURL.appendingPathComponent(
            "\(UUID().uuidString).\(fileExtension)"
        )
        guard writeTempFile(data, to: destinationURL),
              let decodedPath = destinationURL.absoluteString.removingPercentEncoding else {
            return nil
        }

        return SharedMediaFile(path: decodedPath, mimeType: mimeType, type: .image)
    }

    private func loadIds() {
        guard let shareExtensionBundleIdentifier = Bundle.main.bundleIdentifier,
              let lastIndex = shareExtensionBundleIdentifier.lastIndex(of: ".") else {
            return
        }

        hostAppBundleIdentifier = String(shareExtensionBundleIdentifier[..<lastIndex])
        let defaultAppGroupId = "group.\(hostAppBundleIdentifier)"
        let customAppGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = customAppGroupId ?? defaultAppGroupId
    }

    private func saveAndRedirect() {
        guard !hasCompleted else { return }
        hasCompleted = true

        let userDefaults = UserDefaults(suiteName: appGroupId)
        userDefaults?.set(toData(data: sharedMedia), forKey: kUserDefaultsKey)
        userDefaults?.set(nil, forKey: kUserDefaultsMessageKey)
        userDefaults?.synchronize()
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            dismissWithError()
            return
        }

        var responder = self as UIResponder?
        if #available(iOS 18.0, *) {
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                }
                responder = responder?.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            while responder != nil {
                if responder?.responds(to: selectorOpenURL) == true {
                    _ = responder?.perform(selectorOpenURL, with: url)
                }
                responder = responder?.next
            }
        }

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func dismissWithError() {
        guard !hasCompleted else { return }
        hasCompleted = true

        let alert = UIAlertController(
            title: "Error",
            message: "Error loading data",
            preferredStyle: .alert
        )
        let action = UIAlertAction(title: "Dismiss", style: .cancel) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
        alert.addAction(action)
        present(alert, animated: true)
    }

    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image:
                name = UUID().uuidString + ".png"
            case .video:
                name = UUID().uuidString + ".mp4"
            case .text:
                name = UUID().uuidString + ".txt"
            case .file, .url:
                name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ data: Data, to destinationURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try data.write(to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    private func copyFile(at sourceURL: URL, to destinationURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return true
        } catch {
            return false
        }
    }

    private func toData(data: [SharedMediaFile]) -> Data {
        let encodedData = try? JSONEncoder().encode(data)
        return encodedData ?? Data()
    }

    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let alphaInfo = image.cgImage?.alphaInfo else {
            return false
        }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast, .alphaOnly:
            return false
        @unknown default:
            return true
        }
    }
}
