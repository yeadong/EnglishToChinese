//
//  ObservingSCNView.swift
//  MindSurf
//
//  Created by 陈亚东 on 2025/5/1.
//

import SceneKit
class ObservingSCNView: SCNView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
