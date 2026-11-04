import AppKit
import Combine
import CoreAudio
import Darwin
import Foundation

enum MusicSpectrumCaptureStatus: Equatable {
    case idle, waiting, capturing, failed(Int32), unsupported
}

/// Activity source adapter. Owns capture resources, never windows or activity priority.
@MainActor
final class MusicSpectrumSource: ObservableObject {
    static let shared = MusicSpectrumSource()
    @Published private(set) var status: MusicSpectrumCaptureStatus = .idle
    private var subscription: AnyCancellable?
    private let worker = MusicSpectrumWorker()

    private init() {
        subscription = ActivityCoordinator.shared.$spectrumRequest.removeDuplicates().sink { [weak self] request in
            guard let self else { return }
            self.worker.configure(request, frame: { request, levels in
                Task { @MainActor in ActivityCoordinator.shared.receiveSpectrum(levels, for: request) }
            }, status: { [weak self] lease, status in
                Task { @MainActor [weak self] in
                    guard ActivityCoordinator.shared.spectrumRequest?.id == lease else { return }
                    self?.status = status
                }
            })
            if request == nil { self.status = .idle }
        }
    }

    func retry() { worker.retry() }
    func stop() { subscription?.cancel(); subscription = nil; worker.stop() }
}

/// All HAL lifecycle operations run on a serial worker, outside the UI thread.
private final class MusicSpectrumWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AirIsland.music-spectrum.lifecycle", qos: .utility)
    private var poll: DispatchSourceTimer?
    private var session: AnyObject?
    private var request: MusicSpectrumRequest?
    private var processIDs: [AudioObjectID] = []
    private var didAttempt = false
    private var outputDevice: AudioObjectID = kAudioObjectUnknown
    private var lastFrame: TimeInterval = 0
    private var frame: ((MusicSpectrumRequest, [Double]) -> Void)?
    private var status: ((UUID?, MusicSpectrumCaptureStatus) -> Void)?

    func configure(_ request: MusicSpectrumRequest?, frame: @escaping (MusicSpectrumRequest, [Double]) -> Void,
                   status: @escaping (UUID?, MusicSpectrumCaptureStatus) -> Void) {
        queue.async { [self] in
            stopSession()
            poll?.cancel(); poll = nil
            self.request = request; self.frame = frame; self.status = status
            processIDs = []; didAttempt = false
            guard request != nil else { return }
            guard #available(macOS 14.2, *) else { status(request?.id, .unsupported); return }
            refresh()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.refresh() }
            poll = timer
            timer.resume()
        }
    }

    func retry() { queue.async { [self] in didAttempt = false; refresh() } }

    func stop() {
        // Termination drains teardown before the process exits; no audio callback waits on main.
        queue.sync {
            poll?.cancel(); poll = nil
            stopSession()
            request = nil
        }
    }

    private func stopSession() {
        if #available(macOS 14.2, *), let capture = session as? MusicProcessTap { capture.stop() }
        session = nil
    }

    private func refresh() {
        guard #available(macOS 14.2, *), let request else { return }
        let ids = MusicProcessTap.processes(for: request.bundleIdentifier)
        let device = MusicProcessTap.defaultOutputDevice()
        if ids != processIDs || device != outputDevice || !didAttempt {
            stopSession()
            processIDs = ids
            outputDevice = device
            didAttempt = true
            frame?(request, MusicSpectrumState.quiet)
            guard !ids.isEmpty else { status?(request.id, .waiting); return }
            do {
                let capture = try MusicProcessTap(processes: ids) { [weak self] levels in
                    // One small, rate-limited snapshot; a stale lease is checked again by the coordinator.
                    self?.queue.async { [weak self] in
                        guard let self, self.request == request else { return }
                        self.lastFrame = ProcessInfo.processInfo.systemUptime
                        self.frame?(request, levels)
                    }
                }
                session = capture
                lastFrame = ProcessInfo.processInfo.systemUptime
                status?(request.id, .capturing)
            } catch let error as MusicTapError {
                status?(request.id, .failed(error.code))
            } catch { status?(request.id, .failed(-1)) }
        } else if session != nil, ProcessInfo.processInfo.systemUptime - lastFrame > 1 {
            // Silence or a disconnected stream must not freeze an old loud frame.
            frame?(request, MusicSpectrumState.quiet)
        }
    }
}

private struct MusicTapError: Error { let code: OSStatus }

@available(macOS 14.2, *)
private final class MusicProcessTap {
    private var tap: AudioObjectID = kAudioObjectUnknown
    private var aggregate: AudioObjectID = kAudioObjectUnknown
    private var io: AudioDeviceIOProcID?
    private let audioQueue = DispatchQueue(label: "AirIsland.music-spectrum.samples", qos: .userInitiated)

    init(processes: [AudioObjectID], frame: @escaping ([Double]) -> Void) throws {
        do {
            let description = CATapDescription(monoMixdownOfProcesses: processes)
            description.name = "AirIsland Music Spectrum"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap))
            var format = AudioStreamBasicDescription()
            var address = Self.address(kAudioTapPropertyFormat)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, format.mSampleRate > 0 else { throw MusicTapError(code: kAudioHardwareUnsupportedOperationError) }

            // A private, input-only aggregate. Never set the default output or mute the player.
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "AirIsland Music Spectrum",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate))
            let analyzer = MusicSpectrumAnalyzer()
            let sampleRate = format.mSampleRate
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, audioQueue) { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                // Mono mixdown has one Float32 buffer. Never read a disabled/null stream.
                guard let buffer = buffers.first, let data = buffer.mData else { return }
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                 count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                analyzer.consume(samples, channels: Int(buffer.mNumberChannels), sampleRate: sampleRate,
                                 now: ProcessInfo.processInfo.systemUptime, emit: frame)
            })
            try check(AudioDeviceStart(aggregate, io))
        } catch { stop(); throw error }
    }

    deinit { stop() }
    func stop() {
        if let io {
            AudioDeviceStop(aggregate, io)
            AudioDeviceDestroyIOProcID(aggregate, io)
            self.io = nil
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = kAudioObjectUnknown }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap); tap = kAudioObjectUnknown }
    }

    private func check(_ code: OSStatus) throws { if code != noErr { throw MusicTapError(code: code) } }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var device: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device)
        return device
    }

    static func processes(for bundle: String) -> [AudioObjectID] {
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return [] }
        let roots = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).compactMap { $0.bundleURL?.standardizedFileURL.path }
        return ids.filter { id in
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { return false }
            var value: CFString? = nil
            var bundleAddress = address(kAudioProcessPropertyBundleID)
            var bundleSize = UInt32(MemoryLayout<CFString?>.size)
            let success = withUnsafeMutablePointer(to: &value) {
                AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, $0)
            }
            if success == noErr, value as String? == bundle { return true }
            // Helpers are accepted only when their executable belongs to the exact app bundle.
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
            let executable = String(cString: path)
            return roots.contains { executable.hasPrefix($0 + "/") }
        }.sorted()
    }
}
