import SwiftUI
import Vision
import PDFKit

protocol TextExtractionServiceProtocol {
    func extractText(from image: UIImage) async throws -> String
    func extractText(from pdfURL: URL) async throws -> String
}

struct TextExtractionService: TextExtractionServiceProtocol {
    
    // MARK: - Vision (图片 OCR)
    func extractText(from image: UIImage) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else {
                throw NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取 CGImage"])
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                let request = VNRecognizeTextRequest { (request, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: "")
                        return
                    }
                    
                    let recognizedText = observations.compactMap {
                        $0.topCandidates(1).first?.string
                    }.joined(separator: "\n")
                    
                    continuation.resume(returning: recognizedText)
                }
                
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try requestHandler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }
    
    // MARK: - PDFKit (PDF 文本提取)
    func extractText(from pdfURL: URL) async throws -> String{
        return try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: pdfURL) else {
                throw NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载 PDF"])
            }
            
            var fullText = ""
            for i in 0..<document.pageCount {
                if let page = document.page(at: i), let pageContent = page.string {
                    fullText += pageContent + "\n"
                }
            }
            
            if fullText.isEmpty {
                throw NSError(domain: "PDFError", code: -2, userInfo: [NSLocalizedDescriptionKey: "未在 PDF 中发现可提取的文本"])
            }
            
            return fullText
        }.value
    }
}
