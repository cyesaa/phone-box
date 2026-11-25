// Writes keepawake.mp4: 2 s of 64×64 black H.264 with a silent AAC track (spike V4, design §8).
// WebKit keeps the screen on only while an unmuted video with both tracks plays.
// Run: swift scripts/make-video.swift <output.mp4>
// macOS 27 marks these AVAssetWriter calls deprecated; they still work and this runs once per build.
import AVFoundation

func makeVideo(at url: URL, seconds: Int) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let size = 64
    let fps: Int32 = 10

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size, AVVideoHeightKey: size,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size, kCVPixelBufferHeightKey as String: size,
    ])
    writer.add(videoInput)
    let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
    ])
    writer.add(audioInput)

    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    let group = DispatchGroup()

    group.enter()
    var frame = 0
    let frameCount = Int(fps) * seconds
    videoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
        while videoInput.isReadyForMoreMediaData {
            if frame == frameCount {
                videoInput.markAsFinished()
                group.leave()
                return
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), 0, CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            frame += 1
        }
    }

    var description = AudioStreamBasicDescription(
        mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let totalFrames = 44_100 * seconds
    var written = 0
    group.enter()
    audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio")) {
        while audioInput.isReadyForMoreMediaData {
            if written >= totalFrames {
                audioInput.markAsFinished()
                group.leave()
                return
            }
            let count = min(1024, totalFrames - written)
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: count * 2,
                                               flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2)
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: count,
                presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: 44_100),
                packetDescriptions: nil, sampleBufferOut: &sample)
            audioInput.append(sample!)
            written += count
        }
    }

    group.wait()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-video.swift <output.mp4>\n".utf8))
    exit(1)
}
try makeVideo(at: URL(fileURLWithPath: CommandLine.arguments[1]), seconds: 2)
