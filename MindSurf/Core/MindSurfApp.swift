//
//  MindSurfApp.swift
//  MindSurf
//
//  Created by 陈亚东 on 2025/2/26.
//

import SwiftUI
import EnvironmentOverrides

@main
struct MindSurfApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            appDelegate.rootView
        }
    }
}

extension AppEnvironment {
    var rootView: some View {
//        VStack {
//            if isRunningTests {
//                Text("Running unit tests")
//            } else {
//                CountriesList()
//                    .modifier(RootViewAppearance())
//                    .modelContainer(modelContainer)
//                    .attachEnvironmentOverrides(onChange: onChangeHandler)
//                    .inject(diContainer)
//                if modelContainer.isStub {
//                    Text("⚠️ There is an issue with local database")
//                        .font(.caption2)
//                }
//            }
//        }
        ZStack {
//            ParallaxTerrainSceneView()
//                        .edgesIgnoringSafeArea(.all)
//                    VStack {
//                        Text("专注旅程中...")
//                            .font(.title)
//                            .foregroundColor(.white)
//                            .padding()
//                        Spacer()
//                    }
            // 将 RecognizeView 设置为启动视图
//            RecognizeView()
//                .padding()      // 添加 padding 以免文本贴边
            TranslationView().inject(diContainer)
            
         }
    }

    private var onChangeHandler: (EnvironmentValues.Diff) -> Void {
        return { diff in
            if !diff.isDisjoint(with: [.locale, .sizeCategory]) {
                self.diContainer.appState[\.routing] = AppState.ViewRouting()
            }
        }
    }
}
