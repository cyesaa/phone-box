import Foundation
import Testing
@testable import PhoneBoxCore

struct NowPlayingStreamTests {
    /// Recorded from the adapter on macOS 27.2 (`stream --no-diff --no-artwork`), a paused YouTube video in Chrome.
    let chromeLine = #"{"type":"data","diff":false,"payload":{"artist":"Cem Yılmaz","playbackRate":0,"contentItemIdentifier":"254D6129-F85E-4520-9722-B17D9980417B","title":"Masaj | Cem Yılmaz : Diamond Elite Platinum Plus","elapsedTime":2.0565129999999998,"duration":86.741,"playing":false,"bundleIdentifier":"com.google.Chrome","album":"","processIdentifier":24929,"timestamp":"2026-11-25T19:03:59Z"}}"#

    @Test func parsesARealLine() {
        #expect(NowPlayingStream.parse(chromeLine) == .track(NowPlayingTrack(
            title: "Masaj | Cem Yılmaz : Diamond Elite Platinum Plus", artist: "Cem Yılmaz", bundleId: "com.google.Chrome",
            playing: false)))
    }

    @Test func anEmptyPayloadMeansNothingIsPlaying() {
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{}}"#) == .nothing)
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{"title":"","bundleIdentifier":"a"}}"#) == .nothing)
        #expect(NowPlayingStream.parse(#"{"type":"data","diff":false,"payload":{"title":"x"}}"#) == .nothing)
    }

    @Test func prefersTheParentAppAndAcceptsANumericPlayingFlag() {
        let line = #"{"type":"data","payload":{"title":"Song","bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","playing":1}}"#
        #expect(NowPlayingStream.parse(line) == .track(NowPlayingTrack(title: "Song", artist: nil, bundleId: "com.apple.Safari", playing: true)))
    }

    @Test func cleansAndCapsTheText() {
        let long = String(repeating: "ş", count: 200)
        let line = #"{"type":"data","payload":{"title":"‎\#(long)","artist":"  ","bundleIdentifier":"com.spotify.client","playing":true}}"#
        guard case let .track(track) = NowPlayingStream.parse(line) else { Issue.record("no track"); return }
        #expect(track.title == String(repeating: "ş", count: AppUsage.maxNameLength))
        #expect(track.artist == nil)
    }

    @Test func rejectsOtherLines() {
        #expect(NowPlayingStream.parse("") == .invalid)
        #expect(NowPlayingStream.parse("not json") == .invalid)
        #expect(NowPlayingStream.parse(#"{"type":"error","payload":{}}"#) == .invalid)
    }
}

struct LineAssemblerTests {
    @Test func joinsChunksThatEndAnywhere() {
        var assembler = LineAssembler()
        let bytes = Array("{\"a\":\"ğ\"}\n{\"b\":1}\n".utf8)
        let split = 6  // inside the two-byte "ğ"
        #expect(assembler.append(Data(bytes[..<split])) == [])
        #expect(assembler.append(Data(bytes[split...])) == [#"{"a":"ğ"}"#, #"{"b":1}"#])
    }

    @Test func dropsAnOverlongLine() {
        var assembler = LineAssembler()
        #expect(assembler.append(Data(repeating: 0x61, count: LineAssembler.maxLineBytes + 1)) == [])
        #expect(assembler.append(Data("ok\n".utf8)) == ["ok"])
    }
}

struct NowPlayingStateTests {
    let start = Date(timeIntervalSince1970: 1_000)
    let song = NowPlayingTrack(title: "A", artist: nil, bundleId: "com.spotify.client", playing: true)
    let next = NowPlayingTrack(title: "B", artist: nil, bundleId: "com.spotify.client", playing: true)

    @Test func keepsTheTrackThroughTheGapBetweenTwoTracks() {
        var state = NowPlayingState()
        state.received(.track(song), at: start)
        state.received(.nothing, at: start.addingTimeInterval(1))
        #expect(state.current(at: start.addingTimeInterval(2)) == song)
        state.received(.track(next), at: start.addingTimeInterval(2.2))
        #expect(state.current(at: start.addingTimeInterval(5)) == next)
    }

    @Test func nothingPlayingAppliesAfterTheGrace() {
        var state = NowPlayingState()
        state.received(.track(song), at: start)
        state.received(.nothing, at: start.addingTimeInterval(1))
        state.received(.nothing, at: start.addingTimeInterval(2))  // a repeat does not push the deadline back
        #expect(state.current(at: start.addingTimeInterval(2.5)) == nil)
    }

    @Test func ignoresInvalidLinesAndClears() {
        var state = NowPlayingState()
        #expect(state.current(at: start) == nil)
        state.received(.nothing, at: start)
        state.received(.track(song), at: start)
        state.received(.invalid, at: start.addingTimeInterval(10))
        #expect(state.current(at: start.addingTimeInterval(10)) == song)
        state.clear()
        #expect(state.current(at: start.addingTimeInterval(10)) == nil)
    }
}
