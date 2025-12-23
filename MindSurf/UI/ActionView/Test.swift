//import SwiftUI
//import SceneKit
//import GameplayKit // Needed for random numbers
//
//// MARK: - Helper Extensions & Functions
//
//extension UIColor {
//    // Simple linear interpolation between two UIColors
//    func interpolate(to color: UIColor, fraction: CGFloat) -> UIColor {
//        let f = min(max(0, fraction), 1)
//        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
//        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
//        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
//        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
//        let r = r1 + (r2 - r1) * f
//        let g = g1 + (g2 - g1) * f
//        let b = b1 + (b2 - b1) * f
//        let a = a1 + (a2 - a1) * f
//        return UIColor(red: r, green: g, blue: b, alpha: a)
//    }
//}
//
//// MARK: - Vector & Catmull-Rom Helpers
//// (Unchanged)
//struct Vector2D {
//    var x: CGFloat; var y: CGFloat
//    static func + (left: Vector2D, right: Vector2D) -> Vector2D { Vector2D(x: left.x + right.x, y: left.y + right.y) }
//    static func - (left: Vector2D, right: Vector2D) -> Vector2D { Vector2D(x: left.x - right.x, y: left.y - right.y) }
//    static func * (left: CGFloat, right: Vector2D) -> Vector2D { Vector2D(x: left * right.x, y: left * right.y) }
//    static func * (left: Vector2D, right: CGFloat) -> Vector2D { Vector2D(x: left.x * right, y: left.y * right) }
//    static prefix func - (vector: Vector2D) -> Vector2D { Vector2D(x: -vector.x, y: -vector.y) }
//    init(x: CGFloat = 0, y: CGFloat = 0) { self.x = x; self.y = y }
//    init(_ point: CGPoint) { self.x = point.x; self.y = point.y }
//    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
//}
//func interpolateCatmullRom(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint { /* Unchanged */
//    let t2=t*t; let t3=t2*t; let v0=Vector2D(p0); let v1=Vector2D(p1); let v2=Vector2D(p2); let v3=Vector2D(p3);
//    let term1=v1; let term2=0.5*(v2-v0)*t; let term3=0.5*(2*v0-5*v1+4*v2-v3)*t2; let term4=0.5*(-v0+3*v1-3*v2+v3)*t3;
//    return (term1+term2+term3+term4).cgPoint
//}
//func generateDenseCatmullRomPoints(controlPoints: [CGPoint], pointsPerSegment: Int) -> [CGPoint] { /* Unchanged */
//    guard controlPoints.count >= 2 else { return controlPoints }; guard pointsPerSegment > 0 else { return controlPoints };
//    var densePoints: [CGPoint] = []; let n = controlPoints.count;
//    for i in 0..<(n - 1) { let p1=controlPoints[i]; let p2=controlPoints[i+1]; let p0=(i > 0) ? controlPoints[i-1] : p1; let p3=(i < n - 2) ? controlPoints[i+2] : p2; if i == 0 { densePoints.append(p1) }; for j in 1...pointsPerSegment { let t=CGFloat(j)/CGFloat(pointsPerSegment); densePoints.append(interpolateCatmullRom(p0:p0,p1:p1,p2:p2,p3:p3,t:t)) } }; return densePoints
//}
//func createPathFromDensePoints(points: [CGPoint], closePath: Bool, baseLevel: CGFloat) -> UIBezierPath { /* Unchanged */
//    let path = UIBezierPath(); guard let firstPoint = points.first else { return path }; if closePath { path.move(to: CGPoint(x: firstPoint.x, y: baseLevel)); path.addLine(to: firstPoint) } else { path.move(to: firstPoint) }; for i in 1..<points.count { path.addLine(to: points[i]) }; if closePath, points.count > 1, let lastPoint = points.last { path.addLine(to: CGPoint(x: lastPoint.x, y: baseLevel)); path.close() }; return path
//}
//
//
//// MARK: - Day/Night Cycle Definitions
//struct TimeOfDayConstants {
//    // Time points (0.0 = midnight, 0.25 = 6am, 0.5 = noon, 0.75 = 6pm)
//    static let dawnStartTime: Float = 0.23
//    static let sunriseTime: Float = 0.25
//    static let morningEndTime: Float = 0.35 // Shorter morning color transition
//    static let middayStartTime: Float = 0.40 // Start midday white earlier
//    static let middayEndTime: Float = 0.60   // End midday white later
//    static let afternoonStartTime: Float = 0.65 // Start sunset colors later
//    static let sunsetTime: Float = 0.75
//    static let duskEndTime: Float = 0.77
//
//    // Durations for interpolation
//    static let dawnDuration = sunriseTime - dawnStartTime
//    static let morningColorDuration = morningEndTime - sunriseTime
//    static let afternoonColorDuration = sunsetTime - afternoonStartTime
//    static let duskDuration = duskEndTime - sunsetTime
//
//    struct SkyColors { /* Unchanged */
//        static let nightTop = UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1.0); static let nightBottom = UIColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1.0)
//        static let dawnTop = UIColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1.0); static let dawnBottom = UIColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 1.0)
//        static let dayTop = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0); static let dayBottom = UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1.0)
//        static let sunsetTop = UIColor(red: 0.2, green: 0.2, blue: 0.5, alpha: 1.0); static let sunsetBottom = UIColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1.0)
//    }
//
//    // --- Sun Colors (Tint for Disc) ---
//    struct SunColors {
//        static let dawn = UIColor(red: 1.0, green: 0.6, blue: 0.5, alpha: 1.0) // Orange/Pink tint
//        static let midday = UIColor.white // No tint during most of the day
//        static let sunset = UIColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 1.0) // Orange/Red tint
//    }
//
//    // --- Moon Colors (Tint for Disc Texture) ---
//    struct MoonColors {
//        static let base = UIColor(red: 0.90, green: 0.90, blue: 0.95, alpha: 1.0) // Base soft white/grey tint
//        // We can add subtle hue shift based on altitude later if needed
//    }
//
//    // --- Light Source Colors ---
//    struct LightColors { /* Unchanged */
//        static let sunDawn = UIColor(red: 1.0, green: 0.6, blue: 0.4, alpha: 1.0)
//        static let sunMorning = UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1.0)
//        static let sunMidday = UIColor.white
//        static let sunSunset = UIColor(red: 1.0, green: 0.7, blue: 0.5, alpha: 1.0)
//        static let ambientDawn = UIColor(white: 0.3, alpha: 1.0).interpolate(to: sunDawn, fraction: 0.2)
//        static let ambientDay = UIColor(white: 0.6, alpha: 1.0)
//        static let ambientSunset = UIColor(white: 0.3, alpha: 1.0).interpolate(to: sunSunset, fraction: 0.2)
//        static let ambientNight = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 1.0)
//        static let moon = UIColor(red: 0.7, green: 0.7, blue: 1.0, alpha: 1.0)
//    }
//
//    // --- Intensity Definitions --- (Slight adjustment maybe)
//    static let sunIntensityMax: CGFloat = 1800; static let sunIntensityDawnSunset: CGFloat = 1000
//    static let moonIntensityMax: CGFloat = 200 // Moon light slightly dimmer
//    static let ambientIntensityDay: CGFloat = 800; static let ambientIntensityDawnSunset: CGFloat = 500
//    static let ambientIntensityNight: CGFloat = 100 // Night even darker
//    static let starsIntensityMax: CGFloat = 1.0
//    static let sunGlowMaxBirthRate: CGFloat = 150 // Particle birth rate for sun glow peak
//}
//
//// MARK: - SwiftUI View Definition
//struct ParallaxTerrainSceneView: UIViewRepresentable {
//
//    // MARK: Configuration Constants
//    private let dayNightCycleEnabled = true
//    private let dayLengthInSeconds: TimeInterval = 180.0 // Slightly longer cycle
//    private let lunarCycleLengthInSeconds: TimeInterval = 60.0 * 5 // ~5 minutes for a full moon cycle for testing
//
//    // Textures & Particles (REPLACE WITH YOUR FILENAMES)
//    private let sunDiscTextureName = "sun_disc_texture.png" // Simple disc, maybe slightly soft edge, white/yellowish base
//    private let sunGlowParticleSystemName = "sun_glow.scnp" // Particle system for the glow
//    private let moonPhaseTexturePrefix = "moon_phase_" // E.g., "moon_phase_0.png" ... "moon_phase_7.png"
//    private let starParticleSystemName = "Stars.scnp"
//
//    // --- Terrain Configuration ---
//    // Near Terrain
//    private let terrainSegmentWidth: CGFloat = 40.0
//    private let nearSegmentCount = 5
//    // ** Amplitude Limit for Near Terrain **
//    private let nearTerrainAmplitude: CGFloat = 8.0 // Max random vertical deviation
//    private let nearTerrainVerticalOffset: CGFloat = -5.0
//    private let baseScrollSpeed: CGFloat = 0.15 // Base speed (units/sec? Needs clarification, assume units/frame for now)
//    private let pointsPerSegmentSpline = 10
//    private let terrainExtrusionDepth: CGFloat = 0.5
//    private let nearTerrainZPosition: Float = 4.0
//    private let nearTerrainBaseHue: CGFloat = 0.3; private let nearTerrainHueVariance: CGFloat = 0.05
//    private let nearTerrainSaturationRange: ClosedRange<CGFloat> = 0.6...0.8
//    private let nearTerrainBrightnessRange: ClosedRange<CGFloat> = 0.6...0.8
//
//    // Mid-Ground Terrain (Now Dynamic)
//    // ** Amplitude Limit for Mid Terrain (relative to near) **
//    private let midTerrainAmplitudeScale: CGFloat = 0.6 // Mid fluctuates 60% as much as near
//    private let midTerrainVerticalOffsetBelowNear: CGFloat = 4.0 // How far below near terrain's avg Y
//    private let midTerrainZPosition: Float = 6.0
//    private let midTerrainScrollSpeedFactor: Float = 0.6 // Scrolls slower than near
//    private let midTerrainExtrusionDepth: CGFloat = 0.1
//    private let midTerrainColor = UIColor(hue: nearTerrainBaseHue, saturation: 0.5, brightness: 0.5, alpha: 0.9) // Base color for segments
//
//    // Far Terrain (Static Tiled)
//    private let farTerrainWidth: CGFloat = 250; private let farTerrainAmplitude: CGFloat = 5.0
//    private let farTerrainVerticalOffset: CGFloat = -15.0 // Further down
//    private let farTerrainZPosition: Float = -40; private let farTerrainScrollSpeedFactor: Float = 0.2
//    private let farTerrainExtrusionDepth: CGFloat = 1.0; private let farTerrainColor = UIColor.darkGray.withAlphaComponent(0.6)
//    private let farTerrainControlPointCount = 15; private let farTerrainPointsPerSegmentSpline = 5
//
//    // Character Config
//    private let characterStickHeight: CGFloat = 1.6; private let characterStickRadius: CGFloat = 0.2
//    private let fixedCharacterBaseY: Float = -1.0; private let characterZPosition: Float = 4.0
//
//    // Day/Night Cycle Config
//    private let trajectoryRadiusX: Float = 100.0; private let trajectoryRadiusY: Float = 50.0
//    private let trajectoryCenterY: Float = -10.0; private let celestialBodyZ: Float = -60.0
//    private let sunDiscVisualSize: CGFloat = 10.0 // Size of the central disc billboard
//    private let moonVisualSize: CGFloat = 15.0 // Size of the moon phase billboard
//    private let sunSetScaleFactor: Float = 1.15
//
//    // Dynamic Scroll Speed Config
//    private let maxUphillSlopeForMaxSlowdown: CGFloat = 1.0 // Slope of 1.0 (45 degrees) causes max slowdown
//    private let minScrollSpeedFactor: Float = 0.3 // Minimum speed is 30% of base speed when going uphill
//
//
//    // --- UIViewRepresentable Methods ---
//    func makeCoordinator() -> Coordinator {
//        Coordinator(
//            // General
//            dayNightCycleEnabled: dayNightCycleEnabled,
//            dayLengthInSeconds: dayLengthInSeconds,
//            lunarCycleLengthInSeconds: lunarCycleLengthInSeconds,
//            // Near Terrain
//            terrainSegmentWidth: terrainSegmentWidth,
//            nearSegmentCount: nearSegmentCount,
//            nearTerrainAmplitude: nearTerrainAmplitude,
//            nearTerrainVerticalOffset: nearTerrainVerticalOffset,
//            baseScrollSpeed: baseScrollSpeed,
//            pointsPerSegmentSpline: pointsPerSegmentSpline,
//            nearTerrainExtrusionDepth: terrainExtrusionDepth,
//            nearTerrainZPosition: nearTerrainZPosition,
//            nearTerrainBaseHue: nearTerrainBaseHue,
//            nearTerrainHueVariance: nearTerrainHueVariance,
//            nearTerrainSaturationRange: nearTerrainSaturationRange,
//            nearTerrainBrightnessRange: nearTerrainBrightnessRange,
//            // Mid Terrain (Dynamic)
//            midTerrainAmplitudeScale: midTerrainAmplitudeScale,
//            midTerrainVerticalOffsetBelowNear: midTerrainVerticalOffsetBelowNear,
//            midTerrainZPosition: midTerrainZPosition,
//            midTerrainScrollSpeedFactor: midTerrainScrollSpeedFactor,
//            midTerrainExtrusionDepth: midTerrainExtrusionDepth,
//            midTerrainColor: midTerrainColor,
//            // Character
//            fixedCharacterBaseY: fixedCharacterBaseY,
//            characterZPosition: characterZPosition,
//            // Day/Night Visuals
//            trajectoryRadiusX: trajectoryRadiusX,
//            trajectoryRadiusY: trajectoryRadiusY,
//            trajectoryCenterY: trajectoryCenterY,
//            celestialBodyZ: celestialBodyZ,
//            sunDiscVisualSize: sunDiscVisualSize,
//            moonVisualSize: moonVisualSize,
//            sunSetScaleFactor: sunSetScaleFactor,
//            sunDiscTextureName: sunDiscTextureName,
//            sunGlowParticleSystemName: sunGlowParticleSystemName,
//            moonPhaseTexturePrefix: moonPhaseTexturePrefix,
//            starParticleSystemName: starParticleSystemName,
//            // Dynamic Speed
//            maxUphillSlopeForMaxSlowdown: maxUphillSlopeForMaxSlowdown,
//            minScrollSpeedFactor: minScrollSpeedFactor
//        )
//    }
//
//    func makeUIView(context: Context) -> SCNView {
//        let scnView = SCNView(frame: .zero); scnView.backgroundColor = .black
//        scnView.autoenablesDefaultLighting = false; scnView.rendersContinuously = true
//        scnView.delegate = context.coordinator
//        let scene = SCNScene(); scnView.scene = scene
//        context.coordinator.scene = scene
//
//        // Initial Scene Elements (Lights, Sun, Moon, Stars)
//        context.coordinator.setupInitialSceneElements()
//
//        // Static Far Terrain (Tiled)
//        let baseWorldSpeed = Float(baseScrollSpeed) * 60 // Estimate for static layer duration calculation
//        setupTiledBackgroundLayer(
//            scene: scene, baseName: "FarTerrain", width: farTerrainWidth, amplitude: farTerrainAmplitude,
//            verticalOffset: farTerrainVerticalOffset, color: farTerrainColor, extrusionDepth: farTerrainExtrusionDepth,
//            controlPointCount: farTerrainControlPointCount, pointsPerSegmentSpline: farTerrainPointsPerSegmentSpline,
//            zPosition: farTerrainZPosition, scrollSpeedFactor: farTerrainScrollSpeedFactor, baseWorldSpeed: baseWorldSpeed
//        )
//
//        // Dynamic Near and Mid Terrain & Character (Setup handled by Coordinator)
//        context.coordinator.setupDynamicTerrainAndCharacter()
//
//        // Camera
//        let cameraNode = SCNNode(); cameraNode.camera = SCNCamera(); cameraNode.camera?.zFar = 250
//        cameraNode.position = SCNVector3(0, 5, 20); cameraNode.eulerAngles = SCNVector3(-Float.pi / 18, 0, 0)
//        scene.rootNode.addChildNode(cameraNode)
//
//        // Set initial cycle state
//        context.coordinator.updateDayNightCycle(deltaTime: 0, currentScrollSpeed: baseScrollSpeed) // Pass initial speed
//
//        return scnView
//    }
//
//    func updateUIView(_ uiView: SCNView, context: Context) { /* Coordinator handles updates */ }
//
//    // --- Helper Functions ---
//
//    // setupTiledBackgroundLayer (Only needed for Far Terrain now)
//    func setupTiledBackgroundLayer(scene: SCNScene, baseName: String, width: CGFloat, amplitude: CGFloat, verticalOffset: CGFloat, color: UIColor, extrusionDepth: CGFloat, controlPointCount: Int, pointsPerSegmentSpline: Int, zPosition: Float, scrollSpeedFactor: Float, baseWorldSpeed: Float) { /* Unchanged Implementation */
//        let terrainNode1 = createStaticTerrainNode(width: width, amplitude: amplitude, verticalOffset: verticalOffset, color: color, extrusionDepth: extrusionDepth, controlPointCount: controlPointCount, pointsPerSegmentSpline: pointsPerSegmentSpline); terrainNode1.name = "\(baseName)1"; terrainNode1.castsShadow = false; terrainNode1.position = SCNVector3(0, 0, 0);
//        let terrainNode2 = createStaticTerrainNode(width: width, amplitude: amplitude, verticalOffset: verticalOffset, color: color, extrusionDepth: extrusionDepth, controlPointCount: controlPointCount, pointsPerSegmentSpline: pointsPerSegmentSpline); terrainNode2.name = "\(baseName)2"; terrainNode2.castsShadow = false; terrainNode2.position = SCNVector3(Float(width), 0, 0);
//        let parentNode = SCNNode(); parentNode.name = "\(baseName)Parent"; parentNode.position = SCNVector3(0, 0, zPosition); parentNode.addChildNode(terrainNode1); parentNode.addChildNode(terrainNode2); scene.rootNode.addChildNode(parentNode);
//        let scrollDistance = Float(width); let effectiveSpeed = abs(baseWorldSpeed * scrollSpeedFactor); guard effectiveSpeed > 0.001 else { return }; let duration = TimeInterval(scrollDistance / effectiveSpeed);
//        let moveAction = SCNAction.moveBy(x: -width, y: 0, z: 0, duration: duration); let resetAction = SCNAction.moveBy(x: width, y: 0, z: 0, duration: 0); let sequence = SCNAction.sequence([moveAction, resetAction]); let repeatForever = SCNAction.repeatForever(sequence); parentNode.runAction(repeatForever);
//     }
//
//    // generateGradientImage (Unchanged)
//    func generateGradientImage(size: CGSize, topColor: UIColor, bottomColor: UIColor) -> UIImage? { /* Unchanged Implementation */
//        let renderer = UIGraphicsImageRenderer(size: size); return renderer.image { ctx in let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray; guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else { return }; ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: 0), end: CGPoint(x: size.width / 2, y: size.height), options: []) }
//    }
//
//    // --- Sun Node Creation (Disc Billboard + Glow Particles) ---
//    func createSunNode(discTextureName: String, glowParticleSystemName: String, size: CGFloat) -> SCNNode {
//        let sunParent = SCNNode()
//        sunParent.name = "SunVisualParent"
//
//        // Sun Disc Billboard
//        let plane = SCNPlane(width: size, height: size)
//        let material = SCNMaterial()
//        material.lightingModel = .constant
//        if let image = UIImage(named: discTextureName) {
//            material.emission.contents = image
//        } else {
//            print("Warning: Sun disc texture '\(discTextureName)' not found.")
//            material.emission.contents = UIColor.white // Fallback
//        }
//        material.multiply.contents = UIColor.white // Tinted later
//        material.writesToDepthBuffer = false
//        material.blendMode = .alpha
//        plane.materials = [material]
//
//        let discNode = SCNNode(geometry: plane)
//        discNode.name = "SunDisc"
//        discNode.castsShadow = false
//        discNode.constraints = [SCNBillboardConstraint()]
//        sunParent.addChildNode(discNode)
//
//        // Programmatic Glow (Particle System)
//        if let glowSystem = SCNParticleSystem(named: glowParticleSystemName, inDirectory: nil) {
//            // Initial properties (can be adjusted dynamically too)
//            glowSystem.birthRate = 0 // Start with no glow
//            glowSystem.particleIntensity = 1.0
//            glowSystem.particleColor = .white // Tinted by intensity/time later maybe
//            // Ensure particles render correctly (additive or alpha blend)
//            let glowNode = SCNNode()
//            glowNode.name = "SunGlowParticles"
//            glowNode.addParticleSystem(glowSystem)
//            // Position glow slightly behind or at the same place as the disc
//            glowNode.position = SCNVector3(0, 0, 0.1)
//            sunParent.addChildNode(glowNode) // Add glow as child of parent
//        } else {
//            print("Warning: Sun glow particle system '\(glowParticleSystemName)' not found.")
//        }
//
//        return sunParent
//    }
//
//    // --- Moon Node Creation (Billboard Texture for Phases) ---
//    func createMoonNode(texturePrefix: String, size: CGFloat) -> SCNNode {
//        let plane = SCNPlane(width: size, height: size)
//        let material = SCNMaterial()
//        material.lightingModel = .constant
//        // Initial texture (e.g., new moon or full moon) - will be changed dynamically
//        if let image = UIImage(named: "\(texturePrefix)4.png") { // Start with full moon maybe
//             material.emission.contents = image
//        } else {
//            print("Warning: Initial Moon texture '\(texturePrefix)4.png' not found.")
//            material.emission.contents = UIColor.lightGray // Fallback
//        }
//        material.multiply.contents = UIColor.white // Tinted later
//        material.writesToDepthBuffer = false
//        material.blendMode = .alpha
//        plane.materials = [material]
//
//        let node = SCNNode(geometry: plane)
//        node.name = "MoonVisual"
//        node.castsShadow = false
//        node.constraints = [SCNBillboardConstraint()]
//        return node
//    }
//
//    // createStarsNode (Unchanged - uses particle system)
//    func createStarsNode(particleSystemName: String, trajectoryCenterY: Float, trajectoryRadiusY: Float, celestialBodyZ: Float) -> SCNNode { /* Unchanged */
//        let starsNode = SCNNode(); starsNode.name = "Stars"; if let stars = SCNParticleSystem(named: particleSystemName, inDirectory: nil) { stars.particleSize=0.1; stars.birthRate=500; stars.particleLifeSpan=1000; stars.emitterShape=SCNSphere(radius:150); stars.emissionDuration=1000; stars.spreadingAngle=180; stars.particleColor = .white; stars.particleIntensity=0; starsNode.addParticleSystem(stars); starsNode.position = SCNVector3(0, trajectoryCenterY + Float(trajectoryRadiusY*0.5), celestialBodyZ) } else { print("Error: Could not load particle system '\(particleSystemName)'") }; return starsNode
//     }
//
//    // createDirectionalLightNode (Unchanged)
//    func createDirectionalLightNode() -> SCNNode { /* Unchanged */
//        let light = SCNLight(); light.type = .directional; light.color = UIColor.white; light.intensity = 0; light.castsShadow = true; light.shadowMode = .deferred; light.shadowColor = UIColor.black.withAlphaComponent(0.7); light.shadowSampleCount = 4; light.shadowRadius = 6.0; light.shadowMapSize = CGSize(width: 1024, height: 1024); let lightNode = SCNNode(); lightNode.name = "DirectionalLight"; lightNode.light = light; lightNode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0); return lightNode
//     }
//    // createAmbientLightNode (Unchanged)
//    func createAmbientLightNode() -> SCNNode { /* Unchanged */
//        let ambientLight = SCNLight(); ambientLight.type = .ambient; ambientLight.color = UIColor.black; ambientLight.intensity = 0; let ambientLightNode = SCNNode(); ambientLightNode.name = "AmbientLight"; ambientLightNode.light = ambientLight; return ambientLightNode
//     }
//    // createStaticTerrainNode (Used only for Far Terrain now)
//     func createStaticTerrainNode(width: CGFloat, amplitude: CGFloat, verticalOffset: CGFloat, color: UIColor, extrusionDepth: CGFloat, controlPointCount: Int, pointsPerSegmentSpline: Int) -> SCNNode { /* Unchanged */
//         let dx = width/CGFloat(controlPointCount-1); var controlPoints:[CGPoint]=[]; let startX = -width/2; for i in 0..<controlPointCount { let x=startX+CGFloat(i)*dx; let y=CGFloat.random(in: -amplitude...amplitude)+verticalOffset; controlPoints.append(CGPoint(x:x,y:y)) }; let densePoints=generateDenseCatmullRomPoints(controlPoints:controlPoints,pointsPerSegment:pointsPerSegmentSpline); let baseLevel=verticalOffset-amplitude*2-10; let path=createPathFromDensePoints(points:densePoints,closePath:true,baseLevel:baseLevel); let shape=SCNShape(path:path,extrusionDepth:extrusionDepth); let material=SCNMaterial(); material.diffuse.contents=color; material.lightingModel = .blinn; material.isDoubleSided=(extrusionDepth < 0.01); shape.materials=[material]; return SCNNode(geometry:shape)
//     }
//    // createCharacterNode (Unchanged)
//    func createCharacterNode(height: CGFloat, radius: CGFloat) -> SCNNode { /* Unchanged */
//         let cylinder = SCNCylinder(radius:radius, height:height); let material=SCNMaterial(); material.diffuse.contents=UIColor.red; material.lightingModel = .blinn; cylinder.materials=[material]; let node=SCNNode(geometry:cylinder); node.name="CharacterStick"; node.castsShadow=true; node.pivot=SCNMatrix4MakeTranslation(0,-Float(height)/2,0); return node
//     }
//
//
//    // MARK: - Coordinator Class (Handles Updates)
//    class Coordinator: NSObject, SCNSceneRendererDelegate {
//
//        // MARK: Configuration Properties
//        let dayNightCycleEnabled: Bool; let dayLengthInSeconds: TimeInterval; let lunarCycleLengthInSeconds: TimeInterval
//        let terrainSegmentWidth: CGFloat; let nearSegmentCount: Int; let nearTerrainAmplitude: CGFloat; let nearTerrainVerticalOffset: CGFloat
//        let baseScrollSpeed: CGFloat; let pointsPerSegmentSpline: Int; let nearTerrainExtrusionDepth: CGFloat; let nearTerrainZPosition: Float
//        let nearTerrainBaseHue: CGFloat; let nearTerrainHueVariance: CGFloat; let nearTerrainSaturationRange: ClosedRange<CGFloat>; let nearTerrainBrightnessRange: ClosedRange<CGFloat>
//        let midTerrainAmplitudeScale: CGFloat; let midTerrainVerticalOffsetBelowNear: CGFloat; let midTerrainZPosition: Float; let midTerrainScrollSpeedFactor: Float; let midTerrainExtrusionDepth: CGFloat; let midTerrainColor: UIColor
//        let fixedCharacterBaseY: Float; let characterZPosition: Float
//        let trajectoryRadiusX: Float; let trajectoryRadiusY: Float; let trajectoryCenterY: Float; let celestialBodyZ: Float
//        let sunDiscVisualSize: CGFloat; let moonVisualSize: CGFloat; let sunSetScaleFactor: Float
//        let sunDiscTextureName: String; let sunGlowParticleSystemName: String; let moonPhaseTexturePrefix: String; let starParticleSystemName: String
//        let maxUphillSlopeForMaxSlowdown: CGFloat; let minScrollSpeedFactor: Float
//
//        // MARK: State Variables
//        weak var scene: SCNScene?
//        var timeOfDay: Float = 0.2 // Start just before sunrise
//        var lunarCycleTime: Float = 0.5 // Start at full moon phase
//        var lastUpdateTime: TimeInterval = 0
//        var currentScrollSpeed: CGFloat // Current speed adjusted for slope
//
//        // Scene Element References
//        var sunVisualParent: SCNNode? // Parent holds disc and glow
//        var sunGlowParticles: SCNParticleSystem?
//        var moonVisualNode: SCNNode?
//        var starsNode: SCNNode?
//        var directionalLightNode: SCNNode?
//        var ambientLightNode: SCNNode?
//
//        // Terrain State
//        var nearTerrainParent = SCNNode()
//        var midTerrainParent = SCNNode() // Parent node for mid-ground segments
//        var terrainNodes: [SCNNode] = [] // Near terrain nodes
//        var midTerrainNodes: [SCNNode] = [] // Mid terrain nodes
//        var globalControlPoints: [CGPoint] = [] // Near terrain control points
//        var globalMidControlPoints: [CGPoint] = [] // Mid terrain control points
//        var globalDenseTerrainPoints: [CGPoint] = [] // Near terrain dense points
//        var globalMidDenseTerrainPoints: [CGPoint] = [] // Mid terrain dense points
//        let controlPointsPerSegment = 5
//        weak var characterNode: SCNNode?
//        private var isNearTerrainSetupComplete: Bool = false // Changed name for clarity
//        private var isMidTerrainSetupComplete: Bool = false
//
//
//        // MARK: Initializer
//        init(dayNightCycleEnabled: Bool, dayLengthInSeconds: TimeInterval, lunarCycleLengthInSeconds: TimeInterval,
//             terrainSegmentWidth: CGFloat, nearSegmentCount: Int, nearTerrainAmplitude: CGFloat, nearTerrainVerticalOffset: CGFloat,
//             baseScrollSpeed: CGFloat, pointsPerSegmentSpline: Int, nearTerrainExtrusionDepth: CGFloat, nearTerrainZPosition: Float,
//             nearTerrainBaseHue: CGFloat, nearTerrainHueVariance: CGFloat, nearTerrainSaturationRange: ClosedRange<CGFloat>, nearTerrainBrightnessRange: ClosedRange<CGFloat>,
//             midTerrainAmplitudeScale: CGFloat, midTerrainVerticalOffsetBelowNear: CGFloat, midTerrainZPosition: Float, midTerrainScrollSpeedFactor: Float, midTerrainExtrusionDepth: CGFloat, midTerrainColor: UIColor,
//             fixedCharacterBaseY: Float, characterZPosition: Float,
//             trajectoryRadiusX: Float, trajectoryRadiusY: Float, trajectoryCenterY: Float, celestialBodyZ: Float,
//             sunDiscVisualSize: CGFloat, moonVisualSize: CGFloat, sunSetScaleFactor: Float,
//             sunDiscTextureName: String, sunGlowParticleSystemName: String, moonPhaseTexturePrefix: String, starParticleSystemName: String,
//             maxUphillSlopeForMaxSlowdown: CGFloat, minScrollSpeedFactor: Float)
//        {
//            self.dayNightCycleEnabled = dayNightCycleEnabled; self.dayLengthInSeconds = max(1.0, dayLengthInSeconds); self.lunarCycleLengthInSeconds = max(1.0, lunarCycleLengthInSeconds)
//            self.terrainSegmentWidth = terrainSegmentWidth; self.nearSegmentCount = nearSegmentCount; self.nearTerrainAmplitude = nearTerrainAmplitude; self.nearTerrainVerticalOffset = nearTerrainVerticalOffset
//            self.baseScrollSpeed = baseScrollSpeed; self.pointsPerSegmentSpline = pointsPerSegmentSpline; self.nearTerrainExtrusionDepth = nearTerrainExtrusionDepth; self.nearTerrainZPosition = nearTerrainZPosition
//            self.nearTerrainBaseHue = nearTerrainBaseHue; self.nearTerrainHueVariance = nearTerrainHueVariance; self.nearTerrainSaturationRange = nearTerrainSaturationRange; self.nearTerrainBrightnessRange = nearTerrainBrightnessRange
//            self.midTerrainAmplitudeScale = midTerrainAmplitudeScale; self.midTerrainVerticalOffsetBelowNear = midTerrainVerticalOffsetBelowNear; self.midTerrainZPosition = midTerrainZPosition; self.midTerrainScrollSpeedFactor = midTerrainScrollSpeedFactor; self.midTerrainExtrusionDepth = midTerrainExtrusionDepth; self.midTerrainColor = midTerrainColor
//            self.fixedCharacterBaseY = fixedCharacterBaseY; self.characterZPosition = characterZPosition
//            self.trajectoryRadiusX = trajectoryRadiusX; self.trajectoryRadiusY = trajectoryRadiusY; self.trajectoryCenterY = trajectoryCenterY; self.celestialBodyZ = celestialBodyZ
//            self.sunDiscVisualSize = sunDiscVisualSize; self.moonVisualSize = moonVisualSize; self.sunSetScaleFactor = sunSetScaleFactor
//            self.sunDiscTextureName = sunDiscTextureName; self.sunGlowParticleSystemName = sunGlowParticleSystemName; self.moonPhaseTexturePrefix = moonPhaseTexturePrefix; self.starParticleSystemName = starParticleSystemName
//            self.maxUphillSlopeForMaxSlowdown = maxUphillSlopeForMaxSlowdown; self.minScrollSpeedFactor = minScrollSpeedFactor
//            self.currentScrollSpeed = baseScrollSpeed // Initialize current speed
//            super.init()
//        }
//
//        // MARK: Setup
//        func setupInitialSceneElements() {
//            guard let scene = scene else { return }
//            let view = ParallaxTerrainSceneView() // Temporary instance to access creation helpers
//
//            // Lights
//            directionalLightNode = view.createDirectionalLightNode()
//            scene.rootNode.addChildNode(directionalLightNode!)
//            ambientLightNode = view.createAmbientLightNode()
//            scene.rootNode.addChildNode(ambientLightNode!)
//
//            // Day/Night Elements
//            if dayNightCycleEnabled {
//                sunVisualParent = view.createSunNode(discTextureName: sunDiscTextureName, glowParticleSystemName: sunGlowParticleSystemName, size: sunDiscVisualSize)
//                sunVisualParent?.position = SCNVector3(0, -1000, celestialBodyZ); sunVisualParent?.isHidden = true
//                // Store ref to particle system for dynamic control
//                self.sunGlowParticles = sunVisualParent?.childNode(withName: "SunGlowParticles", recursively: false)?.particleSystems?.first
//                scene.rootNode.addChildNode(sunVisualParent!)
//
//                moonVisualNode = view.createMoonNode(texturePrefix: moonPhaseTexturePrefix, size: moonVisualSize)
//                moonVisualNode?.position = SCNVector3(0, -1000, celestialBodyZ); moonVisualNode?.isHidden = true
//                scene.rootNode.addChildNode(moonVisualNode!)
//
//                starsNode = view.createStarsNode(particleSystemName: starParticleSystemName, trajectoryCenterY: trajectoryCenterY, trajectoryRadiusY: trajectoryRadiusY, celestialBodyZ: celestialBodyZ)
//                scene.rootNode.addChildNode(starsNode!)
//            }
//        }
//
//        func setupDynamicTerrainAndCharacter() {
//            guard let scene = scene else { return }
//            let view = ParallaxTerrainSceneView() // For character creation helper
//
//            // --- Setup Near Terrain Parent ---
//            nearTerrainParent.position = SCNVector3(0, 0, nearTerrainZPosition)
//            nearTerrainParent.name = "NearTerrainParent"
//            scene.rootNode.addChildNode(nearTerrainParent)
//
//            // --- Setup Mid Terrain Parent ---
//            midTerrainParent.position = SCNVector3(0, 0, midTerrainZPosition)
//            midTerrainParent.name = "MidTerrainParent"
//            scene.rootNode.addChildNode(midTerrainParent)
//
//            // --- Initial Terrain Generation ---
//            let initialSegmentsToGenerate = nearSegmentCount + 3 // Generate enough for initial view + buffer
//            for i in 0..<initialSegmentsToGenerate {
//                addNewTerrainSegment(isInitialSetup: true, indexForInitial: i)
//            }
//            print("Initial terrain setup complete. Near Segments: \(terrainNodes.count), Mid Segments: \(midTerrainNodes.count)")
//            isNearTerrainSetupComplete = true
//            isMidTerrainSetupComplete = true
//
//
//            // --- Create Character ---
//            let charNode = view.createCharacterNode(height: 1.6, radius: 0.2) // Use constants
//            charNode.position = SCNVector3(0, fixedCharacterBaseY, characterZPosition)
//            scene.rootNode.addChildNode(charNode)
//            self.characterNode = charNode
//
//            // --- Align Terrain AFTER character is placed ---
//            alignInitialTerrainVerticalPosition()
//        }
//
//        // Combined alignment for both layers
//        func alignInitialTerrainVerticalPosition() {
//             guard characterNode != nil else { return }
//
//             // Align Near Terrain
//             if let initialNearY = getDenseTerrainHeight(for: .near, at: 0) {
//                 nearTerrainParent.position.y = fixedCharacterBaseY - Float(initialNearY)
//             } else {
//                 nearTerrainParent.position.y = fixedCharacterBaseY - Float(nearTerrainVerticalOffset) // Fallback
//             }
//
//             // Align Mid Terrain (relative to near terrain's final Y)
//             if let initialMidY = getDenseTerrainHeight(for: .mid, at: 0) {
//                 // Target Y for mid-terrain surface = near terrain surface Y - offset_below
//                 let targetMidSurfaceY = nearTerrainParent.position.y + Float(getDenseTerrainHeight(for: .near, at: 0) ?? nearTerrainVerticalOffset) - Float(midTerrainVerticalOffsetBelowNear)
//                 midTerrainParent.position.y = targetMidSurfaceY - Float(initialMidY)
//             } else {
//                  // Fallback: Position relative to near parent's fallback position
//                 midTerrainParent.position.y = (fixedCharacterBaseY - Float(nearTerrainVerticalOffset)) - Float(midTerrainVerticalOffsetBelowNear) - Float(nearTerrainVerticalOffset * midTerrainAmplitudeScale) // Estimate mid offset
//             }
//             print("Initial Align: NearY=\(nearTerrainParent.position.y), MidY=\(midTerrainParent.position.y)")
//        }
//
//        // --- SCNSceneRendererDelegate Update Loop ---
//        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
//            guard scene != nil else { return }
//            if lastUpdateTime == 0 { lastUpdateTime = time }; let deltaTime = time - lastUpdateTime; lastUpdateTime = time
//
//            // 1. Update Day/Night Cycle (Time, Sun, Moon, Lights, Sky)
//            if dayNightCycleEnabled {
//                updateDayNightCycle(deltaTime: deltaTime, currentScrollSpeed: currentScrollSpeed)
//            }
//
//            // 2. Calculate Dynamic Scroll Speed based on Slope
//            updateCurrentScrollSpeed()
//
//            // 3. Update Terrain Layers (Scrolling, Vertical Adjustment, Segment Management)
//            updateTerrainLayers(deltaTime: deltaTime)
//        }
//
//
//        // MARK: Update Sub-functions
//        func updateDayNightCycle(deltaTime: TimeInterval, currentScrollSpeed: CGFloat) {
//            // --- Time Increment ---
//            timeOfDay = (timeOfDay + Float(deltaTime / dayLengthInSeconds)).truncatingRemainder(dividingBy: 1.0)
//            lunarCycleTime = (lunarCycleTime + Float(deltaTime / lunarCycleLengthInSeconds)).truncatingRemainder(dividingBy: 1.0)
//
//            // --- Calculate Angles & Positions ---
//            let T = TimeOfDayConstants.self
//            let dayDuration = T.sunsetTime - T.sunriseTime; let nightDuration = 1.0 - dayDuration
//            var sunAngle: Float? = nil; var moonAngle: Float? = nil
//            if timeOfDay >= T.sunriseTime && timeOfDay < T.sunsetTime { sunAngle = .pi - ((timeOfDay - T.sunriseTime) / dayDuration * .pi) }
//            else { let timeIntoNight = (timeOfDay >= T.sunsetTime) ? (timeOfDay - T.sunsetTime) : ((1.0 - T.sunsetTime) + timeOfDay); moonAngle = .pi - (timeIntoNight / nightDuration * .pi) }
//            var sunPosition = SCNVector3(0, -1000, celestialBodyZ); if let angle = sunAngle { sunPosition = calculateArcPosition(angle: angle) }
//            var moonPosition = SCNVector3(0, -1000, celestialBodyZ); if let angle = moonAngle { moonPosition = calculateArcPosition(angle: angle) }
//
//            // --- Get Properties ---
//            let sunProps = getSunProperties(timeOfDay: timeOfDay, sunAngle: sunAngle)
//            let moonProps = getMoonProperties(timeOfDay: timeOfDay, moonAngle: moonAngle)
//            let ambientProps = getAmbientLightProperties(timeOfDay: timeOfDay)
//            let skyColors = getSkyGradientColors(timeOfDay: timeOfDay)
//            let starsIntensity = getStarsIntensity(timeOfDay: timeOfDay)
//            let sunGlowBirthRate = getSunGlowBirthRate(timeOfDay: timeOfDay, sunAngle: sunAngle)
//            let moonPhaseIndex = getMoonPhaseIndex(lunarCycleTime: lunarCycleTime)
//
//            // --- Update Visual Nodes ---
//            // Sun
//            sunVisualParent?.position = sunPosition
//            sunVisualParent?.isHidden = !sunProps.isVisible
//            if let discMaterial = sunVisualParent?.childNode(withName: "SunDisc", recursively: false)?.geometry?.firstMaterial {
//                discMaterial.multiply.contents = sunProps.color // Tint disc
//                discMaterial.emission.intensity = sunProps.isVisible ? 1.0 : 0.0
//                 let altitudeFactor = sunAngle != nil ? sin(sunAngle!) : 0
//                 let scale = 1.0 + (1.0 - altitudeFactor) * (sunSetScaleFactor - 1.0)
//                 sunVisualParent?.scale = SCNVector3(scale, scale, 1)
//            }
//            sunGlowParticles?.birthRate = sunGlowBirthRate // Update glow particle emission
//
//            // Moon
//            moonVisualNode?.position = moonPosition
//            moonVisualNode?.isHidden = !moonProps.isVisible
//            if let material = moonVisualNode?.geometry?.firstMaterial {
//                material.multiply.contents = moonProps.color // Tint moon based on altitude/base
//                material.emission.intensity = moonProps.isVisible ? 0.9 : 0.0
//                // Update Moon Phase Texture
//                let textureName = "\(moonPhaseTexturePrefix)\(moonPhaseIndex).png"
//                 if (material.emission.contents as? UIImage)?.accessibilityIdentifier != textureName { // Avoid redundant texture loading
//                     if let phaseImage = UIImage(named: textureName) {
//                         phaseImage.accessibilityIdentifier = textureName // Tag image for comparison
//                         material.emission.contents = phaseImage
//                     } else if moonPhaseIndex != 0 { // Don't warn for new moon (phase 0) if texture missing
//                        // Only print warning once per missing texture? Might need more state.
//                        // print("Warning: Moon texture '\(textureName)' not found.")
//                     } else {
//                         // New moon, ensure it's black/invisible if texture 0 is missing
//                         material.emission.contents = UIColor.black
//                     }
//                 } else if moonPhaseIndex == 0 && material.emission.contents as? UIColor != .black {
//                      material.emission.contents = UIColor.black // Ensure new moon is black
//                 }
//                moonVisualNode?.scale = SCNVector3(1, 1, 1) // Reset scale
//            }
//
//            // --- Update Lighting ---
//            updateSceneLighting(sunProps: sunProps, moonProps: moonProps, ambientProps: ambientProps, sunPosition: sunPosition, moonPosition: moonPosition, sunAngle: sunAngle, moonAngle: moonAngle)
//
//            // --- Update Sky ---
//            updateSkyBackground(skyColors: skyColors)
//
//            // --- Update Stars ---
//            starsNode?.particleSystems?.first?.particleIntensity = starsIntensity
//        }
//
//        func updateSceneLighting(sunProps: SunProperties, moonProps: MoonProperties, ambientProps: AmbientProperties, sunPosition: SCNVector3, moonPosition: SCNVector3, sunAngle: Float?, moonAngle: Float?) {
//             if let light = directionalLightNode?.light {
//                 if sunProps.isVisible, let angle = sunAngle {
//                     let T = TimeOfDayConstants.self
//                     // Interpolate light color based on sun altitude for smoother transitions
//                     let altitudeFactor = sin(angle) // 0 at horizon, 1 at peak
//                     let dayColor = T.LightColors.sunMorning.interpolate(to: T.LightColors.sunMidday, fraction: CGFloat(altitudeFactor))
//                     light.color = T.LightColors.sunDawn.interpolate(to: dayColor, fraction: CGFloat(altitudeFactor)).interpolate(to: T.LightColors.sunSunset, fraction: 1.0 - CGFloat(altitudeFactor*0.8 + 0.2)) // Favor sunset color longer
//
//                     light.intensity = sunProps.intensity
//                     directionalLightNode?.look(at: SCNVector3(0,0,0), up: SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
//                     directionalLightNode?.position = sunPosition
//                 } else if moonProps.isVisible {
//                     light.intensity = moonProps.intensity
//                     light.color = TimeOfDayConstants.LightColors.moon
//                     directionalLightNode?.look(at: SCNVector3(0,0,0), up: SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
//                     directionalLightNode?.position = moonPosition
//                 } else {
//                     light.intensity = 0
//                 }
//             }
//             ambientLightNode?.light?.intensity = ambientProps.intensity
//             ambientLightNode?.light?.color = ambientProps.color
//        }
//
//        // Cache last background colors to avoid redundant updates
//        var lastSkyTopColor: UIColor?
//        var lastSkyBottomColor: UIColor?
//
//        func updateSkyBackground(skyColors: (top: UIColor, bottom: UIColor)) {
//            // Only update if colors have actually changed
//            if skyColors.top != lastSkyTopColor || skyColors.bottom != lastSkyBottomColor {
//                 if let gradientImage = ParallaxTerrainSceneView().generateGradientImage(size: CGSize(width: 1, height: 512), topColor: skyColors.top, bottomColor: skyColors.bottom) {
//                      scene?.background.contents = gradientImage
//                      lastSkyTopColor = skyColors.top
//                      lastSkyBottomColor = skyColors.bottom
//                 }
//            }
//        }
//
//
//        func updateCurrentScrollSpeed() {
//            guard let charPos = characterNode?.position else {
//                currentScrollSpeed = baseScrollSpeed
//                return
//            }
//
//            // X position relative to the near terrain parent's origin
//            let terrainLocalX = CGFloat(-nearTerrainParent.position.x)
//
//            // Get height slightly ahead to calculate slope
//            let lookAheadDistance: CGFloat = 0.5 // Check slope over this distance
//            guard let currentY = getDenseTerrainHeight(for: .near, at: terrainLocalX),
//                  let aheadY = getDenseTerrainHeight(for: .near, at: terrainLocalX + lookAheadDistance)
//            else {
//                // Cannot determine slope, use base speed
//                currentScrollSpeed = baseScrollSpeed
//                return
//            }
//
//            let slope = (aheadY - currentY) / lookAheadDistance
//
//            if slope > 0 { // Uphill
//                let uphillFactor = min(1.0, slope / maxUphillSlopeForMaxSlowdown) // 0 to 1
//                let speedFactor = 1.0 - uphillFactor * (1.0 - CGFloat(minScrollSpeedFactor)) // Interpolate between 1.0 and minFactor
//                currentScrollSpeed = baseScrollSpeed * speedFactor
//            } else { // Flat or Downhill
//                currentScrollSpeed = baseScrollSpeed
//            }
//             // print(String(format: "Slope: %.2f, SpeedFactor: %.2f, ScrollSpeed: %.3f", slope, speedFactor ?? 1.0, currentScrollSpeed))
//        }
//
//        func updateTerrainLayers(deltaTime: TimeInterval) {
//             guard characterNode != nil else { return }
//
//             // --- Scrolling ---
//             let scrollAmount = Float(currentScrollSpeed) // Use dynamically calculated speed
//             nearTerrainParent.position.x -= scrollAmount
//             midTerrainParent.position.x -= scrollAmount * midTerrainScrollSpeedFactor // Mid scrolls slower
//
//             // --- Vertical Adjustment ---
//             let targetTerrainLocalX = CGFloat(-nearTerrainParent.position.x) // Character is always at world X=0
//
//             // Adjust Near Terrain
//             if let nearY = getDenseTerrainHeight(for: .near, at: targetTerrainLocalX) {
//                 nearTerrainParent.position.y = fixedCharacterBaseY - Float(nearY)
//             } // Add fallback?
//
//             // Adjust Mid Terrain (relative to near terrain surface)
//             if let nearSurfaceY = getDenseTerrainHeight(for: .near, at: targetTerrainLocalX), // Use actual near Y
//                 let midY = getDenseTerrainHeight(for: .mid, at: targetTerrainLocalX / CGFloat(midTerrainScrollSpeedFactor)) { // Need to check mid terrain X corresponding to view
//                 // Target Y for mid surface = (near parent Y + near surface Y) - offset_below
//                 let targetMidSurfaceY = nearTerrainParent.position.y + Float(nearSurfaceY) - Float(midTerrainVerticalOffsetBelowNear)
//                 midTerrainParent.position.y = targetMidSurfaceY - Float(midY)
//             } // Add fallback?
//
//
//             // --- Manage Segments ---
//             manageTerrainSegments()
//        }
//
//
//        // MARK: Property Calculation Helpers
//
//        func calculateArcPosition(angle: Float) -> SCNVector3 { /* Unchanged */
//            let x=trajectoryRadiusX*cos(angle); let y=trajectoryCenterY+trajectoryRadiusY*sin(angle); return SCNVector3(x,y,celestialBodyZ)
//        }
//
//        // Define aliases for property tuples for clarity
//        typealias SunProperties = (color: UIColor, intensity: CGFloat, isVisible: Bool)
//        typealias MoonProperties = (color: UIColor, intensity: CGFloat, isVisible: Bool)
//        typealias AmbientProperties = (color: UIColor, intensity: CGFloat)
//
//        func getSunProperties(timeOfDay: Float, sunAngle: Float?) -> SunProperties {
//            guard let angle = sunAngle, angle > 0 && angle < .pi else { return (UIColor.black, 0, false) }
//            let T = TimeOfDayConstants.self
//            var color = T.SunColors.midday // Default white
//            var intensity = T.sunIntensityMax
//
//            // Apply color only during transitions
//            if timeOfDay >= T.dawnStartTime && timeOfDay < T.morningEndTime { // Dawn/Morning Rise Color
//                let progress = (timeOfDay - T.dawnStartTime) / (T.morningEndTime - T.dawnStartTime) // Longer transition for color
//                color = T.SunColors.dawn.interpolate(to: T.SunColors.midday, fraction: CGFloat(progress)) // Fade dawn color to white
//                // Intensity ramps up faster
//                if timeOfDay < T.sunriseTime {
//                    let intensityProgress = (timeOfDay - T.dawnStartTime) / T.dawnDuration
//                    intensity = T.sunIntensityDawnSunset * CGFloat(intensityProgress) // Ramp up from 0
//                } else {
//                     let intensityProgress = (timeOfDay - T.sunriseTime) / T.morningColorDuration
//                     intensity = T.sunIntensityDawnSunset + (T.sunIntensityMax - T.sunIntensityDawnSunset) * CGFloat(intensityProgress)
//                }
//
//            } else if timeOfDay >= T.afternoonStartTime && timeOfDay < T.duskEndTime { // Afternoon/Sunset Color
//                 let progress = (timeOfDay - T.afternoonStartTime) / (T.duskEndTime - T.afternoonStartTime)
//                 color = T.SunColors.midday.interpolate(to: T.SunColors.sunset, fraction: CGFloat(progress)) // Fade white to sunset color
//                 // Intensity ramps down faster
//                 if timeOfDay < T.sunsetTime {
//                     let intensityProgress = (timeOfDay - T.afternoonStartTime) / T.afternoonColorDuration
//                     intensity = T.sunIntensityMax - (T.sunIntensityMax - T.sunIntensityDawnSunset) * CGFloat(intensityProgress)
//                 } else {
//                      let intensityProgress = (timeOfDay - T.sunsetTime) / T.duskDuration
//                      intensity = T.sunIntensityDawnSunset * (1.0 - CGFloat(intensityProgress)) // Ramp down to 0
//                 }
//            } else if timeOfDay >= T.morningEndTime && timeOfDay < T.afternoonStartTime {
//                // Midday - Already set to white / max intensity
//            }
//
//            return (color, intensity, true)
//         }
//
//         func getSunGlowBirthRate(timeOfDay: Float, sunAngle: Float?) -> CGFloat {
//             guard let angle = sunAngle, angle > 0 && angle < .pi else { return 0 }
//             let T = TimeOfDayConstants.self
//             // Glow strongest when sun is high, fade near horizon
//             let altitudeFactor = sin(angle) // 0 at horizon, 1 at peak
//             return T.sunGlowMaxBirthRate * CGFloat(altitudeFactor)
//         }
//
//        func getMoonProperties(timeOfDay: Float, moonAngle: Float?) -> MoonProperties {
//            guard let angle = moonAngle, angle > 0 && angle < .pi else { return (UIColor.black, 0, false) }
//            let T = TimeOfDayConstants.self
//            // Base soft color, maybe slightly adjusted by altitude but keep it subtle
//            let altitudeFactor = sin(angle)
//            let color = T.MoonColors.base //.interpolate(to: T_MoonColors.high, fraction: CGFloat(altitudeFactor)) // Keep it simple now
//
//            // Intensity peaks when high
//            let intensity = T.moonIntensityMax * CGFloat(altitudeFactor)
//
//            return (color, intensity, true)
//         }
//
//        func getMoonPhaseIndex(lunarCycleTime: Float) -> Int {
//             // Map lunar cycle time (0 to 1) to 8 phases (0 to 7)
//             // 0: New, 1: Wax Cres, 2: First Q, 3: Wax Gibb, 4: Full, 5: Wan Gibb, 6: Third Q, 7: Wan Cres
//             let phase = lunarCycleTime * 8.0
//             return Int(floor(phase)) % 8
//         }
//
//        func getAmbientLightProperties(timeOfDay: Float) -> AmbientProperties { /* Unchanged */
//            let T=TimeOfDayConstants.self; var color=T.LightColors.ambientDay; var intensity=T.ambientIntensityDay;
//            if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime { let p=(timeOfDay-T.dawnStartTime)/T.dawnDuration; color=T.LightColors.ambientNight.interpolate(to:T.LightColors.ambientDawn,fraction:CGFloat(p)); intensity=T.ambientIntensityNight+(T.ambientIntensityDawnSunset-T.ambientIntensityNight)*CGFloat(p)}
//            else if timeOfDay>=T.sunriseTime&&timeOfDay<T.morningEndTime{ let p=(timeOfDay-T.sunriseTime)/(T.morningEndTime-T.sunriseTime); color=T.LightColors.ambientDawn.interpolate(to:T.LightColors.ambientDay,fraction:CGFloat(p)); intensity=T.ambientIntensityDawnSunset+(T.ambientIntensityDay-T.ambientIntensityDawnSunset)*CGFloat(p)}
//            else if timeOfDay>=T.afternoonStartTime&&timeOfDay<T.sunsetTime{ let p=(timeOfDay-T.afternoonStartTime)/(T.sunsetTime-T.afternoonStartTime); color=T.LightColors.ambientDay.interpolate(to:T.LightColors.ambientSunset,fraction:CGFloat(p)); intensity=T.ambientIntensityDay-(T.ambientIntensityDay-T.ambientIntensityDawnSunset)*CGFloat(p)}
//            else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime{ let p=(timeOfDay-T.sunsetTime)/T.duskDuration; color=T.LightColors.ambientSunset.interpolate(to:T.LightColors.ambientNight,fraction:CGFloat(p)); intensity=T.ambientIntensityDawnSunset-(T.ambientIntensityDawnSunset-T.ambientIntensityNight)*CGFloat(p)}
//            else if timeOfDay>=T.duskEndTime||timeOfDay<T.dawnStartTime{ color=T.LightColors.ambientNight; intensity=T.ambientIntensityNight }
//            return (color, intensity)
//         }
//
//        func getSkyGradientColors(timeOfDay: Float) -> (top: UIColor, bottom: UIColor) { /* Unchanged */
//            let T=TimeOfDayConstants.self; var top=T.SkyColors.dayTop; var bottom=T.SkyColors.dayBottom;
//            if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime{ let p=(timeOfDay-T.dawnStartTime)/T.dawnDuration; top=T.SkyColors.nightTop.interpolate(to:T.SkyColors.dawnTop,fraction:CGFloat(p)); bottom=T.SkyColors.nightBottom.interpolate(to:T.SkyColors.dawnBottom,fraction:CGFloat(p))}
//            else if timeOfDay>=T.sunriseTime&&timeOfDay<T.morningEndTime{ let p=(timeOfDay-T.sunriseTime)/(T.morningEndTime-T.sunriseTime); top=T.SkyColors.dawnTop.interpolate(to:T.SkyColors.dayTop,fraction:CGFloat(p)); bottom=T.SkyColors.dawnBottom.interpolate(to:T.SkyColors.dayBottom,fraction:CGFloat(p))}
//            else if timeOfDay>=T.afternoonStartTime&&timeOfDay<T.sunsetTime{ let p=(timeOfDay-T.afternoonStartTime)/(T.sunsetTime-T.afternoonStartTime); top=T.SkyColors.dayTop.interpolate(to:T.SkyColors.sunsetTop,fraction:CGFloat(p)); bottom=T.SkyColors.dayBottom.interpolate(to:T.SkyColors.sunsetBottom,fraction:CGFloat(p))}
//            else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime{ let p=(timeOfDay-T.sunsetTime)/T.duskDuration; top=T.SkyColors.sunsetTop.interpolate(to:T.SkyColors.nightTop,fraction:CGFloat(p)); bottom=T.SkyColors.sunsetBottom.interpolate(to:T.SkyColors.nightBottom,fraction:CGFloat(p))}
//            else if timeOfDay>=T.duskEndTime||timeOfDay<T.dawnStartTime{ top=T.SkyColors.nightTop; bottom=T.SkyColors.nightBottom }
//            return(top,bottom)
//         }
//
//        func getStarsIntensity(timeOfDay: Float) -> CGFloat { /* Unchanged */
//            let T=TimeOfDayConstants.self; var intensity:Float=0;
//            if timeOfDay>=T.duskEndTime||timeOfDay<T.dawnStartTime{ intensity=1 }
//            else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime{ let p=(timeOfDay-T.sunsetTime)/T.duskDuration; intensity=p }
//            else if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime{ let p=(timeOfDay-T.dawnStartTime)/T.dawnDuration; intensity=1-p }
//            return CGFloat(intensity)*T.starsIntensityMax
//         }
//
//        // MARK: Terrain Management (Now handles Near and Mid)
//
//        enum TerrainLayer { case near, mid }
//
//        func manageTerrainSegments() {
//            // Manage Near Terrain
//            manageSegments(for: .near, nodes: &terrainNodes, controlPoints: &globalControlPoints, densePoints: &globalDenseTerrainPoints, parent: nearTerrainParent)
//            // Manage Mid Terrain
//            manageSegments(for: .mid, nodes: &midTerrainNodes, controlPoints: &globalMidControlPoints, densePoints: &globalMidDenseTerrainPoints, parent: midTerrainParent)
//        }
//
//        func manageSegments(for layer: TerrainLayer, nodes: inout [SCNNode], controlPoints: inout [CGPoint], densePoints: inout [CGPoint], parent: SCNNode) {
//             guard let firstNode = nodes.first, !nodes.isEmpty else { return }
//
//             let firstNodeRightEdgeLocal = firstNode.position.x + Float(terrainSegmentWidth)
//             let firstNodeRightEdgeWorld = parent.convertPosition(SCNVector3(firstNodeRightEdgeLocal, 0, 0), to: nil).x
//             let removalThresholdX: Float = -Float(terrainSegmentWidth) * 2.0 // Increase buffer slightly
//
//             if firstNodeRightEdgeWorld < removalThresholdX {
//                 // --- Removal ---
//                 firstNode.removeFromParentNode()
//                 nodes.removeFirst()
//
//                 let controlPointsToRemove = controlPointsPerSegment - 1
//                 if controlPoints.count >= controlPointsToRemove {
//                     controlPoints.removeFirst(controlPointsToRemove)
//                 } else { controlPoints.removeAll() }
//
//                 let intervalsInRemovedSegment = controlPointsPerSegment - 1
//                 let densePointsToRemove: Int
//                 if pointsPerSegmentSpline > 0 {
//                     densePointsToRemove = intervalsInRemovedSegment * pointsPerSegmentSpline + 1
//                 } else {
//                     densePointsToRemove = controlPointsPerSegment
//                 }
//                 if densePoints.count >= densePointsToRemove {
//                     densePoints.removeFirst(densePointsToRemove)
//                 } else { densePoints.removeAll() }
//
//                 // --- Addition ---
//                 // Only add if managing the near layer, as addition is driven by near layer's control points
//                 if layer == .near {
//                     addNewTerrainSegment(isInitialSetup: false, indexForInitial: nil)
//                 }
//             }
//        }
//
//        // Adds a new segment to BOTH near and mid layers
//        func addNewTerrainSegment(isInitialSetup: Bool, indexForInitial: Int?) {
//            // 1. Add new control points for Near Terrain
//            let pointsToAdd = controlPointsPerSegment - 1
//            guard let lastNearControlPoint = globalControlPoints.last else {
//                print("Error: Cannot add near segment, no control points exist.")
//                return
//            }
//            var lastNearX = lastNearControlPoint.x
//            let dx = terrainSegmentWidth / CGFloat(controlPointsPerSegment - 1)
//            var addedNearPoints: [CGPoint] = []
//
//            for i in 0..<pointsToAdd {
//                lastNearX += dx
//                // Use near terrain amplitude limits
//                let newNearY = CGFloat.random(in: -nearTerrainAmplitude...nearTerrainAmplitude) + nearTerrainVerticalOffset
//                let newNearPoint = CGPoint(x: lastNearX, y: newNearY)
//                globalControlPoints.append(newNearPoint)
//                addedNearPoints.append(newNearPoint)
//
//                // 2. Derive and add corresponding Mid Terrain control points
//                // midY = (nearY - nearOffset) * midAmplitudeScale + midOffset
//                // where midOffset should place it correctly relative to nearOffset and the desired gap
//                let midOffset = nearTerrainVerticalOffset - midTerrainVerticalOffsetBelowNear // Target average Y for mid
//                let newMidY = (newNearY - nearTerrainVerticalOffset) * midTerrainAmplitudeScale + midOffset
//                let newMidPoint = CGPoint(x: lastNearX, y: newMidY) // Use same X
//                globalMidControlPoints.append(newMidPoint)
//            }
//
//            // 3. Create the visual nodes for both layers
//            let segmentIndex = isInitialSetup ? indexForInitial! : terrainNodes.count
//
//            // Add Near Segment Node
//            if addTerrainSegmentNode(for: .near, atIndex: segmentIndex, isInitialSetup: isInitialSetup) == nil {
//                 print("Error: Failed to add new NEAR terrain segment node.")
//                 // Should potentially rollback control point additions here
//            }
//
//            // Add Mid Segment Node
//            if addTerrainSegmentNode(for: .mid, atIndex: segmentIndex, isInitialSetup: isInitialSetup) == nil {
//                 print("Error: Failed to add new MID terrain segment node.")
//                 // Should potentially rollback control point additions here
//            }
//        }
//
//        // Creates and adds a segment node for either Near or Mid layer
//        private func addTerrainSegmentNode(for layer: TerrainLayer, atIndex index: Int, isInitialSetup: Bool) -> SCNNode? {
//
//            let isNear = (layer == .near)
//            let controlPoints = isNear ? globalControlPoints : globalMidControlPoints
//            let parentNode = isNear ? nearTerrainParent : midTerrainParent
//            var nodes = isNear ? terrainNodes : midTerrainNodes // Get current array
//            var densePoints = isNear ? globalDenseTerrainPoints : globalMidDenseTerrainPoints // Get current array
//
//            // --- Calculate Indices ---
//            let startIndexMesh = index * (controlPointsPerSegment - 1)
//            let endIndexMesh = startIndexMesh + controlPointsPerSegment
//            let splineStartIndex = max(0, startIndexMesh - 1)
//            let splineEndIndex = min(controlPoints.count, endIndexMesh + 1)
//
//            guard (splineEndIndex - splineStartIndex) >= 2 else {
//                 print("Error creating \(layer) segment \(index): Not enough control points [\(splineStartIndex),\(splineEndIndex)). Total: \(controlPoints.count)")
//                 return nil
//            }
//            let segmentSplineInput = Array(controlPoints[splineStartIndex..<splineEndIndex])
//
//            // --- Generate Dense Points ---
//            let canUseCatmullRom = segmentSplineInput.count >= 4
//            let effectivePointsPerSegmentSpline = canUseCatmullRom ? self.pointsPerSegmentSpline : 0
//            let allDensePointsForSpline = generateDenseCatmullRomPoints(controlPoints: segmentSplineInput, pointsPerSegment: effectivePointsPerSegmentSpline)
//
//            // --- Extract Segment Points ---
//            let inputStartIndexOffset = startIndexMesh - splineStartIndex
//            let densePointsOffset = inputStartIndexOffset * (effectivePointsPerSegmentSpline > 0 ? effectivePointsPerSegmentSpline : 1)
//            let numberOfIntervalsInSegment = controlPointsPerSegment - 1
//            let densePointsCountInSegment = numberOfIntervalsInSegment * (effectivePointsPerSegmentSpline > 0 ? effectivePointsPerSegmentSpline : 1) + 1
//
//            guard densePointsOffset >= 0, densePointsCountInSegment > 0,
//                  (densePointsOffset + densePointsCountInSegment) <= allDensePointsForSpline.count else {
//                print("Error creating \(layer) segment \(index): Dense point slicing error.")
//                return nil
//            }
//            let segmentDensePointsRaw = Array(allDensePointsForSpline[densePointsOffset..<(densePointsOffset + densePointsCountInSegment)])
//
//            // --- Create Node Geometry ---
//            guard startIndexMesh < controlPoints.count else { return nil }
//            let segmentStartX = controlPoints[startIndexMesh].x
//            let localDensePoints = segmentDensePointsRaw.map { CGPoint(x: $0.x - segmentStartX, y: $0.y) }
//            guard !localDensePoints.isEmpty else { return nil }
//
//            // Use appropriate vertical offset and amplitude for base level calculation
//            let layerVerticalOffset = isNear ? nearTerrainVerticalOffset : (nearTerrainVerticalOffset - midTerrainVerticalOffsetBelowNear)
//            let layerAmplitude = isNear ? nearTerrainAmplitude : (nearTerrainAmplitude * midTerrainAmplitudeScale)
//            let baseLevel = layerVerticalOffset - layerAmplitude * 2.0 - 10.0 // Ensure well below
//
//            let newPath = createPathFromDensePoints(points: localDensePoints, closePath: true, baseLevel: baseLevel)
//
//            // --- Color & Node Creation ---
//            let segmentColor: UIColor
//            let extrusion: CGFloat
//            if isNear {
//                 let hue = nearTerrainBaseHue + CGFloat.random(in: -nearTerrainHueVariance...nearTerrainHueVariance)
//                 let saturation = CGFloat.random(in: nearTerrainSaturationRange)
//                 let brightness = CGFloat.random(in: nearTerrainBrightnessRange)
//                 segmentColor = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
//                 extrusion = nearTerrainExtrusionDepth
//            } else {
//                 segmentColor = midTerrainColor // Use fixed color for mid-ground segments
//                 extrusion = midTerrainExtrusionDepth
//            }
//
//            let newNode = createTerrainSegmentNode(path: newPath, color: segmentColor, extrusionDepth: extrusion, castsShadow: isNear) // Only near casts shadow
//            newNode.position = SCNVector3(Float(segmentStartX), 0, 0)
//            newNode.name = "\(layer)TerrainSegment_\(index)"
//            parentNode.addChildNode(newNode)
//
//            // --- Update Data Structures ---
//            let globalDensePointsToAdd = segmentDensePointsRaw
//
//            // Append to the correct arrays
//             nodes.append(newNode) // Append node to the mutable array passed inout
//             densePoints.append(contentsOf: globalDensePointsToAdd) // Append points to the mutable array
//
//             // Update the original arrays in the coordinator state
//             if isNear {
//                 terrainNodes = nodes
//                 globalDenseTerrainPoints = densePoints
//             } else {
//                 midTerrainNodes = nodes
//                 globalMidDenseTerrainPoints = densePoints
//             }
//
//             // Filter duplicates (Simplified - consider if really needed or causes issues)
//             filterDuplicatePoints(points: &densePoints)
//             if isNear { globalDenseTerrainPoints = densePoints } else { globalMidDenseTerrainPoints = densePoints }
//
//
//            return newNode
//        }
//
//        // Helper to create the visual node for a terrain segment
//        func createTerrainSegmentNode(path: UIBezierPath, color: UIColor, extrusionDepth: CGFloat, castsShadow: Bool) -> SCNNode {
//            let shape = SCNShape(path: path, extrusionDepth: extrusionDepth)
//            let material = SCNMaterial()
//            material.diffuse.contents = color
//            material.lightingModel = .blinn
//            material.isDoubleSided = (extrusionDepth < 0.01) // Double sided only if flat
//            shape.materials = [material]
//            let node = SCNNode(geometry: shape)
//            node.castsShadow = castsShadow
//            return node
//        }
//
//        // Helper to filter duplicate points (inout parameter)
//         func filterDuplicatePoints(points: inout [CGPoint]) {
//             guard points.count > 1 else { return }
//             var uniquePoints: [CGPoint] = [points.first!]
//             for i in 1..<points.count {
//                 let dx = abs(points[i].x - points[i-1].x)
//                 let dy = abs(points[i].y - points[i-1].y)
//                 if dx > 0.001 || dy > 0.001 {
//                     uniquePoints.append(points[i])
//                 }
//             }
//             points = uniquePoints
//         }
//
//
//        // Gets terrain height for either Near or Mid layer
//        func getDenseTerrainHeight(for layer: TerrainLayer, at globalX: CGFloat) -> CGFloat? {
//            let densePoints = (layer == .near) ? globalDenseTerrainPoints : globalMidDenseTerrainPoints
//            let scrollFactor = (layer == .near) ? 1.0 : midTerrainScrollSpeedFactor
//            let parentX = (layer == .near) ? nearTerrainParent.position.x : midTerrainParent.position.x
//
//            // Adjust globalX based on the layer's own scroll factor and parent position
//             // We need the X coordinate *within the dense points array* for this layer
//             // Character is at world X = 0.
//             // World X = parent.x + localX => localX = -parent.x
//             let targetLocalX = -parentX
//
//            guard densePoints.count >= 2 else { return nil }
//
//            // Search within the appropriate dense points array using the layer's local X
//            for i in 0..<(densePoints.count - 1) {
//                let pA = densePoints[i]; let pB = densePoints[i+1]
//                let tolerance: CGFloat = 0.001 // Increased tolerance slightly
//                if (pA.x - tolerance) <= CGFloat(targetLocalX) && CGFloat(targetLocalX) <= (pB.x + tolerance) {
//                    if abs(pB.x - pA.x) < tolerance { return (pA.y + pB.y) / 2.0 }
//                    let t = (CGFloat(targetLocalX) - pA.x) / (pB.x - pA.x)
//                    let clampedT = max(0.0, min(1.0, t))
//                    return pA.y + clampedT * (pB.y - pA.y)
//                }
//            }
//             // Handle boundary cases by returning first/last point Y within that layer's data
//            if let first = densePoints.first, CGFloat(targetLocalX) < first.x { return first.y }
//            if let last = densePoints.last, CGFloat(targetLocalX) > last.x { return last.y }
//
//            print("Error: Could not find \(layer) height at localX \(targetLocalX)")
//            return nil
//        }
//
//        // --- Cleanup ---
//        deinit {
//            print("Coordinator deinit.")
//            nearTerrainParent.childNodes.forEach { $0.removeFromParentNode() }; nearTerrainParent.removeFromParentNode()
//            midTerrainParent.childNodes.forEach { $0.removeFromParentNode() }; midTerrainParent.removeFromParentNode()
//            // Arrays will deallocate automatically
//        }
//    }
//}
