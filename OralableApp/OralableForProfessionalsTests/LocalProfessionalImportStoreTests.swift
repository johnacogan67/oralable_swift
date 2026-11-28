//
//  LocalProfessionalImportStoreTests.swift
//  OralableForProfessionalsTests
//

import XCTest
@testable import OralableForProfessionals

@MainActor
final class LocalProfessionalImportStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: LocalProfessionalImportStore!

    override func setUpWithError() throws {
        suiteName = "LocalProfessionalImportStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = LocalProfessionalImportStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
    }

    func testImportsStayInsideTheSignedInAccount() throws {
        let patient = makePatient(name: "Ada")
        let list = try JSONEncoder().encode([patient])
        let trace = Data("trace-a".utf8)
        store.saveParticipantsData(list, professionalID: "pro.a")
        store.saveSensorData(trace, professionalID: "pro.a", participantID: patient.patientID)

        XCTAssertNil(store.loadParticipantsData(professionalID: "pro.b"))
        XCTAssertNil(store.loadSensorData(professionalID: "pro.b", participantID: patient.patientID))
        XCTAssertEqual(store.loadParticipantsData(professionalID: "pro.a"), list)
        XCTAssertEqual(store.loadSensorData(professionalID: "pro.a", participantID: patient.patientID), trace)
    }

    func testLegacyListIsClaimedByTheFirstAccountOnly() throws {
        let patient = makePatient(name: "Grace")
        let list = try JSONEncoder().encode([patient])
        defaults.set(list, forKey: LocalProfessionalImportStore.legacyParticipantsKey)
        defaults.set(Data("old".utf8), forKey: LocalProfessionalImportStore.legacySensorKey(participantID: patient.patientID))

        store.adoptLegacyParticipants(professionalID: "pro.a", participantIDs: [patient.patientID])
        store.adoptLegacyParticipants(professionalID: "pro.b", participantIDs: [patient.patientID])

        XCTAssertEqual(store.loadParticipantsData(professionalID: "pro.a"), list)
        XCTAssertNil(store.loadParticipantsData(professionalID: "pro.b"))
        XCTAssertNil(defaults.data(forKey: LocalProfessionalImportStore.legacyParticipantsKey))
        XCTAssertNil(defaults.data(forKey: LocalProfessionalImportStore.legacySensorKey(participantID: patient.patientID)))
        XCTAssertEqual(
            store.loadSensorData(professionalID: "pro.a", participantID: patient.patientID),
            Data("old".utf8)
        )
        XCTAssertNil(store.loadSensorData(professionalID: "pro.b", participantID: patient.patientID))
    }

    func testDeletingOneAccountLeavesTheOther() throws {
        let ada = makePatient(name: "Ada")
        let bea = makePatient(name: "Bea")
        store.saveParticipantsData(try JSONEncoder().encode([ada]), professionalID: "pro.a")
        store.saveSensorData(Data("a".utf8), professionalID: "pro.a", participantID: ada.patientID)
        store.saveParticipantsData(try JSONEncoder().encode([bea]), professionalID: "pro.b")
        store.saveSensorData(Data("b".utf8), professionalID: "pro.b", participantID: bea.patientID)

        store.removeAll(professionalID: "pro.a", participantIDs: [ada.patientID])

        XCTAssertFalse(store.hasScopedParticipants("pro.a"))
        XCTAssertNil(store.loadSensorData(professionalID: "pro.a", participantID: ada.patientID))
        XCTAssertNotNil(store.loadParticipantsData(professionalID: "pro.b"))
        XCTAssertEqual(store.loadSensorData(professionalID: "pro.b", participantID: bea.patientID), Data("b".utf8))
    }

    private func makePatient(name: String) -> ProfessionalPatient {
        let id = UUID().uuidString
        return ProfessionalPatient(
            id: "local_\(id)",
            patientID: id,
            patientName: name,
            shareCode: "CSV",
            accessGrantedDate: Date(timeIntervalSince1970: 1_700_000_000),
            lastDataUpdate: nil,
            recordID: "local_\(id)",
            isLocalImport: true,
            dataPointCount: 1
        )
    }
}
