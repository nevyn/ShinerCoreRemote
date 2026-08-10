import Testing
import CoreBluetooth
@testable import ShinerCoreKit

@Suite struct BLECoreLinkTests {
    let id = CoreProps.meshGroup.id

    /// Pre-fork firmware answers Invalid Offset when reading a zero-length
    /// value (stock ArduinoBLE's `offset >= valueLength` check); that *is*
    /// the value: empty.
    @Test func invalidOffsetReadMeansEmptyValue() {
        let error = CBATTError(.invalidOffset)
        #expect(BLECoreLink.readOutcome(id, error) == .valueRead(id, ""))
    }

    @Test func otherReadErrorsStillFail() {
        let error = CBATTError(.readNotPermitted)
        guard case .readFailed(let failedId, _) = BLECoreLink.readOutcome(id, error) else {
            Issue.record("expected readFailed")
            return
        }
        #expect(failedId == id)
    }
}
