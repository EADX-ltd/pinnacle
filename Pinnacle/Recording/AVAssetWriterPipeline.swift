import AVFoundation
import CoreMedia
import Foundation

/// Thread-safe wrapper around `AVAssetWriter` for screen recording.
///
/// Sample append calls are expected from the SCStreamOutput dispatch queue (off the main
/// actor). Internal state is guarded by `NSLock` so that concurrent append/finish/pause
/// calls from any queue are safe.
final class AVAssetWriterPipeline {
    enum PipelineError: LocalizedError {
        case writerInitFailed(String)
        case startWritingFailed(String)

        var errorDescription: String? {
            switch self {
            case .writerInitFailed(let detail):
                return "Failed to create video writer: \(detail)"
            case .startWritingFailed(let detail):
                return "Failed to start writer session: \(detail)"
            }
        }
    }

    /// Outcome of `finish()` so callers can distinguish a written file from a
    /// session that captured zero frames (which deletes the file).
    enum FinishOutcome {
        case finalized
        case canceledNoFrames
        case alreadyFinished
    }

    let outputURL: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?

    private let lock = NSLock()
    private var sessionStarted = false
    private var isPaused = false
    private var isFinished = false

    // Pause handling: drop any sample whose PTS is between `pauseStart` and
    // `pauseEnd`, and shift later samples back by the accumulated paused
    // duration so the output timeline is continuous instead of containing a
    // freeze the length of the user's pause.
    private var pauseStart: CMTime?
    private var totalPausedDuration: CMTime = .zero
    private var lastWrittenVideoPTS: CMTime?

    init(outputURL: URL, width: Int, height: Int, captureAudio: Bool) throws {
        self.outputURL = outputURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw PipelineError.writerInitFailed(error.localizedDescription)
        }
        self.writer = writer

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        self.videoInput = videoInput

        if captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
            }
            self.audioInput = audioInput
        } else {
            self.audioInput = nil
        }
    }

    func startWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        guard writer.startWriting() else {
            throw PipelineError.startWritingFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    func beginPause() {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        isPaused = true
        // pauseStart is set lazily on the next sample so we anchor to a real
        // capture timestamp rather than wall clock.
        pauseStart = nil
    }

    func endPause() {
        lock.lock()
        defer { lock.unlock() }
        guard isPaused else { return }
        isPaused = false
        // Do NOT clear pauseStart here. It marks the first paused sample's PTS
        // and is consumed by the next post-resume appendVideo/appendAudio,
        // which extends totalPausedDuration by (pts - pauseStart). If zero
        // samples arrived during the pause, pauseStart was never assigned and
        // the next call's `if let pauseStart` guard correctly skips accumulation.
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isPaused {
            if pauseStart == nil { pauseStart = pts }
            return
        }

        // First sample after un-pause: extend totalPausedDuration by the gap.
        if let pauseStart {
            totalPausedDuration = CMTimeAdd(totalPausedDuration, CMTimeSubtract(pts, pauseStart))
            self.pauseStart = nil
        }

        let adjustedPTS = CMTimeSubtract(pts, totalPausedDuration)

        if !sessionStarted {
            writer.startSession(atSourceTime: adjustedPTS)
            sessionStarted = true
        }

        // Guard against monotonic-PTS violations after rebasing.
        if let last = lastWrittenVideoPTS, CMTimeCompare(adjustedPTS, last) <= 0 {
            return
        }

        if videoInput.isReadyForMoreMediaData,
           let rebased = retimedSampleBuffer(sampleBuffer, newPTS: adjustedPTS) {
            videoInput.append(rebased)
            lastWrittenVideoPTS = adjustedPTS
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, sessionStarted, let input = audioInput else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if isPaused {
            if pauseStart == nil { pauseStart = pts }
            return
        }
        if let pauseStart {
            totalPausedDuration = CMTimeAdd(totalPausedDuration, CMTimeSubtract(pts, pauseStart))
            self.pauseStart = nil
        }

        let adjustedPTS = CMTimeSubtract(pts, totalPausedDuration)

        if input.isReadyForMoreMediaData,
           let rebased = retimedSampleBuffer(sampleBuffer, newPTS: adjustedPTS) {
            input.append(rebased)
        }
    }

    func finish() async -> FinishOutcome {
        lock.lock()
        if isFinished {
            lock.unlock()
            return .alreadyFinished
        }
        isFinished = true
        let writerRef = writer
        let videoRef = videoInput
        let audioRef = audioInput
        let didStart = sessionStarted
        lock.unlock()

        videoRef.markAsFinished()
        audioRef?.markAsFinished()
        if didStart {
            await writerRef.finishWriting()
            return .finalized
        } else {
            writerRef.cancelWriting()
            return .canceledNoFrames
        }
    }

    private func retimedSampleBuffer(_ source: CMSampleBuffer, newPTS: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(source, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
              count > 0 else { return source }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(source, entryCount: count, arrayToFill: &timings, entriesNeededOut: nil) == noErr else { return source }
        // Single-presentation buffers are the common SCStream case; offset all entries uniformly.
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(source)
        let delta = CMTimeSubtract(newPTS, originalPTS)
        for index in 0..<timings.count {
            timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, delta)
            if CMTIME_IS_VALID(timings[index].decodeTimeStamp) {
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, delta)
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: source,
            sampleTimingEntryCount: count,
            sampleTimingArray: timings,
            sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }
}
