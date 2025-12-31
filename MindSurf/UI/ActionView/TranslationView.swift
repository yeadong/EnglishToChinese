import SwiftUI
import UniformTypeIdentifiers

struct TranslationView: View {
    @State private var translationState = TranslationAppState() // 本地状态副本，或者直接使用 Binding
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var inputImage: UIImage?
    @Environment(\.injected) private var injected: DIContainer
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if translationState.isProcessing {
                    ProgressView("AI 识别与翻译中...")
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !translationState.sourceText.isEmpty {
                            VStack(alignment: .leading) {
                                Text("原文 (English):").font(.caption).foregroundColor(.secondary)
                                Text(translationState.sourceText)
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        
                        if !translationState.translatedText.isEmpty {
                            VStack(alignment: .leading) {
                                Text("译文 (中文):").font(.caption).foregroundColor(.blue)
                                Text(translationState.translatedText)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        
                        if let error = translationState.error {
                            Text("错误: \(error)").foregroundColor(.red)
                        }
                    }
                    .padding()
                }
                
                HStack(spacing: 20) {
                    Button(action: { showImagePicker = true }) {
                        Label("拍照/相册", systemImage: "camera")
                            .frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                    
                    Button(action: { showDocumentPicker = true }) {
                        Label("PDF文档", systemImage: "doc.text")
                            .frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("英汉翻译")
            // 关键修改：监听 appState.translation
            .onReceive(injected.appState.map(\.translation)) { state in
                self.translationState = state
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $inputImage) { img in
                    if let img = img {
                        injected.interactors.translation.extractFromImage(img)
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    injected.interactors.translation.extractFromPDF(url)
                }
            }
        }
    }
}
