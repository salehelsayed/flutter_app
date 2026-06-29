#if canImport(Flutter)
    import Flutter
#endif
#if canImport(FlutterMacOS)
    import FlutterMacOS
#endif
import Network

/// Allows to broadcast a given service to the local network.
@available(iOS 13.0, macOS 10.15, *)
class BonsoirServiceBroadcast: BonsoirAction {
    /// The advertised service.
    private let service: BonsoirService

    /// The reference to the registering..
    private var sdRef: DNSServiceRef?

    /// mknoon 175 patch: drains `DNSServiceProcessResult` OFF the main thread.
    /// Retained so `dispose()` can cancel it (and free `sdRef` race-free) before
    /// teardown. See PATCH.md / `start()`.
    private var dispatchSource: DispatchSourceRead?

    /// mknoon 175 patch: the function used to drain pending DNS-SD results.
    /// Production uses the real C call; the off-main unit test injects a
    /// delayed/instrumented shim so it can assert `start()` does not block the
    /// calling (main) thread without a live `mDNSResponder`
    /// (`BonsoirServiceBroadcastOffMainTest`).
    static var processResult: (DNSServiceRef?) -> DNSServiceErrorType = { DNSServiceProcessResult($0) }

    /// Initializes this class.
    public init(id: Int, printLogs: Bool, onDispose: @escaping () -> Void, messenger: FlutterBinaryMessenger, service: BonsoirService) {
        self.service = service
        super.init(id: id, action: "broadcast", logMessages: Generated.broadcastMessages, printLogs: printLogs, onDispose: onDispose, messenger: messenger)
    }

    /// Starts the broadcast.
    public func start() {
        var txtRecord = TXTRecordRef()
        TXTRecordCreate(&txtRecord, 0, nil)
        for (key, value) in service.attributes {
            guard let valueData = value.data(using: .utf8) else { continue }
            TXTRecordSetValue(&txtRecord, key, UInt8(valueData.count), [UInt8](valueData))
        }
        let error = DNSServiceRegister(&sdRef, 0, 0, service.name, service.type, "local.", service.host, CFSwapInt16HostToBig(UInt16(service.port)), TXTRecordGetLength(&txtRecord), TXTRecordGetBytesPtr(&txtRecord), BonsoirServiceBroadcast.registerCallback as DNSServiceRegisterReply, Unmanaged.passUnretained(self).toOpaque())
        if error == kDNSServiceErr_NoError {
            log(logMessages[Generated.broadcastInitialized]!, [service])
            // mknoon 175 patch: the original code called `DNSServiceProcessResult(sdRef)`
            // SYNCHRONOUSLY here, on the calling (iOS main) thread. That is a blocking
            // socket read until the `mDNSResponder` daemon replies; when Local Network
            // permission is pending/denied or the daemon is contended it blocked past
            // the 10s scene-update watchdog → 0x8BADF00D SIGKILL (crash
            // Runner-2026-06-29-131147.ips, thread 0:
            // __recvfrom_nocancel ← read_all ← DNSServiceProcessResult ←
            // BonsoirServiceBroadcast.start). Drain it on a background
            // DispatchSourceRead instead, exactly mirroring the in-package discovery
            // resolve path (BonsoirServiceDiscovery.resolveService) — which upstream
            // already moved off-main in 5.1.3 ("Fixed crashes in DNSServiceProcessResult
            // by using DispatchSourceRead") but never applied to this broadcast leg.
            guard let sdRef = sdRef else {
                return
            }
            let socket = DNSServiceRefSockFD(sdRef)
            if socket == -1 {
                onError(parameters: [service, kDNSServiceErr_Invalid], details: kDNSServiceErr_Invalid)
                dispose()
                return
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: DispatchQueue.global(qos: .userInitiated))
            source.setEventHandler {
                // Runs on the background queue → never blocks the main run loop.
                _ = BonsoirServiceBroadcast.processResult(sdRef)
            }
            source.setCancelHandler {
                // libdispatch guarantees the cancel handler runs AFTER the last
                // event-handler invocation has returned, exactly once → no
                // use-after-free / double-process on `sdRef`.
                DNSServiceRefDeallocate(sdRef)
            }
            source.activate()
            dispatchSource = source
        } else {
            onError(parameters: [service, error], details: error)
            dispose()
        }
    }

    override public func dispose() {
        // mknoon 175 patch: tear the off-main drain down FIRST. Cancelling the
        // source frees `sdRef` in its cancel handler (after any in-flight read),
        // so we must NOT also call `DNSServiceRefDeallocate` here when a source
        // exists (that would double-free). When `start()` failed before creating
        // a source, deallocate directly (pre-patch behavior, including the
        // safe `DNSServiceRefDeallocate(nil)` no-op when registration failed).
        if let source = dispatchSource {
            source.cancel()
            dispatchSource = nil
        } else {
            DNSServiceRefDeallocate(sdRef)
        }
        sdRef = nil
        onSuccess(eventId: Generated.broadcastStopped, service: service)
        super.dispose()
    }

    /// Callback triggered by`DNSServiceRegister`.
    private static let registerCallback: DNSServiceRegisterReply = { _, _, errorCode, name, _, _, context in
        let broadcast = Unmanaged<BonsoirServiceBroadcast>.fromOpaque(context!).takeUnretainedValue()
        // mknoon 175 patch: with the drain moved off-main, this C callback now runs
        // on the background queue. `FlutterEventSink` is main-thread-only, so hop to
        // main before touching it — mirroring BonsoirServiceDiscovery.resolveCallback.
        // `name` is only valid for the callback's duration, so copy it to a Swift
        // String before the async hop.
        if errorCode == kDNSServiceErr_NoError {
            let newName = name == nil ? nil : String(cString: name!)
            DispatchQueue.main.async {
                if let newName = newName, broadcast.service.name != newName {
                    let oldName = broadcast.service.name
                    broadcast.service.name = newName
                    broadcast.onSuccess(eventId: Generated.broadcastNameAlreadyExists, service: broadcast.service, parameters: [oldName])
                }
                broadcast.onSuccess(eventId: Generated.broadcastStarted, service: broadcast.service)
            }
        } else {
            DispatchQueue.main.async {
                broadcast.onError(parameters: [broadcast.service, errorCode], details: errorCode)
                broadcast.dispose()
            }
        }
    }
}
