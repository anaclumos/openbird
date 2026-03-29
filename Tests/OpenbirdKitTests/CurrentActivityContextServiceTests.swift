import Testing
@testable import OpenbirdKit

struct CurrentActivityContextServiceTests {
    @Test func extractsNormalizedDomainFromURL() {
        #expect(CurrentActivityContextService.normalizedDomain(from: "https://openbird.vercel.app/path?q=1") == "openbird.vercel.app")
        #expect(CurrentActivityContextService.normalizedDomain(from: "mail.google.com") == "mail.google.com")
    }

    @Test func ignoresInvalidOrEmptyDomains() {
        #expect(CurrentActivityContextService.normalizedDomain(from: nil) == nil)
        #expect(CurrentActivityContextService.normalizedDomain(from: "   ") == nil)
        #expect(CurrentActivityContextService.normalizedDomain(from: "not a url") == nil)
    }
}
