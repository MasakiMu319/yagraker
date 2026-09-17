import XCTest
import Combine
import YagrakerCore
@testable import Yagraker

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func testCatalogNormalizationTrimsDeduplicatesAndSorts() {
        let model = SettingsViewModel()
        let models = [" z ", "", "a", "z", "  "].map {
            LLMModel(id: $0, displayName: $0, description: nil)
        }
        XCTAssertEqual(model.normalizeModels(models).map(\.id), ["a", "z"])
    }

    @MainActor
    func testDraftEditsPublishWithoutPersistingSettings() {
        let model = SettingsViewModel()
        let saved = SettingsStore.shared.model(for: .gemini, task: .translation)
        var updates = 0
        let subscription = model.objectWillChange.sink { updates += 1 }
        model.providerDrafts[.gemini]?.setModel("unsaved-test-model", for: .translation)
        XCTAssertGreaterThan(updates, 0)
        XCTAssertEqual(SettingsStore.shared.model(for: .gemini, task: .translation), saved)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testInvalidationPublishesIdleCatalog() {
        let model = SettingsViewModel()
        model.modelCatalogs[.gemini] = .loaded([])
        model.invalidateModelCatalog(for: .gemini)
        XCTAssertEqual(model.modelCatalogs[.gemini], .idle)
    }
}
