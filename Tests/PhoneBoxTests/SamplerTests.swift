import Foundation
import Testing
@testable import PhoneBox

/// The snapshot timer's phase (design §6): the page files each snapshot under its whole second.
@MainActor
struct SamplerTests {
    @Test func theFirstTickComesHalfWayThroughASecond() {
        #expect(Sampler.firstTick(after: Date(timeIntervalSince1970: 100.0)) == Date(timeIntervalSince1970: 101.5))
        #expect(Sampler.firstTick(after: Date(timeIntervalSince1970: 100.2)) == Date(timeIntervalSince1970: 101.5))
        #expect(Sampler.firstTick(after: Date(timeIntervalSince1970: 100.98)) == Date(timeIntervalSince1970: 101.5))
    }
}
