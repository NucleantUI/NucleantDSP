//
//  NativeState.swift
//  NucleantDSP
//

/// The state of one of CNucleantDSP's processors (an opaque `ndsp_*` made by
/// its `*_create`), held by a Swift processor as a value: freed when the
/// last value holding it goes, and copied with its `*_copy` before a write
/// while another value still shares it. So a copy of a processor carries on
/// from the same state, independently of the original.
struct NativeState: @unchecked Sendable {
    typealias Copy = @convention(c) (OpaquePointer?) -> OpaquePointer?
    typealias Destroy = @convention(c) (OpaquePointer?) -> Void

    private final class Storage {
        let pointer: OpaquePointer
        let channels: Int
        let sampleRate: Double
        let destroy: Destroy

        init(_ pointer: OpaquePointer, channels: Int, sampleRate: Double, destroy: Destroy) {
            self.pointer = pointer
            self.channels = channels
            self.sampleRate = sampleRate
            self.destroy = destroy
        }

        deinit { destroy(pointer) }
    }

    private let copy: Copy
    private let destroy: Destroy
    private var storage: Storage?

    init(copy: Copy, destroy: Destroy) {
        self.copy = copy
        self.destroy = destroy
    }

    /// The state for `channels` channels at `sampleRate`, to write to: made
    /// by `make` the first time and whenever either changes (a processor
    /// whose state does not depend on the rate passes 0), and copied first
    /// while it is shared. Nil if C could not allocate it.
    mutating func pointer(channels: Int, sampleRate: Double = 0, make: () -> OpaquePointer?) -> OpaquePointer? {
        if storage?.channels != channels || storage?.sampleRate != sampleRate {
            storage = make().map { Storage($0, channels: channels, sampleRate: sampleRate, destroy: destroy) }
        } else if !isKnownUniquelyReferenced(&storage), let shared = storage {
            storage = copy(shared.pointer).map { Storage($0, channels: channels, sampleRate: sampleRate, destroy: destroy) }
        }
        return storage?.pointer
    }
}

extension MutableSpan<Float> {
    /// The samples as a pointer, for C, and how many frames of `channels`
    /// they hold.
    mutating func withFrames<R>(channels: Int, _ body: (UnsafeMutablePointer<Float>, Int) -> R) -> R? {
        let frames = count / channels
        guard frames > 0 else { return nil }
        return withUnsafeMutableBufferPointer { samples in
            samples.baseAddress.map { body($0, frames) }
        }
    }
}
