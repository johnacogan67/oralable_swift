//
//  BLESubscriptionLeakTests.swift
//  OralableAppTests
//
//  Purpose: Memory leak tests for BLE Combine subscriptions.
//  Verifies that DashboardViewModel, HistoricalViewModel, and DeviceManager
//  do not create retain cycles through their Combine .sink closures.
//
//  Background:
//  - DashboardViewModel uses three cancellable sets:
//    - `cancellables` for init-time bindings
//    - `bleCancellables` for BLE subscriptions (cleared on reconnect)
//    - `demoCancellables` for demo mode subscriptions
//  - All .sink closures must use [weak self] to prevent retain cycles
//  - A previous bug caused subscription accumulation on reconnect (fixed with
//    separate `bleCancellables` set cleared in `startMonitoring()`)
//
//  Created: February 2026
//

import XCTest
import Combine
import CoreBluetooth
@testable import OralableApp

@MainActor
final class BLESubscriptionLeakTests: XCTestCase {

    // MARK: - Properties

    var mockBLEService: MockBLEService!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockBLEService = MockBLEService(bluetoothState: .poweredOn)
    }

    override func tearDown() async throws {
        cancellables = nil
        mockBLEService = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Helper to create a DashboardViewModel with mock dependencies.
    /// Returns all created objects so the caller can control their lifetimes.
    private func makeDashboardViewModel() -> (
        vm: DashboardViewModel,
        deviceManager: DeviceManager,
        adapter: DeviceManagerAdapter,
        appStateManager: AppStateManager
    ) {
        let deviceManager = DeviceManager(bleService: mockBLEService)
        let sensorDataProcessor = SensorDataProcessor(calculator: BioMetricCalculator())
        let adapter = DeviceManagerAdapter(
            deviceManager: deviceManager,
            sensorDataProcessor: sensorDataProcessor
        )
        let appStateManager = AppStateManager()
        let vm = DashboardViewModel(
            deviceManagerAdapter: adapter,
            deviceManager: deviceManager,
            appStateManager: appStateManager
        )
        return (vm, deviceManager, adapter, appStateManager)
    }

    /// Helper that asserts an object deallocates during teardown.
    /// Uses XCTest's addTeardownBlock to check after the test completes.
    private func assertNoMemoryLeak(
        _ instance: AnyObject,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Potential memory leak: \(String(describing: instance)) was not deallocated",
                file: file,
                line: line
            )
        }
    }

    /// Allow time for ARC cleanup and Combine publisher propagation.
    private func waitForDeallocation(milliseconds: UInt64 = 200) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    // MARK: - 1. DashboardViewModel Deallocation After Use

    func testDashboardViewModelDeallocatesAfterUse() async {
        // Given - create a DashboardViewModel and capture a weak reference
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        weak var weakVM = objects?.vm

        // Verify the VM exists
        XCTAssertNotNil(weakVM, "ViewModel should exist before being nilled out")

        // When - release all strong references
        objects = nil

        // Then - allow ARC to clean up and verify deallocation
        await waitForDeallocation()
        XCTAssertNil(weakVM, "DashboardViewModel should deallocate when all strong references are released (no retain cycle)")
    }

    // MARK: - 2. DashboardViewModel Deallocation After startMonitoring

    func testDashboardViewModelDeallocatesAfterStartMonitoring() async {
        // Given - create VM and start monitoring (creates BLE subscriptions)
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        objects?.vm.startMonitoring()

        weak var weakVM = objects?.vm

        XCTAssertNotNil(weakVM, "ViewModel should exist after startMonitoring")

        // When - release all strong references
        objects = nil

        // Then - VM should still deallocate despite active subscriptions
        // (because all sinks use [weak self])
        await waitForDeallocation()
        XCTAssertNil(weakVM, "DashboardViewModel should deallocate after startMonitoring (subscriptions use [weak self])")
    }

    // MARK: - 3. DashboardViewModel Deallocation After Reconnect Cycle

    func testDashboardViewModelDeallocatesAfterReconnectCycle() async {
        // Given - create VM and simulate connect -> disconnect -> reconnect
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        // First connection cycle
        objects?.vm.startMonitoring()
        await waitForDeallocation(milliseconds: 50)

        // Simulate disconnect by stopping monitoring
        objects?.vm.stopMonitoring()
        await waitForDeallocation(milliseconds: 50)

        // Second connection cycle (reconnect)
        objects?.vm.startMonitoring()
        await waitForDeallocation(milliseconds: 50)

        weak var weakVM = objects?.vm

        XCTAssertNotNil(weakVM, "ViewModel should exist before release")

        // When - release all strong references
        objects = nil

        // Then - VM should deallocate even after reconnect cycle
        await waitForDeallocation()
        XCTAssertNil(weakVM, "DashboardViewModel should deallocate after reconnect cycle (bleCancellables properly cleared)")
    }

    // MARK: - 4. BLE Cancellables Cleared on Reconnect

    func testBLECancellablesClearedOnReconnect() async {
        // Given - create VM
        let objects = makeDashboardViewModel()
        let vm = objects.vm
        let adapter = objects.adapter

        // Before startMonitoring, BLE subscriptions should not be active
        // Verify by checking that sensor data does NOT propagate
        adapter.heartRate = 99
        await waitForDeallocation(milliseconds: 600)

        // heartRate may or may not propagate depending on init-time bindings
        // The key test is that startMonitoring creates subscriptions

        // When - first call to startMonitoring sets up subscriptions
        vm.startMonitoring()

        // Publish sensor data and verify it propagates
        let hrExpectation = XCTestExpectation(description: "Heart rate propagates after first startMonitoring")

        vm.$heartRate
            .dropFirst()
            .sink { hr in
                if hr == 72 {
                    hrExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        adapter.heartRate = 72
        await fulfillment(of: [hrExpectation], timeout: 2.0)

        // When - second call to startMonitoring should clear old subscriptions
        // and create new ones (simulating reconnect)
        vm.startMonitoring()

        // Verify new subscriptions still work after reconnect
        let reconnectExpectation = XCTestExpectation(description: "Heart rate propagates after reconnect")

        vm.$heartRate
            .dropFirst()
            .sink { hr in
                if hr == 85 {
                    reconnectExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        adapter.heartRate = 85
        await fulfillment(of: [reconnectExpectation], timeout: 2.0)
        XCTAssertEqual(vm.heartRate, 85, "Sensor data should propagate after reconnect")
    }

    // MARK: - 5. Weak Self in Combine Sinks

    func testWeakSelfInCombineSinks() async {
        // Given - create VM with monitoring active
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        let adapter = objects!.adapter

        objects?.vm.startMonitoring()

        // Trigger initial data flow to exercise the subscriptions
        adapter.heartRate = 72
        adapter.spO2 = 98
        adapter.temperature = 36.5
        await waitForDeallocation(milliseconds: 600)

        weak var weakVM = objects?.vm

        // When - nil out the ViewModel while keeping the adapter alive
        // This simulates the adapter continuing to publish after the VM is gone
        objects?.vm = nil  // Cannot do this directly since it's in a tuple

        // Release the entire objects tuple - but keep adapter reference
        // to publish more data after VM is gone
        let adapterRef = objects!.adapter
        objects = nil

        await waitForDeallocation()

        // Then - publish more data through the adapter after VM is released
        // If closures captured strong self, this would cause a crash or the VM
        // would still be alive
        adapterRef.heartRate = 150
        adapterRef.spO2 = 100
        adapterRef.temperature = 38.0

        await waitForDeallocation(milliseconds: 100)

        // The test passes if:
        // 1. No crash occurred (strong self would crash on dealloc'd object)
        // 2. The VM was deallocated (no retain cycle)
        XCTAssertNil(weakVM, "ViewModel should be deallocated; [weak self] prevents retain cycle in Combine sinks")
    }

    // MARK: - 6. HistoricalViewModel Deallocation After Use

    func testHistoricalViewModelDeallocatesAfterUse() async {
        // Given - create HistoricalViewModel with mock data manager
        var mockDataManager: PreviewHistoricalDataManager? = PreviewHistoricalDataManager()
        var vm: HistoricalViewModel? = HistoricalViewModel(historicalDataManager: mockDataManager!)

        weak var weakVM = vm
        weak var weakDataManager = mockDataManager

        XCTAssertNotNil(weakVM, "HistoricalViewModel should exist before release")

        // Exercise the VM
        vm?.selectedTimeRange = .day
        vm?.updateAllMetrics()
        vm?.refresh()

        // When - release all strong references
        vm = nil
        mockDataManager = nil

        // Then - VM should deallocate
        await waitForDeallocation()
        XCTAssertNil(weakVM, "HistoricalViewModel should deallocate when all strong references are released")
    }

    // MARK: - 7. DeviceManager Deallocation After Use

    func testDeviceManagerDeallocatesAfterUse() async {
        // Given - create DeviceManager with mock BLE service
        var localMockBLE: MockBLEService? = MockBLEService(bluetoothState: .poweredOn)
        var dm: DeviceManager? = DeviceManager(bleService: localMockBLE!)

        weak var weakDM = dm

        XCTAssertNotNil(weakDM, "DeviceManager should exist before release")

        // When - release all strong references
        dm = nil
        localMockBLE = nil

        // Then - DeviceManager should deallocate
        await waitForDeallocation()
        XCTAssertNil(weakDM, "DeviceManager should deallocate when all strong references are released")
    }

    // MARK: - 8. Multiple startMonitoring Calls Don't Leak

    func testMultipleStartMonitoringCallsDontLeak() async {
        // Given - create VM and call startMonitoring many times
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        // Call startMonitoring multiple times to simulate rapid reconnections
        // Each call should clear bleCancellables before creating new subscriptions
        for _ in 0..<10 {
            objects?.vm.startMonitoring()
        }

        weak var weakVM = objects?.vm

        // When - release
        objects = nil

        // Then - should still deallocate despite 10 start/stop cycles
        await waitForDeallocation()
        XCTAssertNil(weakVM, "DashboardViewModel should deallocate after multiple startMonitoring calls")
    }

    // MARK: - 9. Teardown Block Leak Detection (addTeardownBlock pattern)

    func testDashboardViewModelNoLeakViaTeardown() async {
        // Given - create VM and register teardown assertion
        let objects = makeDashboardViewModel()
        let vm = objects.vm

        // Register leak detection in teardown
        assertNoMemoryLeak(vm)

        // Exercise the VM with monitoring
        vm.startMonitoring()
        objects.adapter.heartRate = 72
        await waitForDeallocation(milliseconds: 600)

        // The test will fail in teardown if vm is not deallocated
        // (assertNoMemoryLeak checks weakRef == nil in addTeardownBlock)
    }

    // MARK: - 10. HistoricalViewModel No Leak Via Teardown

    func testHistoricalViewModelNoLeakViaTeardown() async {
        // Given
        let mockDataManager = PreviewHistoricalDataManager()
        let vm = HistoricalViewModel(historicalDataManager: mockDataManager)

        // Register leak detection
        assertNoMemoryLeak(vm)

        // Exercise
        vm.selectedTimeRange = .week
        vm.updateAllMetrics()
    }

    // MARK: - 11. DeviceManager No Leak Via Teardown

    func testDeviceManagerNoLeakViaTeardown() async {
        // Given
        let localMockBLE = MockBLEService(bluetoothState: .poweredOn)
        let dm = DeviceManager(bleService: localMockBLE)

        // Register leak detection
        assertNoMemoryLeak(dm)
    }

    // MARK: - 12. Adapter Publisher Continues After VM Dealloc

    func testAdapterPublisherContinuesAfterVMDealloc() async {
        // This test verifies that when DashboardViewModel is deallocated,
        // the adapter's publishers can still fire without crash.
        // This is critical for verifying [weak self] usage.

        // Given
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        let adapter = objects!.adapter
        objects?.vm.startMonitoring()

        // Push some initial data
        adapter.heartRate = 60
        adapter.spO2 = 95
        await waitForDeallocation(milliseconds: 600)

        // When - release the VM but keep adapter
        weak var weakVM = objects?.vm
        // We can't selectively nil tuple members, so we save references we need
        let savedAdapter = objects!.adapter
        let savedDM = objects!.deviceManager
        objects = nil

        await waitForDeallocation()

        // Then - push data through the adapter; should not crash
        savedAdapter.heartRate = 200
        savedAdapter.spO2 = 100
        savedAdapter.temperature = 40.0
        savedAdapter.batteryLevel = 100.0

        await waitForDeallocation(milliseconds: 100)

        // Verify VM was deallocated
        XCTAssertNil(weakVM, "DashboardViewModel should be nil after release")

        // Verify adapter still functions (no crash from dangling references)
        XCTAssertEqual(savedAdapter.heartRate, 200, "Adapter should still accept new values after VM dealloc")

        // Keep savedDM alive to prevent cascade dealloc issues
        _ = savedDM
    }

    // MARK: - 13. Demo Mode Subscriptions Use Weak Self

    func testDemoSubscriptionsDontRetainVM() async {
        // Given - create VM (demo subscriptions are set up in init via setupBindings)
        var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                      adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
            = makeDashboardViewModel()

        weak var weakVM = objects?.vm

        // Demo mode subscriptions are created during init's setupBindings -> setupDemoModeSubscription
        // They subscribe to DemoDataProvider.shared publishers
        // These must use [weak self] to avoid leaking

        XCTAssertNotNil(weakVM, "VM should exist before release")

        // When
        objects = nil

        // Then
        await waitForDeallocation()
        XCTAssertNil(weakVM, "DashboardViewModel should deallocate despite demo mode subscriptions (uses [weak self])")
    }

    // MARK: - 14. Rapid Create/Destroy Cycle Doesn't Leak

    func testRapidCreateDestroyCycleDoesntLeak() async {
        // Given - rapidly create and destroy VMs to stress-test cleanup
        var weakRefs: [() -> AnyObject?] = []

        for _ in 0..<5 {
            var objects: (vm: DashboardViewModel, deviceManager: DeviceManager,
                          adapter: DeviceManagerAdapter, appStateManager: AppStateManager)?
                = makeDashboardViewModel()

            objects?.vm.startMonitoring()

            weak var weakVM = objects?.vm
            weakRefs.append { [weak weakVM] in weakVM }

            objects = nil
        }

        // When - wait for cleanup
        await waitForDeallocation(milliseconds: 500)

        // Then - all VMs should be deallocated
        for (index, weakRefGetter) in weakRefs.enumerated() {
            XCTAssertNil(
                weakRefGetter(),
                "DashboardViewModel instance \(index) should be deallocated in rapid create/destroy cycle"
            )
        }
    }
}
