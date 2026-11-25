// Writes the two keep-awake test videos the spike page plays:
//   keepawake-video.mp4  1 s, 64×64 black H.264, no audio
//   keepawake-av.mp4     2 s, 64×64 black H.264 + silent AAC track
// Run: swift spike/make-video.swift spike/web
import AVFoundation

func makeVideo(at url: URL, seconds: Int, withAudio: Bool) throws {
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

    var audioInput: AVAssetWriterInput?
    if withAudio {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
        writer.add(input)
        audioInput = input
    }

    guard writer.startWriting() else { throw writer.error! }
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

    if let audioInput {
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
    }

    group.wait()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try makeVideo(at: directory.appendingPathComponent("keepawake-video.mp4"), seconds: 1, withAudio: false)
try makeVideo(at: directory.appendingPathComponent("keepawake-av.mp4"), seconds: 2, withAudio: true)
print("Wrote keepawake-video.mp4 and keepawake-av.mp4 in \(directory.path)")
