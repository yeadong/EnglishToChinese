import SwiftUI

protocol TranslationInteractor {
    func extractFromImage(_ image: UIImage)
    func extractFromPDF(_ url: URL)
    func translateText(source: String)
}

struct RealTranslationInteractor: TranslationInteractor {
    let appState: Store<AppState>
    let extractionService: TextExtractionServiceProtocol
    
    // 模拟翻译服务 (实际项目中可替换为 WebRepository 调用)
    private func performMockTranslation(_ text: String) async throws -> String {
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000) // 模拟网络延迟
        return "【中文翻译】\n" + text
    }

    func extractFromImage(_ image: UIImage) {
        setupProcessingState()
        
        Task {
            do {
                let text = try await extractionService.extractText(from: image)
                await updateSourceText(text)
                await doTranslate(text)
            } catch {
                await handleError(error)
            }
        }
    }
    
    func extractFromPDF(_ url: URL) {
        setupProcessingState()
        
        Task {
            do {
                let text = try await extractionService.extractText(from: url)
                await updateSourceText(text)
                await doTranslate(text)
            } catch {
                await handleError(error)
            }
        }
    }
    
    func translateText(source: String) {
        guard !source.isEmpty else { return }
        setupProcessingState()
        Task {
            await doTranslate(source)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupProcessingState() {
        appState.bulkUpdate { state in
            state.translation.isProcessing = true
            state.translation.error = nil
        }
    }
    
    @MainActor
    private func updateSourceText(_ text: String) {
        appState.value.translation.sourceText = text
    }
    
    @MainActor
    private func doTranslate(_ text: String) async {
        do {
            let result = try await performMockTranslation(text)
            appState.bulkUpdate { state in
                state.translation.translatedText = result
                state.translation.isProcessing = false
            }
        } catch {
            handleError(error)
        }
    }
    
    @MainActor
    private func handleError(_ error: Error) {
        appState.bulkUpdate { state in
            state.translation.error = error.localizedDescription
            state.translation.isProcessing = false
        }
    }
}

// 对应的 Stub 用于预览或测试
struct StubTranslationInteractor: TranslationInteractor {
    func extractFromImage(_ image: UIImage) {}
    func extractFromPDF(_ url: URL) {}
    func translateText(source: String) {}
}
