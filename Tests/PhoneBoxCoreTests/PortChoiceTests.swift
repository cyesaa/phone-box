import Testing
@testable import PhoneBoxCore

struct PortChoiceTests {
    @Test func readsAPortInTheAllowedRange() {
        #expect(PortChoice.parse("4747") == 4747)
        #expect(PortChoice.parse(" 8080\n") == 8080)
        #expect(PortChoice.parse("1024") == 1024)
        #expect(PortChoice.parse("65535") == 65535)
    }

    @Test func refusesEverythingElse() {
        for text in ["", " ", "80", "1023", "65536", "99999", "123456", "-4747", "+4747", "47 47", "4747a", "0x12AB",
                     "4747.0", "٤٧٤٧", "00004747"] {
            #expect(PortChoice.parse(text) == nil, "\(text)")
        }
    }
}
