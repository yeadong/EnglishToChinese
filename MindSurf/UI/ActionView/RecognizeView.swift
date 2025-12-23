//
//  RecognizeView.swift
//  MindSurf
//
//  Created by 陈亚东 on 2025/10/29.
//
import SwiftUI
import NaturalLanguage
// ----------------------------------------------------
// 1. 核心数据结构 (来自前文的实现)
// ----------------------------------------------------

struct ProcessedToken {
    let word: String
    let range: Range<String.Index>
    var partOfSpeech: String?
    var lemma: String?
    var namedEntityType: String?
}


struct ProcessedArticle {
    let originalText: String
    var tokens: [ProcessedToken]

    static func processArticle(text: String, language: NLLanguage = .english) -> ProcessedArticle {
        // ... (省略前文的 ProcessedArticle.processArticle 实现细节，假设它已存在)
        // 实际代码中应包含前文给出的 ProcessedArticle.processArticle 实现
        // --- 阶段一: 标记化 (Tokenization) ---
                
        
        let tagSchemes: [NLTagScheme] = [
                    .lexicalClass,   // 词性标注
                    .lemma,          // 原型/词干
                    .nameType        // 命名实体
                ]
        let tagger = NLTagger(tagSchemes: tagSchemes)
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var tokenMap: [Range<String.Index>: ProcessedToken] = [:]

        for scheme in tagSchemes {
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: scheme, options: options) { tag, tokenRange in
                guard let tag = tag else { return true }
                
                let word = String(text[tokenRange])

                if tokenMap[tokenRange] == nil {
                    tokenMap[tokenRange] = ProcessedToken(word: word, range: tokenRange)
                }
                
                switch scheme {
                case .lexicalClass:
                    tokenMap[tokenRange]?.partOfSpeech = tag.rawValue
                case .lemma:
                    tokenMap[tokenRange]?.lemma = tag.rawValue
                case .nameType:
                    if tag == .personalName || tag == .placeName || tag == .organizationName {
                        tokenMap[tokenRange]?.namedEntityType = tag.rawValue
                    }
                default:
                    break
                }
                return true
            }
        }
        
        let sortedTokens = tokenMap.values.sorted { $0.range.lowerBound < $1.range.lowerBound }
        
        return ProcessedArticle(originalText: text, tokens: sortedTokens)
    }
}
// ----------------------------------------------------
// 2. UIViewRepresentable 视图实现
// ----------------------------------------------------

struct RecognizeView: UIViewRepresentable {
    
    // 待分析的测试文章
    let testArticle = "Tim Cook, the CEO of Apple, is speaking at the conference in London today. His team is running late."
    
    // 视图创建方法：相当于 UIKit 中的 viewDidLoad
    func makeUIView(context: Context) -> UITextView {
        
        // 1. 调用 NLTagger 测试代码
        let processedArticle = ProcessedArticle.processArticle(text: testArticle)
        
        // 2. 格式化结果以显示
        var resultText = "--- 原始文章 ---\n\(processedArticle.originalText)\n\n--- NLP 分析结果 ---\n"
        
        for token in processedArticle.tokens {
            let entity = token.namedEntityType != nil ? " (\(token.namedEntityType!))" : ""
            resultText += "• \(token.word)\n"
            resultText += "  - POS: \(token.partOfSpeech ?? "N/A")\n"
            resultText += "  - Lemma: \(token.lemma ?? "N/A")\(entity)\n"
        }
        
        // 3. 创建并配置 UITextView (使用 UITextView 而不是 UILabel 以更好地显示多行文本)
        let textView = UITextView()
        textView.isEditable = false
        textView.text = resultText
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .black
        textView.dataDetectorTypes = .all // 启用数据检测，如检测 London
        
        return textView
    }

    // 视图更新方法：本例中不需要更新逻辑
    func updateUIView(_ uiView: UITextView, context: Context) {
        // 通常留空，除非需要响应 SwiftUI 状态变化来更新 UIKit 视图
    }
}
