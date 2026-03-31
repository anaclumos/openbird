import Testing
@testable import OpenbirdKit

struct CurrentActivityContextServiceTests {
    @Test func extractsNormalizedDomainFromURL() {
        #expect(normalizedDomain(from: "https://openbird.vercel.app/path?q=1") == "openbird.vercel.app")
        #expect(normalizedDomain(from: "mail.google.com") == "mail.google.com")
    }

    @Test func ignoresInvalidOrEmptyDomains() {
        #expect(normalizedDomain(from: nil) == nil)
        #expect(normalizedDomain(from: "   ") == nil)
        #expect(normalizedDomain(from: "not a url") == nil)
    }
}
