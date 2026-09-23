#if os(macOS)
  import Foundation
  import OmarchyAppleInstallerTrustCore

  /// Holds which release channel this run of the app reads.
  ///
  /// The choice lives in memory only: every launch opens on the bundled
  /// default, and one app process can never change another's channel. It only
  /// chooses between the two URLs already baked into the signed app bundle, so
  /// it can never introduce a source the app was not built to trust.
  public struct ReleaseChannelPreference: Sendable {
    public final class Store: @unchecked Sendable {
      private let lock = NSLock()
      private var value: ReleaseChannel?

      public init() {}

      var channel: ReleaseChannel? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
      }
    }

    public static let processStore = Store()

    private let store: Store

    public init(store: Store = processStore) {
      self.store = store
    }

    /// The choice made in this run, or `nil` when none was made.
    public var stored: ReleaseChannel? { store.channel }

    public func select(_ channel: ReleaseChannel?) {
      store.channel = channel
    }

    public func resolve(descriptorDefault: ReleaseChannel) -> ReleaseChannel {
      stored ?? descriptorDefault
    }

    /// The channel the next preparation fetches. The window and the download
    /// both resolve through here, so they cannot disagree.
    public func resolve(configuration: InstallerReleaseConfiguration) -> ReleaseChannel {
      resolve(descriptorDefault: configuration.defaultChannel)
    }

    /// `nil` when the app bundle carries no valid release descriptor; nothing
    /// can be fetched then either.
    public func resolveFromMainBundle() -> ReleaseChannel? {
      guard
        let configuration = try? InstallerReleaseConfigurationLocator()
          .loadFromMainBundle()
      else { return nil }
      return resolve(configuration: configuration)
    }
  }
#endif
