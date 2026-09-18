import Foundation

/// Observations must show a running process before its absence can prove retirement.
/// Idle qualification also requires positive liveness observations across the lifetime;
/// a delayed observation of an already dead worker cannot pass as successful expiry.
struct PrivilegeProofRetirement {
  private var firstAlive: Duration?
  private var lastAlive: Duration?

  mutating func observe(
    jobPresent: Bool, processPresent: Bool, elapsed: Duration,
    mode: PrivilegeProofMode
  ) throws -> Bool {
    if jobPresent && processPresent {
      if firstAlive == nil { firstAlive = elapsed }
      lastAlive = elapsed
      return false
    }
    guard !jobPresent && !processPresent else { return false }
    guard let firstAlive, let lastAlive else {
      throw PrivilegeProofError.retirementUnverified
    }
    // Allow one second for launch and polling latency. Unknown or late observations
    // fail conservatively and require another qualification run.
    if mode == .idleExpiry,
      lastAlive - firstAlive < .seconds(PrivilegeProofIdentity.lifetime - 1)
    {
      throw PrivilegeProofError.workerExitedEarly
    }
    return true
  }
}
