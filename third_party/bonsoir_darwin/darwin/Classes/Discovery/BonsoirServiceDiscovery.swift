#if canImport(Flutter)
    import Flutter
#endif
#if canImport(FlutterMacOS)
    import FlutterMacOS
#endif
import Network

/// Allows to find net services on local network.
@available(iOS 13.0, macOS 10.15, *)
class BonsoirServiceDiscovery: BonsoirAction {
    /// The type we're listening to.
    private let type: String
    
    /// The current browser instance.
    private let browser: NWBrowser
    
    /// Contains all found services.
    private var services: [BonsoirService] = []
    
    /// Each read source owns its DNS-SD handle until its cancel handler runs.
    private struct PendingResolution {
        let sdRef: DNSServiceRef
        let source: DispatchSourceRead
    }
    private var pendingResolution: [PendingResolution] = []
    private let resolutionQueue = DispatchQueue(label: "fr.skyost.bonsoir.discovery.resolve", qos: .userInitiated)
    private var isDisposed = false

    /// Initializes this class.
    public init(id: Int, printLogs: Bool, onDispose: @escaping () -> Void, messenger: FlutterBinaryMessenger, type: String) {
        self.type = type
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: .tcp)
        super.init(id: id, action: "discovery", logMessages: Generated.discoveryMessages, printLogs: printLogs, onDispose: onDispose, messenger: messenger)
        browser.stateUpdateHandler = stateHandler
        browser.browseResultsChangedHandler = browseHandler
    }
    
    /// Finds a service amongst discovered services.
    private func findService(_ name: String, _ type: String? = nil) -> BonsoirService? {
        return services.first(where: { $0.name == name && (type == nil || $0.type == type) })
    }
    
    /// Handles state changes.
    func stateHandler(_ newState: NWBrowser.State) {
        switch newState {
        case .ready:
            onSuccess(eventId: Generated.discoveryStarted, parameters: [type])
        case .failed(let error):
            let details: Any?
            if #available(iOS 16.4, macOS 13.3, *) {
                details = error.errorCode
            } else {
                details = error.debugDescription
            }
            onError(parameters: [error], details: details)
            dispose()
        case .cancelled:
            onSuccess(eventId: Generated.discoveryStopped, parameters: [type])
            dispose()
        default:
            break
        }
    }
    
    /// Handles the browsing of services.
    func browseHandler(_ newResults: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case .service(let name, let type, _, _) = result.endpoint {
                    var service = findService(name, type)
                    if service != nil {
                        break
                    }
                    service = BonsoirService(name: name, type: type, port: 0, host: nil, attributes: [:])
                    if case .bonjour(let records) = result.metadata {
                        service!.attributes = records.dictionary
                    }
                    onSuccess(eventId: Generated.discoveryServiceFound, service: service)
                    services.append(service!)
                }
            case .removed(let result):
                if case .service(let name, let type, _, _) = result.endpoint {
                    guard let service = findService(name, type) else {
                        break
                    }
                    onSuccess(eventId: Generated.discoveryServiceLost, service: service)
                    if let index = services.firstIndex(where: { $0 === service }) {
                        services.remove(at: index)
                    }
                }
            case .changed(let old, let new, _):
                if case .service(let newName, let newType, _, _) = new.endpoint {
                    if case .service(let oldName, let oldType, _, _) = old.endpoint {
                        guard let service = findService(oldName) else {
                            break
                        }
                        var newAttributes: [String: String]
                        if case .bonjour(let newRecords) = new.metadata {
                            newAttributes = newRecords.dictionary
                        } else {
                            newAttributes = service.attributes
                        }
                        if oldName == newName && oldType == newType && newAttributes == service.attributes {
                            break
                        }
                        onSuccess(eventId: Generated.discoveryServiceLost, message: "A Bonsoir service has changed : %s.", service: service)
                        service.name = newName
                        service.type = newType
                        service.attributes = newAttributes
                        onSuccess(eventId: Generated.discoveryServiceFound, message: "New service is \(service)", service: service)
                    }
                }
            default:
                break
            }
        }
    }
    
    /// Resolves a service.
    public func resolveService(name: String, type: String) -> Bool {
        guard !isDisposed else { return false }
        guard let service = findService(name, type) else {
            onError(message: Generated.discoveryUndiscoveredServiceResolveFailed, parameters: [name, type])
            return false
        }
        var sdRef: DNSServiceRef? = nil
        let error = DNSServiceResolve(&sdRef, 0, 0, name, type, "local.", BonsoirServiceDiscovery.resolveCallback, Unmanaged.passUnretained(self).toOpaque())
        guard error == kDNSServiceErr_NoError, let sdRef = sdRef else {
            onSuccess(eventId: Generated.discoveryServiceResolveFailed, service: service, parameters: [error])
            if let sdRef = sdRef { DNSServiceRefDeallocate(sdRef) }
            return false
        }

        let socket = DNSServiceRefSockFD(sdRef)
        if socket == -1 {
            onSuccess(eventId: Generated.discoveryServiceResolveFailed, service: service, parameters: [])
            DNSServiceRefDeallocate(sdRef)
            return false
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: resolutionQueue)
        source.setEventHandler { [weak self] in
            // Keep the callback context alive while DNSServiceProcessResult runs.
            guard let self = self else { return }
            let result = DNSServiceProcessResult(sdRef)
            if result != kDNSServiceErr_NoError {
                DispatchQueue.main.async { [weak self] in
                    self?.failResolution(sdRef: sdRef, name: name, type: type, error: result)
                }
            }
        }
        source.setCancelHandler {
            // This runs on resolutionQueue after any active read handler returns.
            // No other path may free a handle once its source is activated.
            DNSServiceRefDeallocate(sdRef)
        }
        pendingResolution.append(PendingResolution(sdRef: sdRef, source: source))
        source.activate()
        return true
    }
    
    /// Stops the resolution of the given service.
    private func stopResolution(sdRef: DNSServiceRef) {
        guard let index = pendingResolution.firstIndex(where: { $0.sdRef == sdRef }) else { return }
        let resolution = pendingResolution.remove(at: index)
        resolution.source.cancel()
    }

    private func failResolution(sdRef: DNSServiceRef, name: String, type: String, error: DNSServiceErrorType) {
        guard pendingResolution.contains(where: { $0.sdRef == sdRef }) else { return }
        if let service = findService(name, type) {
            onSuccess(eventId: Generated.discoveryServiceResolveFailed, service: service, parameters: [error])
        } else {
            onError(message: Generated.discoveryServiceResolveFailed, parameters: ["nil", error])
        }
        stopResolution(sdRef: sdRef)
    }
    
    /// Starts the discovery.
    public func start() {
        browser.start(queue: .main)
    }
    
    override public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        for resolution in pendingResolution { resolution.source.cancel() }
        pendingResolution.removeAll()
        services.removeAll()
        if [.setup, .ready].contains(browser.state) {
            browser.cancel()
        }
        super.dispose()
    }
    
    /// Callback triggered by`DNSServiceResolve`.
    private static let resolveCallback: DNSServiceResolveReply = { sdRef, _, _, errorCode, fullName, hosttarget, port, _, _, context in
        guard let sdRef = sdRef, let context = context else { return }
        let discovery = Unmanaged<BonsoirServiceDiscovery>.fromOpaque(context).takeUnretainedValue()
        // DNS-SD owns these C strings only for the duration of this callback.
        let resolvedName = fullName.map { String(cString: $0) }
        let resolvedHost = hosttarget.map { String(cString: $0) }
        DispatchQueue.main.async {
            guard discovery.pendingResolution.contains(where: { $0.sdRef == sdRef }) else { return }
            let service = resolvedName
                .flatMap { parseBonjourFqdn(unescapeAscii($0)) }
                .flatMap { discovery.findService($0.0, $0.1) }
            if let service = service, errorCode == kDNSServiceErr_NoError {
                service.host = resolvedHost
                service.port = Int(CFSwapInt16BigToHost(port))
                discovery.onSuccess(eventId: Generated.discoveryServiceResolved, service: service)
            } else if let service = service {
                discovery.onSuccess(eventId: Generated.discoveryServiceResolveFailed, service: service, parameters: [errorCode])
            } else {
                discovery.onError(message: Generated.discoveryServiceResolveFailed, parameters: ["nil", errorCode])
            }
            discovery.stopResolution(sdRef: sdRef)
        }
    }
    
    /// Allows to unescape services FQDN.
    private static func unescapeAscii(_ inputString: String) -> String {
        let input = inputString.replacingOccurrences(of: "\\.", with: ".")
        var result = ""
        var i = 0
        while i < input.count {
            if input[i] == "\\" && i + 1 < input.count {
                var asciiCode = ""
                var j = 1
                while j < 4 {
                    if i + j >= input.count || !String(input[i + j]).isNumeric {
                        break
                    }
                    asciiCode += String(input[i + j])
                    j += 1
                }
                if let code = Int(asciiCode), let unicodeScalar = UnicodeScalar(code) {
                    result += String(unicodeScalar)
                } else {
                    result += "\\\(asciiCode)"
                }
                i += (j - 1)
            } else {
                result += String(input[i])
            }
            
            i += 1
        }
        return result
    }

    /// Parses a Bonjour FQDN.
    private static func parseBonjourFqdn(_ fqdn: String) -> (String, String)? {
        let regexPattern = "^(.*?)\\._(.*?)\\.?(?:local)?\\.?$"
        let regex = try! NSRegularExpression(pattern: regexPattern, options: [])
        if let match = regex.firstMatch(in: fqdn, options: [], range: NSRange(location: 0, length: fqdn.utf16.count)) {
            let serviceName = (fqdn as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let serviceType = "_\((fqdn as NSString).substring(with: match.range(at: 2)))"
            return (serviceName, serviceType)
        }
        return nil
    }
}

extension String {
    var isNumeric: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
    
    subscript(i: Int) -> String {
        return self[i ..< i + 1]
    }
    
    func substring(fromIndex: Int) -> String {
        return self[min(fromIndex, count) ..< count]
    }
    
    func substring(toIndex: Int) -> String {
        return self[0 ..< max(0, toIndex)]
    }
    
    subscript(r: Range<Int>) -> String {
        let range = Range(uncheckedBounds: (lower: max(0, min(count, r.lowerBound)),
                                            upper: min(count, max(0, r.upperBound))))
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(start, offsetBy: range.upperBound - range.lowerBound)
        return String(self[start ..< end])
    }
}
