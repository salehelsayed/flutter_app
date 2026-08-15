import Foundation
import UIKit

/// Runner's sole native owner for app-visibility lifecycle projection. UIKit
/// and scene notifications deliberately converge on the same semantic writer,
/// so duplicate callbacks cannot advance the generation or clear an
/// interleaved Flutter route publication.
final class IosAppVisibilityCoordinator {
  private enum CallbackSource {
    case application
    case scene
  }

  private let store: IosAppVisibilitySnapshotStore
  private let notificationCenter: NotificationCenter
  private let queue = DispatchQueue(label: "mknoon.app_visibility.ios")
  private let queueKey = DispatchSpecificKey<Void>()
  private var observers: [NSObjectProtocol] = []
  private var started = false

  convenience init?() {
    guard let store = IosAppVisibilitySnapshotStore() else { return nil }
    self.init(store: store)
  }

  init(
    store: IosAppVisibilitySnapshotStore,
    notificationCenter: NotificationCenter = .default
  ) {
    self.store = store
    self.notificationCenter = notificationCenter
    queue.setSpecific(key: queueKey, value: ())
  }

  deinit {
    stop()
  }

  /// Must run before Flutter receives a messenger. The forced transition
  /// invalidates an incumbent route even when the prior process also ended in
  /// INACTIVE.
  func start(observeSystemNotifications: Bool = true) {
    synchronized {
      guard !started else { return }
      started = true
      _ = store.recordColdStart(lifecycle: .inactive)
      guard observeSystemNotifications else { return }
      installObservers()
    }
  }

  func stop() {
    synchronized {
      guard started else { return }
      for observer in observers {
        notificationCenter.removeObserver(observer)
      }
      observers.removeAll()
      started = false
    }
  }

  func readSnapshot() -> IosAppVisibilitySnapshotEnvelope? {
    synchronized { store.readSnapshot() }
  }

  func publishVisibleConversation(
    digest: String?,
    lifecycleGeneration: Int64
  ) -> IosAppVisibilityPublishResult {
    synchronized {
      store.publishVisibleConversation(
        digest: digest,
        lifecycleGeneration: lifecycleGeneration
      )
    }
  }

  func handleApplicationLifecycleForTesting(
    _ lifecycle: IosAppVisibilityLifecycle
  ) {
    handle(lifecycle, source: .application)
  }

  func handleSceneLifecycleForTesting(
    _ lifecycle: IosAppVisibilityLifecycle
  ) {
    handle(lifecycle, source: .scene)
  }

  private func installObservers() {
    observe(UIApplication.willResignActiveNotification) { [weak self] in
      self?.handle(.inactive, source: .application)
    }
    observe(UIApplication.didEnterBackgroundNotification) { [weak self] in
      self?.handle(.background, source: .application)
    }
    observe(UIApplication.willEnterForegroundNotification) { [weak self] in
      self?.handle(.inactive, source: .application)
    }
    observe(UIApplication.didBecomeActiveNotification) { [weak self] in
      self?.handle(.foregroundActive, source: .application)
    }

    observe(UIScene.willDeactivateNotification) { [weak self] in
      self?.handle(.inactive, source: .scene)
    }
    observe(UIScene.didEnterBackgroundNotification) { [weak self] in
      self?.handle(.background, source: .scene)
    }
    observe(UIScene.willEnterForegroundNotification) { [weak self] in
      self?.handle(.inactive, source: .scene)
    }
    observe(UIScene.didActivateNotification) { [weak self] in
      self?.handle(.foregroundActive, source: .scene)
    }
  }

  private func observe(
    _ name: Notification.Name,
    handler: @escaping () -> Void
  ) {
    observers.append(notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: nil
    ) { _ in
      handler()
    })
  }

  private func handle(
    _ lifecycle: IosAppVisibilityLifecycle,
    source _: CallbackSource
  ) {
    synchronized {
      _ = store.transitionLifecycle(to: lifecycle)
    }
  }

  private func synchronized<T>(_ operation: () -> T) -> T {
    if DispatchQueue.getSpecific(key: queueKey) != nil {
      return operation()
    }
    return queue.sync(execute: operation)
  }
}
