// 太阳 月亮形状和轨迹改进 v1.8 - Sun Glow Effect
 // Modified: Far terrain uses static mesh (largeMountain.obj)
 // Added: Three mid-ground mesh layers for parallax effect
 // Fixed: Mesh loading compilation errors
 // V1.9: Added shader-based coloring and fog for static terrain layers
 // V1.9.2: Corrected shader syntax again for SceneKit Shader Modifiers
 // V2.0: Implemented infinite scrolling for mid-ground layers
 // V2.1: Replaced simple sun with 7-layer Alto's Adventure style sun complex

 import SwiftUI
 import SceneKit
 import GameplayKit // Needed for random numbers
 import ModelIO      // Needed for MDLAsset, MDLMesh
 import SceneKit.ModelIO // Needed for SCNGeometry(mdlMesh:)
 import MetalKit     // Needed for MTKMeshBufferAllocator and
 
//vertex descriptors

// MARK: - Shader Definition (Dynamic Cold/Warm Tint, SceneKit-compatible)
let terrainShaderModifier = """
// Uniforms
uniform vec4 u_baseColor;
uniform vec4 u_peakColor;
uniform vec4 u_fogColor;
uniform float u_minHeight;
uniform float u_maxHeight;
uniform float u_fogStartDistance;
uniform float u_fogDensity;

// Time-based tint
uniform float u_timeOfDay;      // 0.0…1.0, 0 = midnight, 0.5 = noon
uniform vec4 u_coldTintColor;   // Morning cold tint
uniform vec4 u_warmTintColor;   // Evening warm tint
uniform vec4 u_ambientColor; // NEW: Ambient color uniform

#pragma surface

// 1. World-space position
vec3 modelPos = _surface.position.xyz;

// 2. Height factor
float h = clamp(modelPos.y, u_minHeight, u_maxHeight);
float heightFactor = (h - u_minHeight) / max(0.001, u_maxHeight - u_minHeight);

// 3. Fog factor
vec4 pv = u_modelViewTransform * vec4(modelPos, 1.0);
float viewZ = abs(pv.z / pv.w);
float fogFactor = clamp((viewZ - u_fogStartDistance) * u_fogDensity, 0.0, 1.0);

// 4. Base terrain color and fog blend
vec4 terrainColor = mix(u_baseColor, u_peakColor, heightFactor);
vec4 fogged = mix(terrainColor, u_fogColor, fogFactor);

// NEW: Blend terrain/fog color with ambient light explicitly
// This ensures the ambient color affects the base color before directional light/tint
vec3 ambientBlendedRGB = mix(fogged.rgb, u_ambientColor.rgb, 0.5); // Adjust blend factor as needed

// 5. Day-phase for tint (sin wave: midnight->0, noon->1)
float dayPhase = clamp(sin(u_timeOfDay * 3.1415926), 0.0, 1.0);
vec4 tintColor = mix(u_coldTintColor, u_warmTintColor, dayPhase);

// 6. Final blend: apply small tint overlay AND directional light
// The standard Blinn model handles directional and specular, but we control ambient blend here.
// By setting _surface.diffuse = vec4(ambientBlendedRGB, fogged.a);, we provide a base color
// that already incorporates ambient and fog, which Blinn then uses.

// 7. Output - Use the ambientBlendedRGB for the diffuse component
_surface.diffuse = vec4(ambientBlendedRGB, fogged.a);

// Optionally, if you want the ambient to purely add/multiply, adjust here.
// For now, blending seems a good approach.

"""
// MARK: - Sun Glow Surface Shader Modifier (SceneKit)
let sunCoreSurfaceModifier = """
#pragma arguments
float4 u_color;
#pragma body
// 使用 SceneKit 自动采样好的 diffuse 值
float4 tex = _surface.diffuse;
tex.rgb *= tex.a;  // 预乘 Alpha
// ✅ 丢弃 alpha 太低的像素，防止背景透出
if (tex.a < 0.8) {
    discard_fragment();
}
_surface.diffuse = tex * u_color * 1.5;
"""
// MARK: - Sun Glow Surface Shader Modifier (SceneKit)
let sunGlowSurfaceModifier = """
#pragma arguments
// Texture samplers
texture2d<float> u_mainTex [[texture(0)]];
texture2d<float> u_glowTex [[texture(1)]];

// Uniforms
float4 u_color;      // RGBA main color
float4 u_glowColor;  // RGBA glow tint color
float  u_glowScale;  // Glow intensity (0.0–1.0)

#pragma body
// Sample base texture
float2 uv = _surface.diffuseTexcoord;

constexpr sampler s(address::repeat, filter::linear);
float4 baseColor = u_mainTex.sample(s, uv);
float4 mask      = u_glowTex.sample(s, uv);

// Apply main color tint
float4 lit = baseColor * u_color;

// Compute glow contribution
float4 glowContrib = baseColor * (u_glowColor * u_glowScale * 4.0);

// Blend lit and glowContrib, then mix towards pure glowColor for softness
float4 litPlusGlow = lit + glowContrib;
float glowMix = u_glowScale * 0.9;
float4 softGlow = mix(litPlusGlow, u_glowColor, glowMix);

// Final color: interpolate between lit and softGlow by mask.r
float4 outColor = mix(lit, softGlow, mask.r);
//加入动态 alpha 逻辑
float glowAlpha = mask.r * u_glowScale;   // 随 mask 和强度变化
outColor.a = glowAlpha;                   // 替换默认 alpha（不再是 1.0）
// Assign output
_surface.diffuse = outColor;
_surface.emission = outColor;
_surface.transparent = outColor.a;
"""

// MARK: - Halo Shader Definition
 let haloShaderModifier = """
 #pragma arguments
 // No extra uniforms needed for this basic version

 #pragma transparent
 #pragma body

 // --- Calculate Radial Alpha for Feathered Halo ---

 // 1. Get UV coordinates (assuming centered 0-1 range)
 vec2 uv = _surface.diffuseTexcoord;
 vec2 center = vec2(0.5);

 // 2. Calculate distance from center
 float d = distance(uv, center);

 // 3. Define Radii in UV space (0.0 to 0.5 from center)
 //    Outer radius corresponds to the edge of the 4.2m halo geometry (uv radius = 0.5)
 //    Inner radius corresponds to the edge of the 3.0m core geometry relative to the 4.2m halo geometry
 float coreHaloRatio = 3.0 / 4.2; // Approx 0.714
 float r0 = 0.5 * coreHaloRatio;  // Inner edge radius in UV space (approx 0.357)
 float r1 = 0.5;                  // Outer edge radius in UV space
 float rMid = (r0 + r1) * 0.5;    // Radius for peak alpha (approx 0.4285)

 // Add a tiny epsilon to avoid division by zero if r0=rMid or rMid=r1
 rMid = max(rMid, r0 + 0.001);
 r1 = max(r1, rMid + 0.001);

 // 4. Calculate Alpha using smoothstep for smooth transitions
 //    Fade In: 0->1 between r0 and rMid
 //    Fade Out: 1->0 between rMid and r1
 float fadeIn = smoothstep(r0, rMid, d);
 float fadeOut = 1.0 - smoothstep(rMid, r1, d);
 float alpha = fadeIn * fadeOut;

 // 5. Apply the calculated alpha
 //    Multiply with existing alpha (e.g., from texture or base color)
 //    Or set directly if base alpha is assumed to be 1.0
 _output.color.a *= alpha; // Use this if base color/texture might have alpha < 1
 // _output.color.a = alpha; // Use this if base color/texture alpha is always 1.0

 """



func generateRadialAlphaTexture(size: Int = 512) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: UIGraphicsImageRendererFormat.default())
    return renderer.image { ctx in
        let cgCtx = ctx.cgContext
        let colors = [
            UIColor.white.withAlphaComponent(1.0).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ] as CFArray
        let space = CGColorSpaceCreateDeviceRGB() // ✅ RGBA
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        let center = CGPoint(x: size / 2, y: size / 2)
        cgCtx.setBlendMode(.copy)
        cgCtx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center,   endRadius: CGFloat(size / 2),
            options: .drawsAfterEndLocation
        )
    }
}
func centerGeometryPivot(_ node: SCNNode) {
    guard let geo = node.geometry else { return }
    let (min, max) = geo.boundingBox
    // 计算几何体中心
    let center = SCNVector3(
        (min.x + max.x) * 0.5,
        (min.y + max.y) * 0.5,
        (min.z + max.z) * 0.5
    )
    // 把几何体绕它自身中心平移，使得现在的 local-origin 在几何中心
    node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    // 并清除 node 本身的 position，保证它在父节点的原点
    node.position = SCNVector3Zero
}

 // MARK: - Helper Extensions & Functions

 extension UIColor {
     // Simple linear interpolation between two UIColors
     func interpolate(to color: UIColor, fraction: CGFloat) -> UIColor {
         let f = min(max(0, fraction), 1)
         var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
         self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

         var r2: CGFloat
  = 0, g2: CGFloat = 0, b2: CGFloat  = 0, a2: CGFloat = 0
         color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
         let r = r1 + (r2 - r1) * f
         let g = g1 + (g2 - g1) * f
         let b = b1 + (b2 - b1) * f
         let a = a1 + (a2 - a1) * f

         return UIColor(red: r, green: g,  blue: b, alpha: a)
     }

     // Helper to convert UIColor to SCNVector4 for shader uniforms
     var scnVector4: SCNVector4 {
             var r: CGFloat = 0
             var g: CGFloat = 0
             var b: CGFloat = 0

            var a: CGFloat = 0

      self.getRed(&r, green: &g, blue: &b, alpha: &a)
             return SCNVector4(r, g, b, a)
     }
 }

 // NEW Helper function to blend colors (from user request)
 func blendColors(_ color1: UIColor, _ color2: UIColor, t: CGFloat) -> UIColor {
    return color1.interpolate(to: color2, fraction: t)
 }


 // Linear mapping function helper (Unchanged)
 func mapValue(_ value: CGFloat, fromMin: CGFloat, fromMax: CGFloat, toMin: CGFloat, toMax: CGFloat) -> CGFloat {
     if abs(fromMax - fromMin) < 0.0001 { return (toMin + toMax) / 2 }

      let fraction = (value - fromMin) / (fromMax - fromMin)
     return toMin + fraction * (toMax - toMin)
 }

func findFirstGeometryNode(_ node: SCNNode) -> SCNNode? {
    if node.geometry != nil {
        return node
    }
    for child in node.childNodes {
        if let result = findFirstGeometryNode(child) {
            return result
        }
    }
    return nil
}


 // MARK: - Vector & Catmull-Rom Helpers (Unchanged)
 // ... (Vector2D, interpolateCatmullRom,  generateDenseCatmullRomPoints, createPathFromDensePoints remain the same) ...
 struct Vector2D {
     var x: CGFloat;
  var y: CGFloat;
  static func + (l: Vector2D, r: Vector2D) -> Vector2D {
         Vector2D(x: l.x + r.x, y: l.y + r.y)
     }
     static func - (l: Vector2D, r: Vector2D) -> Vector2D {
         Vector2D(x: l.x - r.x, y: l.y - r.y)
     }
     static func * (l: CGFloat, r: Vector2D) -> Vector2D {
         Vector2D(x: l * r.x, y: l * r.y)
     }

     static func * (l:  Vector2D, r: CGFloat) -> Vector2D {
         Vector2D(x: l.x * r, y: l.y * r)
     }
     static prefix func - (v: Vector2D) -> Vector2D {
         Vector2D(x: -v.x, y: -v.y)
     }
     init(x: CGFloat = 0, y: CGFloat = 0) {
         self.x = x;
  self.y = y
     }
     init(_ p: CGPoint) {
         self.x = p.x;
  self.y = p.y
     }
     var cgPoint: CGPoint {
         CGPoint(x: x, y: y)
     }
 }
 func interpolateCatmullRom(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint {
     let t2=t*t
     let t3=t2*t
     let v0=Vector2D(p0)
     let v1=Vector2D(p1)
     let v2=Vector2D(p2)
     let v3=Vector2D(p3)
     let term1=v1
     let term2=0.5*(v2-v0)*t

  let term3=0.5*(2*v0-5*v1+4*v2-v3)*t2
     let term4=0.5*(-v0+3*v1-3*v2+v3)*t3
     return (term1+term2+term3+term4).cgPoint
 }
func generateDenseCatmullRomPoints(controlPoints: [CGPoint], pointsPerSegment:  Int) -> [CGPoint] {
    guard controlPoints.count >= 2 else { return controlPoints }
    guard pointsPerSegment > 0 else { return controlPoints }
    var densePoints: [CGPoint] = []
    let n=controlPoints.count
    for i in 0..<(n-1) {
        let p1=controlPoints[i]
        let p2=controlPoints[i+1]
        let p0=(i>0) ?
        controlPoints[i-1] : p1
        let p3=(i<n-2) ?
        controlPoints[i+2] : p2
        
        if i==0 {
            densePoints.append(p1)
        }
        for j in 1...pointsPerSegment {
            let t=CGFloat(j)/CGFloat(pointsPerSegment)
            densePoints.append(interpolateCatmullRom(p0:p0, p1:p1, p2:p2, p3:p3, t:t))
        }
    }
    if let
        lastControl=controlPoints.last, densePoints.last != lastControl {
        
        if densePoints.isEmpty ||
            (densePoints.last!.x < lastControl.x) ||
            abs(densePoints.last!.y - lastControl.y) > 0.001 {
            densePoints.append(lastControl)
        }
    }
    return densePoints
}
 func createPathFromDensePoints(points: [CGPoint], closePath: Bool, baseLevel: CGFloat) -> UIBezierPath {
     let path=UIBezierPath()
     guard let firstPoint=points.first else { return path }
     if closePath {
         path.move(to: CGPoint(x: firstPoint.x, y: baseLevel))

  path.addLine(to: firstPoint)
     } else {

  path.move(to: firstPoint)
     }
     for i in 1..<points.count {
         path.addLine(to: points[i])
     }
     if closePath, points.count > 1, let lastPoint=points.last {
         path.addLine(to: CGPoint(x: lastPoint.x, y: baseLevel))
         path.close()
     }
     return path
 }


 // MARK: - Day/Night Cycle Definitions
 // ... (TimeOfDayConstants struct with nested structs remains the same, adjusted SunCoreColors) ...
struct TimeOfDayConstants {
    // Time points (0.0 to 1.0)
    static let dawnStartTime: Float  = 0.23
    static let sunriseTime: Float = 0.25 // Sun appears
    static let morningEndTime: Float = 0.35 // Sun becomes fully white / glow fades
    static let middayTime: Float = 0.5
    static let afternoonStartTime: Float = 0.65 // Sun starts tinting / glow appears
    static let sunsetTime: Float = 0.75 // Sun disappears
    static let duskEndTime: Float = 0.77
    
    // Durations
    static let dawnDuration = sunriseTime - dawnStartTime
    static let sunriseTransitionDuration = morningEndTime  - sunriseTime // Duration for sun/glow color transition after sunrise
    static let dayDuration = afternoonStartTime - morningEndTime // Duration of pure white sun / min glow
    static let sunsetTransitionDuration = sunsetTime - afternoonStartTime // Duration for sun/glow color transition before sunset
    static let
    duskDuration = duskEndTime - sunsetTime
    
    struct SkyColors { // Unchanged
        static let nightTop = UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1.0)
        static let nightBottom = UIColor(red: 0.05, green: 0.08, blue:  0.15, alpha: 1.0)
        static let dawnTop = UIColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1.0)
        static let dawnBottom = UIColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 1.0)
        
        static let dayTop = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)
        static let dayBottom = UIColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1.0)
        static let sunsetTop = UIColor(red: 0.2, green: 0.2, blue: 0.5, alpha: 1.0)
        
        static let sunsetBottom = UIColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1.0)
    }
    
    // *** UPDATED: Sun Core Colors based on user request ***
    struct SunCoreColors {
        static let midday =  UIColor(red: 1.0, green: 0.98, blue: 0.95, alpha: 1.0) // White
        static let dawn = UIColor(red: 0.6, green: 0.75, blue: 1.0, alpha: 1.0)  // 更蓝紫
        static let sunset = UIColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 1.0) // 更橙红
    }
    
    
    // *** REMOVED: Old Glow Colors (Glow effect now part of Alto sun complex) ***
    // struct GlowColors { ... }
    
    struct MoonColors { // Unchanged
        
        static let low = UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1.0)
        
        static let high = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1.0)
    }
    
    struct LightColors { // Unchanged (using updated SunCoreColors conceptually for dawn/sunset)
        static let sunDawn = SunCoreColors.dawn // Use new dawn color
        static let sunMorning = UIColor(red: 1.0, green: 0.95, blue: 0.9, alpha: 1.0) // Approaching white
        static let sunMidday = UIColor.white
        static let sunSunset = SunCoreColors.sunset // Use new sunset color
        static let ambientDawn = UIColor(white: 0.3, alpha: 1.0).interpolate(to: sunDawn, fraction: 0.2);
        static let ambientDay = UIColor(white: 0.6, alpha: 1.0)
        static let ambientSunset = UIColor(white: 0.3, alpha: 1.0).interpolate(to: sunSunset, fraction: 0.2);
        static let ambientNight = UIColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 1.0)
        static let moon = UIColor(red: 0.7, green: 0.7, blue: 1.0, alpha: 1.0)
    }
    
    // Intensities (Unchanged)
    static let sunIntensityMax: CGFloat = 1800
    static let sunIntensityDawnSunset: CGFloat = 1000
    static let moonIntensityMax: CGFloat = 250
    static let ambientIntensityDay: CGFloat = 800
    static let ambientIntensityDawnSunset: CGFloat = 500
    static let ambientIntensityNight: CGFloat = 120
    static let  starsIntensityMax: CGFloat = 1.0
    
    // MARK: - Shader Colors & Fog Params (Unchanged)
    struct TerrainShaderParams {
        struct LayerParams {
            let baseColor: UIColor
            let peakColor: UIColor
            let fogColor: UIColor
            
            let minHeight: Float
            let  maxHeight: Float
            let fogStartDistance: Float
            let fogDensity: Float
        }
        
        // Define params for each layer, getting progressively lighter/foggier
        static let midFront = LayerParams(
            
            baseColor: UIColor(red: 0.07, green: 0.18, blue: 0.14, alpha: 1.0),   // 深墨绿
            
            peakColor: UIColor(red: 0.15, green: 0.25, blue: 0.2, alpha: 1.0),    // 稍亮受光色
            fogColor: UIColor(red: 0.5, green: 0.6, blue: 0.6, alpha: 0.2),       // 青绿色薄雾
            minHeight: -50.0,
            
            maxHeight: 150.0,
            fogStartDistance: 80.0,
            
            fogDensity: 0.00001
        )
        
        static let midBack = LayerParams(
            baseColor: UIColor(red: 0.12, green: 0.25, blue: 0.22, alpha: 1.0),   // 稍浅墨绿
            
            peakColor: UIColor(red: 0.2, green: 0.32, blue: 0.28, alpha: 1.0),
            fogColor: UIColor(red: 0.55, green: 0.65, blue: 0.65, alpha: 0.15),
            minHeight: -80.0,
            
            maxHeight: 250.0,
            fogStartDistance: 250.0,
            fogDensity: 0.0001
        )
        
        
        static let background = LayerParams(
            baseColor: UIColor(red: 0.18, green: 0.32, blue: 0.3, alpha: 1.0),    // 蓝绿色调
            peakColor: UIColor(red: 0.28, green: 0.4,  blue: 0.38, alpha: 1.0),
            fogColor: UIColor(red: 0.6, green: 0.7, blue: 0.75, alpha: 0.1),      // 更偏蓝
            
            minHeight: -200.0,
            maxHeight: 500.0,
            fogStartDistance: 450.0,
            fogDensity: 0.0001
        )
        
        static let far = LayerParams(
            baseColor: UIColor(red: 0.25, green: 0.35, blue: 0.38, alpha: 1.0),   // 淡灰青
            
            peakColor: UIColor(red: 0.35, green: 0.45, blue: 0.48, alpha: 1.0),
            fogColor: UIColor(red: 0.75, green: 0.85, blue: 0.95, alpha: 0.05),   // 接近天空色
            minHeight: 0.0,
            
            maxHeight: 1000.0,
            fogStartDistance: 1500.0,
            fogDensity: 0.0001
        )
    }
}


 // MARK: - SwiftUI View Definition

struct ParallaxTerrainSceneView: UIViewRepresentable {
    // MARK: Configuration Constants
    private let dayNightCycleEnabled = true
    private let dayLengthInSeconds: TimeInterval = 120.0
    
    // *** REMOVED Old Sun Textures ***
    // private let sunTextureName = "sun_texture.png"
    // private let sunGlowTextureName = "sun_glow_soft.png"
    
    // NEW: Alto Sun Mesh Names
    private let altoSunCoreMeshName = "sun.obj"       // 3m disk
    private let altoSunHaloMeshName = "sun_halo.obj"    // 4.2m ring
    private let altoSunGlowMeshName = "sun_glow.obj"    // 20m 20-gon
    private let altoSunFlareMeshName = "sun_flare.obj"   // 20m cross
    private let altoSunFlatMeshName = "sun_flat.obj"                     // 90m 16-gon
    private let altoPlaneGlowMeshName = "plane_sun_glow.obj"                // 2000m 20-gon
    private let altoPlaneFlareMeshName = "plane_sun_flare.obj"             // 2000m square
    
    // Textures (Moon remains)
    private let moonTextureName = "moon_texture.png"
    
    //  Speed Control (Unchanged)
    private let baseScrollUnitsPerSecond: CGFloat = 2.0
    private let maxUphillSlopeForSpeed: CGFloat = 0.6
    private let minDownhillSlopeForSpeed: CGFloat = -0.4
    private let minSpeedFactor: CGFloat = 0.4
    private let maxSpeedFactor: CGFloat = 1.2
    
    // Near Terrain Config (Unchanged)
    private let terrainSegmentWidth: CGFloat = 40.0
    private let nearSegmentCount = 5
    private let nearAmplitude: CGFloat = 10.0
    private let nearVerticalOffset: CGFloat = -5.0
    private let nearTerrainMaxDeltaYPerPoint: CGFloat = 3.0
    
    private let pointsPerSegmentSpline = 10
    private let terrainExtrusionDepth: CGFloat = 0.0
    private let nearTerrainZPosition: Float = 4.0
    private let nearTerrainBaseHue: CGFloat = 0.3
    private let nearTerrainHueVariance: CGFloat = 0.05
    private let nearTerrainSaturationRange: ClosedRange<CGFloat> = 0.6...0.8
    private let nearTerrainBrightnessRange: ClosedRange<CGFloat> = 0.6...0.8
    private let controlPointsPerSegmentNear = 5
    
    // Character Config (Unchanged)
    private let characterStickHeight: CGFloat = 1.6
    private let characterStickRadius: CGFloat = 0.2
    private let  fixedCharacterBaseY: Float = -1.0
    private let characterZPosition: Float = 4.0
    
    // Close-Ground Terrain Config (Unchanged)
    private let closeTerrainAmplitude: CGFloat = 8.0
    private let closeTerrainVerticalOffset: CGFloat = -10.0
    private let closeTerrainZPosition: Float = 6.0 // Closest dynamic terrain layer
    private let closeTerrainScrollSpeedFactor: Float = 0.6 // Scrolls at 60% of near speed
    private let closeTerrainExtrusionDepth: CGFloat = 0.0
    private let closeTerrainColor: UIColor
    private let closeTerrainPointsPerSegmentSpline = 6
    private let closeSegmentCount =  8
    
    // *** Mid-Ground Terrain Config (Position/Scale Unchanged) ***
    private let midFrontMeshName = "midMountainFront.obj"
    private let midFrontTerrainZPosition: Float = -600.0   // Behind close terrain
    private let midFrontTerrainYOffset: CGFloat = -200.0  // Adjust vertical position as needed
    private let midFrontMeshScale: Float = 1.0         // Adjust scale as needed
    private let midFrontTerrainScrollSpeedFactor: Float = 0.8 // Scrolls at 50% of near speed // Adjusted speed
    
    private let midBackMeshName = "midMountainBack.obj"
    
    private let midBackTerrainZPosition: Float = -800.0
    // Behind mid-front
    private let midBackTerrainYOffset: CGFloat = -200.0  // Adjust vertical position as needed
    private let midBackMeshScale: Float = 1.0           // Adjust scale as needed
    private let midBackTerrainScrollSpeedFactor: Float = 0.7 // Scrolls at 40% of near speed
    
    private let backgroundMeshName = "midBackground.obj"
    private let backgroundTerrainZPosition: Float = -1000.0 // Behind mid-back
    private let backgroundTerrainYOffset: CGFloat = -400.0  // Adjust vertical position as needed
    private let backgroundMeshScale: Float = 1.0          // Adjust scale as needed
    private let backgroundTerrainScrollSpeedFactor: Float = 0.5 // Scrolls at 30% of near speed
    
    // *** Far Terrain Config (Position/Scale Unchanged) ***
    private let farTerrainMeshName = "largeMountain.obj"
    private let farTerrainYOffset: CGFloat = 0.0 // Adjust vertical position as needed
    private let farTerrainZPosition: Float = -3500.0 // Furthest layer
    private let farTerrainScrollSpeedFactor: Float = 0.0 // Far terrain is static
    private  let farTerrainMeshScale: Float = 1.00 // Adjust scale as needed
    
    // Day/Night Cycle Config (Adjusted for new sun)
    private let trajectoryRadiusX: Float = 100.0
    private let trajectoryRadiusY: Float = 30.0
    private let trajectoryCenterY: Float = -10.0
    private let celestialBodyZ: Float = -30.0
    // REMOVED: sunVisualSize, sunGlowSizeMultiplier (Sizes now defined by meshes)
    // private let sunVisualSize: CGFloat = 15.0
    // private let sunGlowSizeMultiplier: CGFloat = 2.5
    
    private let moonVisualSize: CGFloat = 3.0
    private let sunSetScaleFactor: Float = 1.15 // Keep for potential scaling of whole sun complex at horizon? Or remove if meshes handle it. Keeping for now.
    
    init() {
        
        self.closeTerrainColor = UIColor(hue: nearTerrainBaseHue + 0.02, saturation: 0.5, brightness: 0.5, alpha: 0.9)
        // ... (Sanity checks remain the same for near terrain) ...
        let dx = terrainSegmentWidth / CGFloat(controlPointsPerSegmentNear > 1 ?
                                               controlPointsPerSegmentNear - 1 : 1);
        if nearTerrainMaxDeltaYPerPoint < 0 {
            print("WARN: nearTerrainMaxDeltaYPerPoint < 0")
        } else if dx > 0 && (nearTerrainMaxDeltaYPerPoint / dx) > 2.0 {
            print("WARN: nearTerrainMaxDeltaYPerPoint may cause steep slopes")
        }
        if maxUphillSlopeForSpeed <= 0 {
            print("WARN: maxUphillSlopeForSpeed <= 0")
        }
        if minDownhillSlopeForSpeed >= 0 {
            print("WARN: minDownhillSlopeForSpeed >= 0")
        }
        if minSpeedFactor < 0 ||
            minSpeedFactor > 1 {
            print("WARN: minSpeedFactor invalid")
        }
        if maxSpeedFactor < 1 {
            print("WARN: maxSpeedFactor < 1")
        }
    }
    
    // MARK: - UIViewRepresentable Methods
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            // Core Params
            dayNightCycleEnabled: dayNightCycleEnabled,
            dayLengthInSeconds: dayLengthInSeconds,
            baseScrollUnitsPerSecond: baseScrollUnitsPerSecond,
            maxUphillSlopeForSpeed: maxUphillSlopeForSpeed,
            minDownhillSlopeForSpeed: minDownhillSlopeForSpeed,
            minSpeedFactor: minSpeedFactor,
            
            maxSpeedFactor: maxSpeedFactor,
            
            // Near Terrain
            terrainSegmentWidth: terrainSegmentWidth,
            nearSegmentCount: nearSegmentCount,
            nearAmplitude: nearAmplitude,
            nearVerticalOffset: nearVerticalOffset,
            nearTerrainMaxDeltaYPerPoint:
                nearTerrainMaxDeltaYPerPoint,
            nearPointsPerSegmentSpline: pointsPerSegmentSpline,
            nearExtrusionDepth: terrainExtrusionDepth,
            
            nearTerrainZPosition: nearTerrainZPosition,
            nearTerrainBaseHue: nearTerrainBaseHue,
            nearTerrainHueVariance: nearTerrainHueVariance,
            nearTerrainSaturationRange: nearTerrainSaturationRange,
            nearTerrainBrightnessRange:
                nearTerrainBrightnessRange,
            controlPointsPerSegmentNear: controlPointsPerSegmentNear,
            // Close Terrain
            
            closeSegmentCount: closeSegmentCount,
            closeAmplitude: closeTerrainAmplitude,
            closeVerticalOffset: closeTerrainVerticalOffset,
            closePointsPerSegmentSpline: closeTerrainPointsPerSegmentSpline,
            
            closeExtrusionDepth: 0.0,
            closeTerrainZPosition: closeTerrainZPosition,
            closeTerrainColor: closeTerrainColor,
            closeTerrainScrollSpeedFactor: closeTerrainScrollSpeedFactor,
            
            // *** Mid-Ground Terrain ***
            midFrontMeshName: midFrontMeshName,
            midFrontTerrainZPosition: midFrontTerrainZPosition,
            
            midFrontTerrainYOffset: midFrontTerrainYOffset,
            midFrontMeshScale: midFrontMeshScale,
            midFrontTerrainScrollSpeedFactor: midFrontTerrainScrollSpeedFactor,
            midBackMeshName: midBackMeshName,
            
            midBackTerrainZPosition: midBackTerrainZPosition,
            midBackTerrainYOffset: midBackTerrainYOffset,
            midBackMeshScale: midBackMeshScale,
            
            midBackTerrainScrollSpeedFactor: midBackTerrainScrollSpeedFactor,
            backgroundMeshName: backgroundMeshName,
            backgroundTerrainZPosition: backgroundTerrainZPosition,
            backgroundTerrainYOffset: backgroundTerrainYOffset,
            backgroundMeshScale: backgroundMeshScale,
            
            backgroundTerrainScrollSpeedFactor: backgroundTerrainScrollSpeedFactor,
            // Far Terrain
            
            farTerrainMeshName: farTerrainMeshName,
            farTerrainYOffset: farTerrainYOffset,
            farTerrainZPosition: farTerrainZPosition,
            farTerrainScrollSpeedFactor: farTerrainScrollSpeedFactor,
            farTerrainMeshScale: farTerrainMeshScale,
            // Character
            
            fixedCharacterBaseY: fixedCharacterBaseY,
            
            characterZPosition: characterZPosition,
            // Day/Night
            trajectoryRadiusX: trajectoryRadiusX,
            trajectoryRadiusY: trajectoryRadiusY,
            trajectoryCenterY: trajectoryCenterY,
            
            celestialBodyZ: celestialBodyZ,
            
            // Alto Sun Meshes
            altoSunCoreMeshName: altoSunCoreMeshName,
            altoSunHaloMeshName: altoSunHaloMeshName,
            altoSunGlowMeshName: altoSunGlowMeshName,
            altoSunFlareMeshName: altoSunFlareMeshName,
            altoSunFlatMeshName: altoSunFlatMeshName,
            altoPlaneGlowMeshName: altoPlaneGlowMeshName,
            altoPlaneFlareMeshName: altoPlaneFlareMeshName,
            
            // Other Celestial
            
            moonVisualSize: moonVisualSize,
            sunSetScaleFactor: sunSetScaleFactor, // Keep for potential sun complex scaling
            // sunTextureName: sunTextureName, // Removed
            moonTextureName: moonTextureName
            // sunGlowTextureName: sunGlowTextureName, // Removed
            // sunGlowSizeMultiplier: sunGlowSizeMultiplier // Removed
            
            
        )
    }
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = ObservingSCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.autoenablesDefaultLighting = false // Use custom lights only
        scnView.rendersContinuously = true
        scnView.delegate = context.coordinator
        
        scnView.onLayout = {
                let width = scnView.bounds.width
                let height = scnView.bounds.height
                if height > 0 {
                    let aspect = Float(width / height)
                    context.coordinator.aspectRatio = aspect
                }
            }
        
        let scene = SCNScene()
        
        scnView.scene = scene
        
        context.coordinator.scene = scene
        context.coordinator.setupInitialSceneElements()
        // 保存 scnView 给 Coordinator 用
        context.coordinator.scnView = scnView
        // *** Setup Static Background Layers ***
        setupStaticMidTerrainMeshes(scene: scene, coordinator: context.coordinator) // Calls helper with shader setup
        setupStaticFarTerrainMesh(scene: scene, coordinator: context.coordinator)   // Calls helper with shader setup
        
        // Setup Dynamic Foreground Layers
        
        context.coordinator.setupDynamicTerrainsAndCharacter()
        
        // Setup Camera
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        // Increase zFar significantly to see the far terrain and large sun elements
        //cameraNode.camera?.zFar = Double(abs(farTerrainZPosition)) * 2.0 // Ensure far terrain is visible
        // Adjust zFar further if needed for the 2000m sun elements
        //cameraNode.camera?.zFar = max(cameraNode.camera?.zFar ?? 0, Double(abs(celestialBodyZ)) + 3500.0) // Make sure very large sun elements are visible
        cameraNode.camera?.zNear = 1
        cameraNode.camera?.zFar = 10000
        cameraNode.camera?.usesOrthographicProjection=false
        
        cameraNode.position = SCNVector3(0, 5, 20)
        cameraNode.eulerAngles = SCNVector3(-Float.pi/18, 0,0)
        scene.rootNode.addChildNode(cameraNode)
        
        // Initial Day/Night Update
        context.coordinator.updateDayNightCycle(deltaTime: 0)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
    } // Unchanged
    
    
    // MARK: - Helper Functions (Static parts)
    
    // *** NEW: Setup for Static Mid-Ground Terrain MESHES ***
    
    func setupStaticMidTerrainMeshes(scene: SCNScene, coordinator: Coordinator) {
        // Layer 1: Mid-Front
        setupSingleStaticMeshLayer(
            scene: scene,
            coordinator: coordinator,
            
            meshName: coordinator.midFrontMeshName,
            yOffset: coordinator.midFrontTerrainYOffset,
            
            zPosition: coordinator.midFrontTerrainZPosition,
            scale: coordinator.midFrontMeshScale,
            nodeName: "MidFrontTerrain",
            parentRef: &coordinator.midFrontTerrainParent,
            meshRef: &coordinator.midFrontMeshNode, // Storing one reference is enough for updates
            meshWidthRef: &coordinator.midFrontMeshWidth, // Store width for scrolling
            shaderParams: TimeOfDayConstants.TerrainShaderParams.midFront
            // Pass shader params
        )
        
        // Layer 2: Mid-Back
        setupSingleStaticMeshLayer(
            scene: scene,
            coordinator: coordinator,
            meshName: coordinator.midBackMeshName,
            yOffset: coordinator.midBackTerrainYOffset,
            
            zPosition: coordinator.midBackTerrainZPosition,
            
            scale: coordinator.midBackMeshScale,
            nodeName: "MidBackTerrain",
            parentRef: &coordinator.midBackTerrainParent,
            meshRef: &coordinator.midBackMeshNode,
            meshWidthRef: &coordinator.midBackMeshWidth, // Store width for scrolling
            shaderParams: TimeOfDayConstants.TerrainShaderParams.midBack // Pass shader params
            
        )
        
        // Layer 3: Background
        setupSingleStaticMeshLayer(
            
            scene: scene,
            coordinator: coordinator,
            meshName: coordinator.backgroundMeshName,
            yOffset: coordinator.backgroundTerrainYOffset,
            
            zPosition: coordinator.backgroundTerrainZPosition,
            scale: coordinator.backgroundMeshScale,
            nodeName: "BackgroundTerrain",
            parentRef: &coordinator.backgroundTerrainParent,
            
            meshRef: &coordinator.backgroundMeshNode,
            meshWidthRef: &coordinator.backgroundMeshWidth, // Store width for scrolling
            shaderParams: TimeOfDayConstants.TerrainShaderParams.background // Pass shader params
            
        )
    }
    
    // *** MODIFIED: Setup for Static Far Terrain MESH (calls helper) ***
    // Far terrain doesn't need infinite scroll, so widthRef is not needed.
    func setupStaticFarTerrainMesh(scene: SCNScene, coordinator: Coordinator) {
        var dummyWidth: Float = 0 // Not used for far terrain
        setupSingleStaticMeshLayer(
            scene: scene,
            coordinator: coordinator,
            
            meshName: coordinator.farTerrainMeshName,
            yOffset: coordinator.farTerrainYOffset,
            
            zPosition: coordinator.farTerrainZPosition,
            scale: coordinator.farTerrainMeshScale,
            nodeName: "FarTerrain", // Updated name slightly
            parentRef: &coordinator.farTerrainParent,
            meshRef: &coordinator.farTerrainMeshNode,
            meshWidthRef: &dummyWidth, // Pass dummy ref, it won't be used
            shaderParams: TimeOfDayConstants.TerrainShaderParams.far // Pass shader params
        )
    }
    
    // *** UPDATED HELPER: Sets up a single static mesh layer WITH SHADER and DUPLICATION for infinite scroll ***
    private func setupSingleStaticMeshLayer(
        scene: SCNScene,
        coordinator: Coordinator,
        meshName: String,
        yOffset: CGFloat,
        
        zPosition: Float,
        
        scale: Float,
        nodeName: String,
        parentRef: inout SCNNode?,         // Use inout for assignment
        meshRef: inout SCNNode?,         // Use inout for assignment
        meshWidthRef: inout Float,
        // Use inout to store mesh width
        shaderParams: TimeOfDayConstants.TerrainShaderParams.LayerParams // Shader params
    ) {
        guard let baseMeshNode = loadMeshNode(meshName: meshName, scaleToUnit: false) else { // Don't force scale here, apply later
            print("Error: \(nodeName) mesh '\(meshName)' could  not be loaded.")
            return
        }
        
        
        // --- Determine Mesh Width ---
        // Calculate the bounding box to get the width for seamless scrolling
        // Note: Bounding box is in the mesh's local coordinates before scaling.
        let (minBounds, maxBounds) = baseMeshNode.boundingBox
        let meshWidth = (maxBounds.x - minBounds.x) // Width along the X-axis
        meshWidthRef = meshWidth // Store the raw width in the coordinator
        
        let scaledMeshWidth = meshWidth * scale // Width after scaling
        
        
        // Apply Material WITH SHADER
        let material = SCNMaterial()
        
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        material.blendMode = .replace   // 确保是完全不透明
        
        material.lightingModel = .constant // Use constant for shader control
        material.isDoubleSided = false
        material.ambient.contents = UIColor.black // Base ambient
        material.locksAmbientWithDiffuse  = false
        material.diffuse.contents = UIColor.white // Base diffuse color before shader modifies _surface.diffuse
        // --- Set Shader Modifier ---
        let shaderModifiers = [SCNShaderModifierEntryPoint.surface: terrainShaderModifier]
        material.shaderModifiers = shaderModifiers
        
        // --- Set Shader Uniform Values ---
        let worldMin = shaderParams.minHeight * scale + Float(yOffset) // Apply scale to height params
        let worldMax = shaderParams.maxHeight * scale + Float(yOffset) // Apply scale to height params
        material.setValue(NSNumber(value: worldMin), forKey: "u_minHeight")
        
        material.setValue(NSNumber(value: worldMax), forKey: "u_maxHeight")
        material.setValue(NSNumber(value: shaderParams.fogStartDistance), forKey: "u_fogStartDistance")
        
        material.setValue(NSNumber(value: shaderParams.fogDensity), forKey: "u_fogDensity")
        material.setValue(NSValue(scnVector4: shaderParams.baseColor.scnVector4), forKey: "u_baseColor")
        material.setValue(NSValue(scnVector4: shaderParams.peakColor.scnVector4), forKey: "u_peakColor")
        material.setValue(NSValue(scnVector4: shaderParams.fogColor.scnVector4), forKey: "u_fogColor")
        material.setValue(NSNumber(value: Float(0.0)), forKey: "u_timeOfDay")
        
        let coldTint = UIColor(red: 0.6, green: 0.75, blue: 0.9, alpha: 1.0)
        let warmTint = UIColor(red: 1.0, green: 0.8, blue: 0.6,
                               alpha: 1.0)
        material.setValue(NSValue(scnVector4: coldTint.scnVector4), forKey: "u_coldTintColor")
        material.setValue(NSValue(scnVector4: warmTint.scnVector4), forKey: "u_warmTintColor")
        material.setValue(NSValue(scnVector4: UIColor.black.scnVector4), forKey: "u_ambientColor") // Initialize ambient uniform
        
        // Apply material recursively (important!)
        applyMaterialRecursively(to: baseMeshNode,  material: material)
        
        // --- Configure Nodes for Infinite Scrolling ---
        baseMeshNode.name = "\(nodeName)Mesh_0" // Specific name for the first mesh part
        baseMeshNode.position = SCNVector3(0, Float(yOffset), 0) // Position first instance
        baseMeshNode.scale = SCNVector3(scale, scale, scale) // Apply final scale
        baseMeshNode.castsShadow = false
        
        // Create and configure the second instance for seamless looping
        let secondMeshNode = baseMeshNode.clone() // Clone the first node with its geometry and material
        
        secondMeshNode.name = "\(nodeName)Mesh_1"
        // Position the second instance immediately to the right of the first one
        secondMeshNode.position = SCNVector3(scaledMeshWidth, Float(yOffset), 0) // Position uses scaled width
        secondMeshNode.scale = SCNVector3(scale, scale, scale) // Ensure scale is also set
        secondMeshNode.castsShadow = false
        
        
        // Setup Parent Node for Scrolling & Z-Positioning
        
        let parent  = SCNNode()
        parent.name = "\(nodeName)Parent"
        parent.position = SCNVector3(0, 0, zPosition)
        parent.addChildNode(baseMeshNode)      // Add the first instance
        // Add second instance ONLY if it's one of the mid-ground layers needing scroll
        if nodeName != "FarTerrain" && scaledMeshWidth > 0.001 { // Use scaled width and tolerance
            
            parent.addChildNode(secondMeshNode)  // Add the second instance for looping
        }
        scene.rootNode.addChildNode(parent)
        
        // Store references in coordinator using inout parameters
        parentRef = parent
        meshRef = baseMeshNode // Store reference to one of the meshes for uniform updates
        
        print("Setup \(nodeName) with width \(meshWidth) (scaled: \(scaledMeshWidth)). Infinite scroll setup: \(nodeName != "FarTerrain" && scaledMeshWidth > 0.001)")
    }
    
    // *** HELPER: Applies material recursively *** (Unchanged)
    
    private func applyMaterialRecursively(to node: SCNNode, material: SCNMaterial) {
        if let geometry = node.geometry {
            var materials = [SCNMaterial]()
            let materialCount = max(1, geometry.elementCount) // Ensure at least one material slot
            for _ in 0..<materialCount {
                materials.append(material.copy() as!
                                 SCNMaterial) // Use copies to avoid sharing state issues
            }
            
            geometry.materials = materials
        }
        for child in node.childNodes {
            applyMaterialRecursively(to: child, material: material)
        }
    }
    
    // *** CORRECTED: Helper to Load Mesh Node  *** (Updated to handle potential scaling needed for meshes)
    func loadMeshNode(meshName: String, scaleToUnit: Bool = true) -> SCNNode? { // Added scaleToUnit flag
        // Try loading from Assets first
        if let scene = SCNScene(named: meshName) {
            let node = SCNNode()
            var foundNodes = false
            for child in scene.rootNode.childNodes {
                node.addChildNode(child.clone()) // Clone to avoid modifying the original asset
                
                foundNodes = true
            }
            if foundNodes {
                print("Loaded mesh '\(meshName)' from scene assets.")
                if scaleToUnit { node.scale = SCNVector3(0.01, 0.01, 0.01) } // Example scale if needed
                return node
                
            } else {
                
                print("Warning: Loaded scene '\(meshName)' but found no child nodes.")
            }
        } else {
            print("Info: Mesh '\(meshName)' not found in scene assets. Trying direct URL.")
        }
        
        
        // Fallback: Try loading directly via URL
        guard let url = Bundle.main.url(forResource:  meshName, withExtension: nil) ?? Bundle.main.url(forResource: meshName.replacingOccurrences(of: ".obj", with: ""), withExtension: "obj") else {
            print("Error: Could not find mesh file URL for '\(meshName)' in bundle.")
            
            return nil
        }
        
        // --- Corrected Mesh Loading using Model I/O ---
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Error: Metal device  not available.")
            return nil
        }
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        
        // Create a vertex descriptor suitable for SceneKit rendering (position, normal, texcoord)
        // This ensures the _geometry struct in the shader has the expected attributes.
        let vertexDescriptor = MDLVertexDescriptor()
        // Specify attributes SceneKit expects. Adjust if your OBJ has different names.
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0) // Assuming packed floats
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0) // Assuming packed
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 32) // Adjust stride based on actual vertex data size (pos(12)+norm(12)+uv(8)=32)
        
        
        // Load the asset
        
        let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        // --- End Correction ---
        
        // Find the first MDLMesh in the asset
        var loadedMesh: MDLMesh?
        for i in 0..<asset.count {
            if let mesh = asset.object(at: i) as?
                MDLMesh {
                // Recalculate normals if they might be missing (common with OBJ)
                // Do this *before* creating the SCNGeometry
                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    print("Info: Adding normals to mesh '\(meshName)'")
                    
                    mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.02)
                }
                // Ensure vertex descriptor matches SceneKit's expectations, especially after adding normals
                
                mesh.vertexDescriptor = vertexDescriptor // Re-assign descriptor after potential modifications
                
                loadedMesh = mesh
                
                print("Found MDLMesh at index \(i) in '\(meshName)'")
                
                break
            }
        }
        
        guard let mesh = loadedMesh else {
            print("Error: No MDLMesh found in asset '\(meshName)'")
            return nil
        }
        
        
        // Create SceneKit geometry and node
        do {
            // Create geometry from the potentially modified MDLMesh
            let geometry = try SCNGeometry(mdlMesh: mesh)
            let node = SCNNode(geometry: geometry)
            
            // Optional Scaling: If meshes aren't 1 unit = 1 meter, scale here.
            // Example: If OBJ units are cm, scale by 0.01. Set scaleToUnit = false if using explicit SCNNode scaling later.
            if scaleToUnit {
                node.scale = SCNVector3(0.01, 0.01, 0.01) // Adjust as needed
            }
            print("Successfully created SCNNode for  mesh '\(meshName)'.")
            return node
        } catch {
            print("Error creating SCNGeometry from MDLMesh for '\(meshName)': \(error)")
            return nil
        }
    }
    
    /// Utility to load and prepare a mesh node from asset or .obj file
    func loadMeshNode(named name: String, scaleToUnitDiameter diameter: CGFloat) -> SCNNode? {
        guard let scene = SCNScene(named: name) else { return nil }
        let parent = SCNNode()
        for child in scene.rootNode.childNodes {
            let copy = child.clone()
            parent.addChildNode(copy)
            // Scale to match desired diameter
            let (min, max) = copy.boundingBox
            let size = max.x - min.x
            if size > 0 {
                let factor = Float(diameter) / size
                copy.scale = SCNVector3(factor, factor, factor)
            }
        }
        return parent
    }

    
    
    // --- REMOVED: createStaticFarTerrainNode --- (Functionality moved to setupSingleStaticMeshLayer)
    
    // Unchanged generateGradientImage
    func generateGradientImage(size: CGSize, topColor: UIColor, bottomColor: UIColor)  -> UIImage?
    {
        let r=UIGraphicsImageRenderer(size:size)
        return r.image { ctx in let c = [topColor.cgColor, bottomColor.cgColor] as CFArray
            guard let sp = CGColorSpace(name: CGColorSpace.sRGB), let gr = CGGradient(colorsSpace: sp, colors: c, locations: [0, 1])
            else {
                return
                
            }
            
            ctx.cgContext.drawLinearGradient(gr, start: CGPoint(x:size.width/2, y:0), end: CGPoint(x:size.width/2, y:size.height), options:[])
        }
    }
    
    
    // --- REMOVED Old Sun/Glow Creation Functions ---
    // func createSunNode(...) { ... }
    // func createSunGlowNode(...) { ... }
    // Helper to scale node to a target diameter
    private func scaleNodeToDiameter(_ node: SCNNode, diameter: Float) {
        let (min, max) = node.boundingBox
        let currentSize = max.x - min.x // Assuming diameter is primarily along X for flat objects
        if currentSize > 0.001 {
            let scaleFactor = diameter / currentSize
            node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
            print("Scaled node \(node.name ?? "<?>") from diameter \(currentSize) to \(diameter) (scale: \(scaleFactor))")
        } else {
            print("Warning: Could not determine size for node \(node.name ?? "<?>"), cannot scale.")
        }
    }
    
    
    
    // +++ NEW: Create Alto's Adventure Sun Complex +++
    func createAltoSunNode(
        coreMeshName: String, haloMeshName: String, glowMeshName: String, flareMeshName: String,
        flatMeshName: String, planeGlowMeshName: String, planeFlareMeshName: String
    ) -> SCNNode? {
        let parentSunNode = SCNNode()
        parentSunNode.name = "AltoSunComplex"
        parentSunNode.constraints = [SCNBillboardConstraint()] // Make the whole complex face the camera
        
        // --- 1. Sun Core (Background_Shared_Sun.obj) ---
        if let rootNode = loadMeshNode(meshName: coreMeshName, scaleToUnit: false),
           let geometryNode = findFirstGeometryNode(rootNode) {
            geometryNode.name = "SunCore"
            scaleNodeToDiameter(geometryNode, diameter: 3.0)
            centerGeometryPivot(geometryNode)
            // Create material
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = false
            material.blendMode = .replace // 保守且稳定，确保贴图可见

            // Set core texture
            material.diffuse.contents = UIImage(named: "sun_core.png")
            
            // Set default uniform values
            material.setValue(SCNVector4(1, 1, 1, 1), forKey: "u_color")
            // Attach surface shader modifier
            //material.shaderModifiers = [SCNShaderModifierEntryPoint.surface: sunCoreSurfaceModifier]
            geometryNode.renderingOrder = -500
            // Apply materialå
            // Configure rendering order and depth
            material.writesToDepthBuffer = true
            material.readsFromDepthBuffer = true
            geometryNode.geometry?.materials = [material]
            
           
            
            geometryNode.scale.z = -1
            geometryNode.position = SCNVector3(0, 0, 0)
            parentSunNode.addChildNode(geometryNode)
        } else {
            print("❌ 加载失败或未找到 geometry 节点")
            return nil
        }
        
        
//        if let rootNode = loadMeshNode(meshName: coreMeshName, scaleToUnit: false),
//                  let geometryNode = findFirstGeometryNode(rootNode) {
//                   geometryNode.name = "SunCore"
//                   // You might want to scale the geometry node if the OBJ isn't the right size
//                   // scaleNodeToDiameter(geometryNode, diameter: 3.0) // Example scaling
//
//                   // --- Create and Configure Material for Glow Shader ---
//                   let material = SCNMaterial()
//                   //
//                   material.lightingModel = .constant // Use constant as shader sets emission directly
//                   //
//                   material.isDoubleSided = true // Match Unity's Cull Off
//                   //
//                   material.blendMode = .add // Additive blending often looks good for sun glow
//                                             // Use .alpha if you need standard transparency based on textures
//                   material.writesToDepthBuffer = false // Match Unity's ZWrite Off
//
//                   // Assign textures (REPLACE "soft.png" and "SharedFlare.png" with your actual texture assets)
//                   // u_mainTex: Defines the base shape/gradient of the sun core
//                   if let mainTex = UIImage(named: "soft.png") { // Example: A soft white circle texture
//                       material.setValue(mainTex, forKey: "u_mainTex")
//                   } else {
//                       print("Warning: Sun core texture 'soft.png' not found.")
//                       material.setValue(UIColor.white, forKey: "u_mainTex") // Fallback to white color
//                   }
//                   // u_glowTex: Defines the shape/mask of the glow/flare overlay
//                   if let glowTex = UIImage(named: "SharedFlare.png") { // Example: A flare/starburst texture
//                       material.setValue(glowTex, forKey: "u_glowTex")
//                   } else {
//                       print("Warning: Sun glow texture 'SharedFlare.png' not found.")
//                       material.setValue(UIColor.clear, forKey: "u_glowTex") // Fallback to clear (no glow mask)
//                   }
//
//                   //
//                   // Set INITIAL uniform values (These will be updated dynamically)
//                   // u_color: Initial tint (e.g., white)
//                   material.setValue(SCNVector4(0, 1, 0, 1), forKey: "u_color")
//                   // u_glowColor: Initial glow color (e.g., warm yellow/orange)
//                   material.setValue(SCNVector4(1.0, 0.8, 0.6, 1.0), forKey: "u_glowColor")
//                   // u_glowScale: Initial glow intensity
//                   material.setValue(Float(1.0), forKey: "u_glowScale") // IMPORTANT: Pass Float for single float uniforms
//
//                   // Attach surface shader modifier
//                   //
//                   material.shaderModifiers = [SCNShaderModifierEntryPoint.surface: sunGlowSurfaceModifier]
//
//                   // Apply material
//                   geometryNode.geometry?.materials = [material]
//
//                   // Configure rendering order and depth
//                   //
//                   geometryNode.renderingOrder = 100 // Render sun core relatively late among transparent objects
//                   // material.writesToDepthBuffer = false // Already set above
//
//                   //
//                   geometryNode.position = SCNVector3(0, 0, 0) // Core is at the center of the complex
//                   parentSunNode.addChildNode(geometryNode)
//               } else {
//                   //
//                   print("❌ Failed to load SunCore mesh ('\(coreMeshName)') or find its geometry node.")
//                   return nil // Failed to create essential part
//               }
        
        
        
//        // --- 2. Sun Halo (Background_Shared_Sun_Halo.obj) ---
//        if let haloNode = loadMeshNode(meshName: haloMeshName, scaleToUnit: false),
//            let geometryNode=findFirstGeometryNode(haloNode){// Assuming 4.2m ring
//            scaleNodeToDiameter(geometryNode, diameter: 4.2) // Scale to 4.2m
//            let material = SCNMaterial()
//            material.lightingModel = .constant
//            material.diffuse.contents = UIColor.white // Base color before shader alpha
//            material.writesToDepthBuffer = false
//            material.isDoubleSided = false
//            material.blendMode = .alpha // Needs alpha blending for feathering
//            // *** APPLY SHADER MODIFIER for Feathered Alpha ***
//            let modifiers = [SCNShaderModifierEntryPoint.fragment: haloShaderModifier]
//            material.shaderModifiers = modifiers
//            // *** END SHADER APPLICATION ***
//            geometryNode.geometry?.materials = [material]
//            // 检查赋值是否生效
//            if let materials = geometryNode.geometry?.materials, materials.contains(material) {
//                print("✅ 材料赋值成功，共 \(materials.count) 个材质。")
//            } else {
//                print("❌ 材料赋值失败！")
//            }
//            geometryNode.name = "SunHalo"
//            geometryNode.renderingOrder = 15 // Render after core
//            geometryNode.position = SCNVector3(0, 0, 0.01) // Slightly in front of core
//            parentSunNode.addChildNode(geometryNode)
//        } else { print("Error loading: \(haloMeshName)") } // Continue if optional elements fail
        
         // --- 3. Sun Glow (Background_Shared_Sun_Glow.obj) ---
//        if let glowNode = loadMeshNode(meshName: glowMeshName, scaleToUnit: false),
//           let geometryNode = findFirstGeometryNode(glowNode) {
//            geometryNode.name = "SunGlow"
//            // 20m 二十边形，确保尺寸
//            scaleNodeToDiameter(geometryNode, diameter: 20.0)
//            centerGeometryPivot(geometryNode)
//            // 创建材质
//            let mat = SCNMaterial()
//            mat.lightingModel = .constant
//            mat.isDoubleSided = true
//            mat.blendMode = .add     // 加色混合，增强发光
//            mat.writesToDepthBuffer = false
//            
//            // 赋贴图：主贴图可以用纯白，发光遮罩用径向 alpha
//            // u_mainTex:
//            let transparentWhite = UIImage.transparentWhite1x1()
//            mat.setValue(transparentWhite, forKey: "u_mainTex")
//            // u_glowTex:
//            mat.setValue(generateRadialAlphaTexture(size: 512), forKey: "u_glowTex")
//         
//            // 初始 uniform
//            mat.setValue(NSValue(scnVector4: UIColor.white.scnVector4), forKey: "u_color")
//            mat.setValue(NSValue(scnVector4: TimeOfDayConstants.SunCoreColors.midday.scnVector4), forKey: "u_glowColor")
//            mat.setValue(Float(1.0), forKey: "u_glowScale")
//            
//            // 应用你之前定义的 Surface Shader Modifier
//            mat.shaderModifiers = [ .surface : sunGlowSurfaceModifier ]
//            
//            // 赋给几何体
//            geometryNode.geometry?.materials = [mat]
//            geometryNode.renderingOrder = 20
//            parentSunNode.addChildNode(geometryNode)
//        } else { print("Error loading: \(haloMeshName)") } // Continue if optional elements fail
        
        
        // --- 4. Flare Quad ---
//        if let flareNode = loadMeshNode(meshName: flareMeshName, scaleToUnit: false),
//           let geometryNode = findFirstGeometryNode(flareNode) {
//            geometryNode.name = "SunFlare"
//            scaleNodeToDiameter(geometryNode, diameter: 20.0)
//            centerGeometryPivot(geometryNode)
//            // --- 2. Material with Metal shader modifier ---
//            let material = SCNMaterial()
//            material.isDoubleSided = true
//            material.blendMode = .add        // Additive blending
//            material.writesToDepthBuffer = false
//            material.lightingModel = .constant
//            
//            if let flareImage = UIImage(named: "sun_flare.png") {
//                let flareTex = SCNMaterialProperty(contents: flareImage)
//                material.setValue(flareTex, forKey: "_FlareTex")
//            }
//            let fragmentSunPlaneModifier = """
//                            #pragma arguments
//                            float4 _SunColor;
//                            texture2d<float> _FlareTex;
//
//                            #pragma body
//                            // ① 清空上一帧留下的颜色
//                            _output.color = float4(0.0);
//
//                            // ② 采样 UV
//                            float2 uv = _surface.diffuseTexcoord;
//                            constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
//                            float4 tex = _FlareTex.sample(texSampler, uv);
//
//                            // ③ 径向渐隐  
//                            float2 cent = uv - float2(0.5, 0.5);
//                            float dist = length(cent) / 0.7071;
//                            float mask = saturate(1.0 - dist);
//
//                            // ④ 颜色和 alpha  
//                            float3 rgb = tex.rgb * _SunColor.rgb * mask;
//                            float  a   = tex.a * _SunColor.a * mask;
//
//                            // ⑤ 输出  
//                            _output.color = float4(rgb, a);
//                            """
//            material.shaderModifiers = [.fragment: fragmentSunPlaneModifier]
//            
//            geometryNode.geometry?.firstMaterial = material
//            geometryNode.renderingOrder = 15
//            parentSunNode.addChildNode(geometryNode)
//        }
        
//        // --- 5. Sun Flat (SunFlat.obj) ---
//        if let flatNode = loadMeshNode(meshName: flatMeshName, scaleToUnit: false) { // Assuming 90m 16-gon
//            let material = SCNMaterial()
//            material.lightingModel = .constant
//            // Use texture/vertex color/simple color
//            material.diffuse.contents = UIColor(white: 1.0, alpha: 0.5) // Placeholder - semi-transparent white
//            material.emission.contents = UIColor(white: 1.0, alpha: 0.5)
//            material.emission.intensity = 0.4
//            material.writesToDepthBuffer = false
//            material.isDoubleSided = false
//            material.blendMode = .add // Or .alpha if layering over glow distinctly
//            flatNode.geometry?.materials = [material]
//            flatNode.name = "SunFlat"
//            flatNode.renderingOrder = 5 // Render behind core/halo/glow? Or 25 to layer over glow? Adjust as needed.
//            flatNode.position = SCNVector3(0, 0, 0.04)
//            parentSunNode.addChildNode(flatNode)
//        } else { print("Error loading: \(flatMeshName)") }
//        
//        // --- 6. Plane Sun Glow (planeSunGlow.obj) ---
//            if let pGlow = loadMeshNode(meshName: planeGlowMeshName, scaleToUnit: false),
//               let geometryNode = findFirstGeometryNode(pGlow) {
//                scaleNodeToDiameter(geometryNode, diameter: 2000.0)
//                centerGeometryPivot(geometryNode)
//               // loadMeshNode(named: planeGlowMeshName, scaleToUnitDiameter: 2000.0) {
//                geometryNode.name = "PlaneSunGlow"
//                let mat = SCNMaterial()
//                mat.lightingModel = .constant
//                mat.isDoubleSided = true
//                mat.blendMode = .add
//                mat.writesToDepthBuffer = false
//
//                // Custom radial alpha shader
//                let glowShader = """
//                #pragma arguments
//                float4 u_glowColor;
//                float u_glowScale;
//
//                #pragma body
//                float3 pos = _surface.position.xyz;
//                float dist = length(pos.xy);          // 假设是圆盘，XY 平面展开
//                float fade = clamp(1.0 - dist / 1000.0, 0.0, 1.0); // 半径 1000m → 渐隐边缘
//                float glowAlpha = pow(fade, 2.0) * u_glowScale;
//                float4 color = u_glowColor * glowAlpha;
//
//                _surface.diffuse = color;
//                _surface.emission = color;
//                _surface.transparent = glowAlpha;
//                """
//                mat.shaderModifiers = [.surface: glowShader]
//                mat.setValue(NSValue(scnVector4: UIColor.white.scnVector4), forKey: "u_glowColor")
//                mat.setValue(Float(1.0), forKey: "u_glowScale")
//
//                geometryNode.geometry?.materials = [mat]
//                geometryNode.renderingOrder = 5
//                parentSunNode.addChildNode(geometryNode)
//                
//            }

//        // --- 7. Plane Sun Flare (PlaneSunFlare.obj) ---
//        
//        if let flareNode = loadMeshNode(meshName: planeFlareMeshName, scaleToUnit: false),
//           let geometryNode = findFirstGeometryNode(flareNode) {
//            geometryNode.name = "PlaneSunFlare"
//            scaleNodeToDiameter(geometryNode, diameter: 2000.0)
//            centerGeometryPivot(geometryNode)
//            let material = SCNMaterial()
//            material.isDoubleSided = true
//            material.blendMode = .add
//            material.writesToDepthBuffer = false
//            material.lightingModel = .constant
//            
//            if let flareImage = UIImage(named: "plane_sun_flare.png") {
//                let flareTex = SCNMaterialProperty(contents: flareImage)
//                material.setValue(flareTex, forKey: "_FlareTex")
//            }
//            let fragmentModifier = """
//                            #pragma arguments
//                            float4 _SunColor;
//                            texture2d<float> _FlareTex;
//
//                            #pragma body
//                            _output.color = float4(0.0);
//
//                            float2 uv = _surface.diffuseTexcoord;
//                            constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
//                            float4 tex = _FlareTex.sample(texSampler, uv);
//
//                            float2 cent = uv - float2(0.5, 0.5);
//                            float dist = length(cent) / 0.7071;
//                            float mask = saturate(1.0 - dist);
//
//                            float3 rgb = tex.rgb * _SunColor.rgb * mask;
//                            float  a   = tex.a * _SunColor.a * mask;
//                            
//                            _output.color = float4(rgb, a);
//                            """
//            material.shaderModifiers = [.fragment: fragmentModifier]
//            
//            geometryNode.geometry?.firstMaterial = material
//            geometryNode.renderingOrder = 50
//            parentSunNode.addChildNode(geometryNode)
//        }
        
        
        // Apply slight Z offsets if needed to fine-tune layering, adjust renderingOrder as well.
        return parentSunNode
    }
    
    
    // Unchanged createMoonNode, createStarsNode, createDirectionalLightNode, createAmbientLightNode, createCharacterNode
    func createMoonNode(textureName: String, size: CGFloat) -> SCNNode {
        let plane = SCNPlane(width:size, height:size)
        let mat=SCNMaterial()
        
        mat.lightingModel = .constant
        if let img = UIImage(named:textureName) {
            mat.emission.contents = img
            mat.emission.intensity = 0.9 // Slightly less intense than default
        }
        else {
            
            print("Warn: Moon texture '\(textureName)' missing")
            mat.emission.contents = UIColor.white
            
        }
        mat.multiply.contents=UIColor.white
        mat.writesToDepthBuffer=false
        mat.blendMode = .alpha
        plane.materials=[mat]
        let node=SCNNode(geometry:plane)
        node.name="MoonVisual"
        
        node.castsShadow=false
        node.constraints = [SCNBillboardConstraint()]
        return node
    }
    func createStarsNode() -> SCNNode {
        
        let node=SCNNode()
        node.name="Stars"
        if let stars=SCNParticleSystem(named: "Stars.scnp", inDirectory:nil) {
            // Configure particle system properties
            
            stars.particleSize=0.1
            stars.birthRate=500 // Number of stars generated over time
            stars.particleLifeSpan=1000 // Very long lifespan so they don't disappear
            
            stars.emitterShape=SCNSphere(radius:150) // Emit from a large sphere shape
            stars.emissionDuration=1000 // Long emission duration
            
            stars.spreadingAngle=180 // Emit in all directions
            stars.particleColor = .white
            stars.particleIntensity=0 // Start invisible (controlled by day/night cycle)
            node.addParticleSystem(stars)
            
            // Position stars centered slightly above horizon, far back
            node.position=SCNVector3(0, trajectoryCenterY+Float(trajectoryRadiusY*0.5), celestialBodyZ)
            
        }
        else {
            print("Error: Stars.scnp missing")
        }
        return node
    }
    func createDirectionalLightNode() -> SCNNode {
        let light=SCNLight()
        
        light.type = .directional
        light.color=UIColor.white
        
        light.intensity=0 // Start off
        light.castsShadow=true
        light.shadowMode = .deferred // Or .forward depending on performance needs
        light.shadowColor=UIColor.black.withAlphaComponent(0.7)
        light.shadowSampleCount=4 // Adjust for quality/performance
        light.shadowRadius=6.0 // Soften shadow edges
        light.shadowMapSize=CGSize(width:1024, height:1024) // Adjust for quality/performance
        
        let node=SCNNode()
        
        node.name="DirLight"
        node.light=light
        // Initial orientation doesn't matter much as it follows sun/moon
        node.eulerAngles=SCNVector3(-Float.pi/2, 0, 0)
        return node
    }
    func createAmbientLightNode() -> SCNNode {
        let light=SCNLight()
        light.type = .ambient
        light.color=UIColor.black // Start dark
        
        light.intensity=0
        let node=SCNNode()
        node.name="AmbLight"
        node.light=light
        return node
    }
    func createCharacterNode(height: CGFloat, radius: CGFloat) -> SCNNode {
        let cyl=SCNCylinder(radius:radius, height:height)
        let mat=SCNMaterial()
        mat.diffuse.contents=UIColor.red
        
        mat.lightingModel = .blinn // React to light
        
        cyl.materials=[mat]
        let node=SCNNode(geometry:cyl)
        node.name="Char"
        node.castsShadow=true // Character should cast shadow
        // Set pivot to bottom center for easier positioning on terrain
        node.pivot=SCNMatrix4MakeTranslation(0, -Float(height)/2, 0)
        return node
    }
    
    
    // MARK: - Coordinator Class
    class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var scnView: SCNView?
        //屏幕宽高比
        var aspectRatio: Float = 0.0
        // Configuration Properties  (Updated)
        let dayNightCycleEnabled: Bool
        let dayLengthInSeconds: TimeInterval
        let baseScrollUnitsPerSecond: CGFloat
        let maxUphillSlopeForSpeed: CGFloat
        let minDownhillSlopeForSpeed: CGFloat
        let minSpeedFactor: CGFloat
        
        let maxSpeedFactor: CGFloat
        // Near Terrain
        let terrainSegmentWidth: CGFloat
        let nearSegmentCount:  Int
        let nearAmplitude: CGFloat
        let nearVerticalOffset: CGFloat
        let nearTerrainMaxDeltaYPerPoint: CGFloat
        let nearPointsPerSegmentSpline: Int
        let nearExtrusionDepth: CGFloat
        
        let nearTerrainZPosition: Float
        let nearTerrainBaseHue: CGFloat
        let nearTerrainHueVariance: CGFloat
        let nearTerrainSaturationRange: ClosedRange<CGFloat>
        let nearTerrainBrightnessRange:  ClosedRange<CGFloat>
        let controlPointsPerSegmentNear: Int
        // Close Terrain
        let closeSegmentCount: Int
        let closeAmplitude: CGFloat
        
        let closeVerticalOffset: CGFloat
        let closePointsPerSegmentSpline: Int
        let closeExtrusionDepth: CGFloat
        let closeTerrainZPosition: Float
        let closeTerrainColor: UIColor
        let closeTerrainScrollSpeedFactor:  Float
        // *** Mid-Ground Terrain ***
        let midFrontMeshName: String
        let midFrontTerrainZPosition: Float
        
        let midFrontTerrainYOffset: CGFloat
        let midFrontMeshScale: Float
        let midFrontTerrainScrollSpeedFactor: Float
        let midBackMeshName: String
        let midBackTerrainZPosition: Float
        let midBackTerrainYOffset: CGFloat
        
        let midBackMeshScale: Float
        let midBackTerrainScrollSpeedFactor: Float
        let backgroundMeshName:
        String
        let backgroundTerrainZPosition: Float
        let backgroundTerrainYOffset: CGFloat
        let backgroundMeshScale: Float
        let backgroundTerrainScrollSpeedFactor: Float
        // Far Terrain
        let farTerrainMeshName: String
        let farTerrainYOffset: CGFloat
        
        let farTerrainZPosition: Float
        let
        farTerrainScrollSpeedFactor: Float
        let farTerrainMeshScale: Float
        // Character
        let fixedCharacterBaseY: Float
        let characterZPosition: Float
        // Day/Night
        let trajectoryRadiusX: Float
        let trajectoryRadiusY: Float
        let trajectoryCenterY: Float
        let celestialBodyZ:  Float
        
        // Alto Sun Meshes
        let altoSunCoreMeshName: String
        let altoSunHaloMeshName: String
        let altoSunGlowMeshName: String
        let altoSunFlareMeshName: String
        let altoSunFlatMeshName: String
        let altoPlaneGlowMeshName: String
        let altoPlaneFlareMeshName: String
        
        // Other Celestial
        
        let moonVisualSize: CGFloat
        let sunSetScaleFactor: Float // Keep for potential sun complex scaling
        // let sunTextureName: String // Removed
        let moonTextureName: String
        // let sunGlowTextureName: String // Removed
        // let sunGlowSizeMultiplier: CGFloat // Removed
        
        // State Variables
        weak var scene: SCNScene?
        var timeOfDay: Float = 0.2 // Start near dawn
        var lastUpdateTime: TimeInterval = 0
        var currentNearScrollAmount: Float = 0.0 // Base scroll amount calculated from near terrain speed
        
        // Scene Element References (Updated)
        // var sunVisualNode: SCNNode? // Removed old sun
        // var sunGlowNode: SCNNode? // Removed old glow
        var altoSunParentNode: SCNNode? // Reference to the new sun complex parent
        var altoSunCoreNode: SCNNode?   // Specific reference to the core for color updates
        var moonVisualNode: SCNNode?
        var starsNode: SCNNode?
        var directionalLightNode: SCNNode?
        var ambientLightNode: SCNNode?
        weak var characterNode: SCNNode?
        // Dynamic Terrain State
        let nearTerrainParent = SCNNode()
        var nearTerrainNodes: [SCNNode] = []
        var nearGlobalControlPoints: [CGPoint] = []
        var nearGlobalDenseTerrainPoints: [CGPoint] = []
        let closeTerrainParent = SCNNode()
        var closeTerrainNodes: [SCNNode] = []
        var closeGlobalControlPoints: [CGPoint] = []
        
        
        
        // Static Background Terrain State
        var midFrontTerrainParent: SCNNode?
        var midFrontMeshNode: SCNNode?
        var midFrontMeshWidth: Float = 0 // Store mesh width for scrolling
        
        var midBackTerrainParent: SCNNode?
        var midBackMeshNode: SCNNode?
        var midBackMeshWidth: Float = 0 // Store mesh width for scrolling
        
        var backgroundTerrainParent: SCNNode?
        var backgroundMeshNode: SCNNode?
        var backgroundMeshWidth: Float = 0 // Store mesh width for scrolling
        
        var farTerrainParent: SCNNode?
        var farTerrainMeshNode: SCNNode?
        // No width needed for far terrain as it doesn't scroll infinitely
        
        
        // Shader Uniforms (for dynamic updates if needed, e.g., fog color based on sky)
        var currentFogColor: UIColor = TimeOfDayConstants.SkyColors.dayBottom // Initial guess
        
        let randomSource = GKARC4RandomSource()
        
        // Initializer (Updated)
        init(
            // Core Params
            dayNightCycleEnabled: Bool, dayLengthInSeconds: TimeInterval,
            baseScrollUnitsPerSecond: CGFloat,  maxUphillSlopeForSpeed: CGFloat, minDownhillSlopeForSpeed: CGFloat,
            minSpeedFactor: CGFloat, maxSpeedFactor: CGFloat,
            // Near Terrain
            terrainSegmentWidth: CGFloat, nearSegmentCount: Int, nearAmplitude: CGFloat, nearVerticalOffset: CGFloat,
            nearTerrainMaxDeltaYPerPoint: CGFloat, nearPointsPerSegmentSpline: Int, nearExtrusionDepth: CGFloat,
            
            nearTerrainZPosition: Float, nearTerrainBaseHue: CGFloat, nearTerrainHueVariance: CGFloat,
            nearTerrainSaturationRange: ClosedRange<CGFloat>, nearTerrainBrightnessRange:  ClosedRange<CGFloat>,
            controlPointsPerSegmentNear: Int,
            // Close Terrain
            closeSegmentCount: Int, closeAmplitude: CGFloat, closeVerticalOffset: CGFloat,
            closePointsPerSegmentSpline: Int, closeExtrusionDepth: CGFloat, closeTerrainZPosition: Float,
            
            closeTerrainColor: UIColor, closeTerrainScrollSpeedFactor: Float,
            // *** Mid-Ground Terrain ***
            
            midFrontMeshName: String, midFrontTerrainZPosition: Float, midFrontTerrainYOffset: CGFloat,
            midFrontMeshScale: Float, midFrontTerrainScrollSpeedFactor: Float,
            midBackMeshName: String, midBackTerrainZPosition: Float, midBackTerrainYOffset: CGFloat,
            midBackMeshScale: Float, midBackTerrainScrollSpeedFactor:
            Float,
            backgroundMeshName: String, backgroundTerrainZPosition: Float, backgroundTerrainYOffset: CGFloat,
            backgroundMeshScale: Float, backgroundTerrainScrollSpeedFactor: Float,
            
            // Far Terrain
            farTerrainMeshName: String, farTerrainYOffset: CGFloat, farTerrainZPosition: Float,
            farTerrainScrollSpeedFactor: Float, farTerrainMeshScale: Float,
            // Character
            
            fixedCharacterBaseY: Float, characterZPosition: Float,
            // Day/Night
            trajectoryRadiusX: Float, trajectoryRadiusY: Float, trajectoryCenterY: Float, celestialBodyZ: Float,
            
            // Alto Sun Meshes
            altoSunCoreMeshName: String, altoSunHaloMeshName: String, altoSunGlowMeshName: String,
            altoSunFlareMeshName: String, altoSunFlatMeshName: String, altoPlaneGlowMeshName: String,
            altoPlaneFlareMeshName: String,
            
            // Other Celestial
            // sunVisualSize: CGFloat, // Removed
            moonVisualSize: CGFloat, sunSetScaleFactor: Float,
            // sunTextureName: String, // Removed
            moonTextureName: String
            // sunGlowTextureName: String, // Removed
            // sunGlowSizeMultiplier: CGFloat // Removed
        )
        {
            // Assign all properties...
            self.dayNightCycleEnabled = dayNightCycleEnabled
            self.dayLengthInSeconds = max(1.0, dayLengthInSeconds) // Avoid division by zero
            
            self.baseScrollUnitsPerSecond = baseScrollUnitsPerSecond
            self.maxUphillSlopeForSpeed = maxUphillSlopeForSpeed
            self.minDownhillSlopeForSpeed = minDownhillSlopeForSpeed
            
            self.minSpeedFactor = minSpeedFactor
            self.maxSpeedFactor = maxSpeedFactor
            self.terrainSegmentWidth = terrainSegmentWidth
            self.nearSegmentCount = nearSegmentCount
            self.nearAmplitude =  nearAmplitude
            self.nearVerticalOffset = nearVerticalOffset
            
            self.nearTerrainMaxDeltaYPerPoint = max(0, nearTerrainMaxDeltaYPerPoint) // Ensure non-negative
            self.nearPointsPerSegmentSpline = nearPointsPerSegmentSpline
            self.nearExtrusionDepth = nearExtrusionDepth
            self.nearTerrainZPosition = nearTerrainZPosition
            self.nearTerrainBaseHue = nearTerrainBaseHue
            
            self.nearTerrainHueVariance = nearTerrainHueVariance
            self.nearTerrainSaturationRange
            = nearTerrainSaturationRange
            self.nearTerrainBrightnessRange = nearTerrainBrightnessRange
            self.controlPointsPerSegmentNear = controlPointsPerSegmentNear
            self.closeSegmentCount = closeSegmentCount
            self.closeAmplitude = closeAmplitude
            self.closeVerticalOffset = closeVerticalOffset
            self.closePointsPerSegmentSpline =  closePointsPerSegmentSpline
            
            self.closeExtrusionDepth = closeExtrusionDepth
            self.closeTerrainZPosition = closeTerrainZPosition
            self.closeTerrainColor = closeTerrainColor
            self.closeTerrainScrollSpeedFactor = closeTerrainScrollSpeedFactor
            // Mid-Ground
            self.midFrontMeshName = midFrontMeshName
            self.midFrontTerrainZPosition = midFrontTerrainZPosition
            
            self.midFrontTerrainYOffset = midFrontTerrainYOffset
            self.midFrontMeshScale = midFrontMeshScale
            self.midFrontTerrainScrollSpeedFactor = midFrontTerrainScrollSpeedFactor
            self.midBackMeshName = midBackMeshName
            self.midBackTerrainZPosition = midBackTerrainZPosition
            self.midBackTerrainYOffset = midBackTerrainYOffset
            
            self.midBackMeshScale = midBackMeshScale
            
            self.midBackTerrainScrollSpeedFactor = midBackTerrainScrollSpeedFactor
            self.backgroundMeshName = backgroundMeshName
            self.backgroundTerrainZPosition = backgroundTerrainZPosition
            self.backgroundTerrainYOffset = backgroundTerrainYOffset
            self.backgroundMeshScale = backgroundMeshScale
            self.backgroundTerrainScrollSpeedFactor = backgroundTerrainScrollSpeedFactor
            
            // Far
            
            self.farTerrainMeshName = farTerrainMeshName
            self.farTerrainYOffset = farTerrainYOffset
            self.farTerrainZPosition = farTerrainZPosition
            self.farTerrainScrollSpeedFactor = farTerrainScrollSpeedFactor
            self.farTerrainMeshScale = farTerrainMeshScale
            
            // Character
            self.fixedCharacterBaseY = fixedCharacterBaseY
            
            self.characterZPosition = characterZPosition
            // Day/Night
            self.trajectoryRadiusX = trajectoryRadiusX
            self.trajectoryRadiusY = trajectoryRadiusY
            self.trajectoryCenterY = trajectoryCenterY
            
            self.celestialBodyZ = celestialBodyZ
            // Alto Sun
            self.altoSunCoreMeshName = altoSunCoreMeshName
            self.altoSunHaloMeshName = altoSunHaloMeshName
            self.altoSunGlowMeshName = altoSunGlowMeshName
            self.altoSunFlareMeshName = altoSunFlareMeshName
            self.altoSunFlatMeshName = altoSunFlatMeshName
            self.altoPlaneGlowMeshName = altoPlaneGlowMeshName
            self.altoPlaneFlareMeshName = altoPlaneFlareMeshName
            // Other Celestial
            // self.sunVisualSize = sunVisualSize // Removed
            self.moonVisualSize =  moonVisualSize
            self.sunSetScaleFactor = sunSetScaleFactor
            // self.sunTextureName = sunTextureName // Removed
            self.moonTextureName = moonTextureName
            // self.sunGlowTextureName = sunGlowTextureName // Removed
            
            super.init()
        }
        
        // MARK:  - Setup
        
        func setupInitialSceneElements() {
            guard let scene = scene else { return }
            // Setup Lights
            
            directionalLightNode = ParallaxTerrainSceneView().createDirectionalLightNode()
            scene.rootNode.addChildNode(directionalLightNode!)
            ambientLightNode = ParallaxTerrainSceneView().createAmbientLightNode()
            scene.rootNode.addChildNode(ambientLightNode!)
            
            // Setup Sun, Moon, Stars
            
            if dayNightCycleEnabled {
                // --- Create Alto Sun Complex ---
                altoSunParentNode = ParallaxTerrainSceneView().createAltoSunNode(
                    coreMeshName: altoSunCoreMeshName, haloMeshName: altoSunHaloMeshName,
                    glowMeshName: altoSunGlowMeshName, flareMeshName: altoSunFlareMeshName,
                    flatMeshName: altoSunFlatMeshName, planeGlowMeshName: altoPlaneGlowMeshName,
                    planeFlareMeshName: altoPlaneFlareMeshName
                )
                if let sunParent = altoSunParentNode {
                    sunParent.position = SCNVector3(0, -1000, celestialBodyZ) // Start offscreen
                    sunParent.isHidden = true
                    sunParent.renderingOrder = -500
      
                    scene.rootNode.addChildNode(sunParent)
                    // Store reference to core node for easy access to its material
                    altoSunCoreNode = sunParent.childNode(withName: "SunCore", recursively: false)
                } else {
                    print("ERROR: Failed to create Alto Sun complex.")
                }
                // --- End Alto Sun ---
                
                
                // --- Create Moon ---
                moonVisualNode = ParallaxTerrainSceneView().createMoonNode(textureName: moonTextureName, size: moonVisualSize)
                moonVisualNode?.position = SCNVector3(0,-1000, celestialBodyZ) // Start offscreen
                moonVisualNode?.isHidden = true
                scene.rootNode.addChildNode(moonVisualNode!)
                
                // --- Create Stars ---
                starsNode = ParallaxTerrainSceneView().createStarsNode()
                
                
                scene.rootNode.addChildNode(starsNode!)
            }
            // Setup Dynamic Terrain Parents (their content is added later)
            nearTerrainParent.position = SCNVector3(0, 0, nearTerrainZPosition)
            nearTerrainParent.name = "NearTerrainParent"
            scene.rootNode.addChildNode(nearTerrainParent)
            
            closeTerrainParent.position = SCNVector3(0, 0,  closeTerrainZPosition)
            closeTerrainParent.name = "CloseTerrainParent"
            scene.rootNode.addChildNode(closeTerrainParent)
            
            // Note: Static terrain parents (mid, far) are setup in the View's makeUIView -> setup... methods
        }
        
        
        
        // Unchanged setupDynamicTerrainsAndCharacter, alignInitialTerrainVerticalPosition
        func setupDynamicTerrainsAndCharacter() {
            guard let scene=scene else{return}
            
            // Initial number of segments to generate (enough to fill view plus some buffer)
            let
            initialNearSegments=nearSegmentCount+3 // Needs more buffer due to scrolling
            let initialMidSegments=closeSegmentCount+3
            // Distance between control points along X
            let dx=terrainSegmentWidth/CGFloat(controlPointsPerSegmentNear > 1 ?
                                               controlPointsPerSegmentNear - 1 : 1)
            // Starting X position (needs to be left of view)
            var currentX:CGFloat = -terrainSegmentWidth*1.5
            // Generate some flat initial points
            let initialFlatPoints = 2
            for _ in 0..<initialFlatPoints{let nearY=nearVerticalOffset
                
                let midY=closeVerticalOffset
                nearGlobalControlPoints.append(CGPoint(x:currentX, y:nearY))
                closeGlobalControlPoints.append(CGPoint(x:currentX, y:midY))
                currentX+=dx
            }
            
            // Total points to generate initially
            let pointsToGenerate = max(initialNearSegments,  initialMidSegments)*(controlPointsPerSegmentNear>1 ? controlPointsPerSegmentNear-1 : 1)
            // Terrain height limits
            let nearMinY = nearVerticalOffset-nearAmplitude
            let nearMaxY = nearVerticalOffset+nearAmplitude
            
            
            // Generate initial random terrain points
            for _ in 0..<pointsToGenerate{guard let lastNearPoint=nearGlobalControlPoints.last else{
                
                continue // Should not happen after initial points
            }
                
                let lastNearY=lastNearPoint.y
                // Calculate next point's Y based on max delta
                let deltaY = CGFloat(randomSource.nextUniform())*2*nearTerrainMaxDeltaYPerPoint - nearTerrainMaxDeltaYPerPoint
                let proposedNearY =  lastNearY + deltaY
                // Clamp to amplitude bounds
                
                let nextNearY = max(nearMinY, min(proposedNearY, nearMaxY))
                // Calculate corresponding mid terrain Y based on relative amplitude
                let nearYDeviation = nextNearY - nearVerticalOffset
                
                let
                midYDeviation = nearYDeviation*(closeAmplitude/nearAmplitude)
                let nextMidY = closeVerticalOffset+midYDeviation
                // Add new points
                nearGlobalControlPoints.append(CGPoint(x:currentX, y:nextNearY))
                closeGlobalControlPoints.append(CGPoint(x:currentX, y:nextMidY))
                // Move to next X position
                currentX+=dx
            }
            // Clear existing nodes and generate new terrain segments
            nearGlobalDenseTerrainPoints.removeAll() // Important: Regenerate dense points
            nearTerrainNodes.forEach{$0.removeFromParentNode()}
            nearTerrainNodes.removeAll()
            
            for i in 0..<initialNearSegments{
                _=addTerrainSegmentNode(type:.near, atIndex:i, isInitialSetup:true)
            }
            closeTerrainNodes.forEach{$0.removeFromParentNode()}
            closeTerrainNodes.removeAll()
            for i in 0..<initialMidSegments{
                _=addTerrainSegmentNode(type:.close, atIndex:i, isInitialSetup:true)
                
            }
            // Setup Character Node
            let charNode=ParallaxTerrainSceneView().createCharacterNode(height:1.6, radius:0.2) // Use values from config
            charNode.position=SCNVector3(0, fixedCharacterBaseY, characterZPosition)
            
            scene.rootNode.addChildNode(charNode)
            self.characterNode=charNode // Store reference
            // Align terrain vertically initially
            
            alignInitialTerrainVerticalPosition()
            print("Init dynamic terrain done.")
        }
        
        func alignInitialTerrainVerticalPosition() {
            guard characterNode != nil else{return}
            // Get height of near terrain at x=0
            if let initialTerrainY = getDenseTerrainHeight(at:0){
                // Adjust parent node so terrain height at x=0 matches character base Y
                nearTerrainParent.position.y = fixedCharacterBaseY - Float(initialTerrainY)
            }
            else{
                // Fallback if height lookup fails
                nearTerrainParent.position.y = fixedCharacterBaseY - Float(nearVerticalOffset)
            }
        }
        
        // This function is no longer needed as references are set directly via inout parameters
        //        func registerStaticMesh(node: SCNNode) { ... }
        
        // MARK: - SCNSceneRendererDelegate (Update Loop)
        
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard scene != nil else { return }
            if lastUpdateTime == 0 { lastUpdateTime = time }
            let deltaTime = time - lastUpdateTime
            guard deltaTime > 0 else { return } // Avoid division by zero or negative time
            lastUpdateTime = time
            
            // Update Day/Night Cycle first if enabled
            if dayNightCycleEnabled {
                updateDayNightCycle(deltaTime: deltaTime)
            }
            
            // Update Dynamic Terrains (Near terrain update calculates currentNearScrollAmount)
            
            updateNearTerrain(deltaTime: deltaTime)
            updateCloseTerrain(deltaTime: deltaTime)
            
            // *** Update Static Background Terrains (using currentNearScrollAmount) ***
            
            updateMidAndFarTerrains(deltaTime: deltaTime) // Uses scroll amount calculated by near terrain
            
            
            
            // Compute tints and ambient color for TERRAIN SHADER
            let coldTint = UIColor(red: 0.6, green: 0.75, blue: 0.9, alpha: 1.0).scnVector4
            
            let warmTint = UIColor(red: 1.0, green: 0.8,  blue: 0.6, alpha: 1.0).scnVector4
            let ambientProps = getAmbientLightProperties(timeOfDay: timeOfDay) // Get ambient properties
            let ambientColorForShader = ambientProps.color // Use the color calculated for ambient light
            
            
            // Update uniforms on all STATIC TERRAIN meshes
            
            // Update uniforms on all static meshes
            for node in [midFrontMeshNode, midBackMeshNode, backgroundMeshNode, farTerrainMeshNode] {
                updateMeshUniformRecursively(node: node, key: "u_timeOfDay",      value: timeOfDay)
                
                updateMeshUniformRecursively(node: node, key: "u_coldTintColor", value: coldTint)
                
                updateMeshUniformRecursively(node: node, key: "u_warmTintColor", value: warmTint)
                updateMeshUniformRecursively(node: node, key: "u_ambientColor", value: ambientColorForShader.scnVector4) // Update ambient uniform
            }
            
            // Also update the *material's* ambient property based on the  ambient light
            
            // This allows SceneKit's standard lighting to contribute ambient light *in addition*
            // to what the shader does with the diffuse color.
            // Keep this line, it might still influence the Blinn model's ambient term depending on SceneKit's internal handling.
            let ambientColorForMaterial = ambientProps.color
            updateMeshAmbientRecursively(node: midFrontMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: midBackMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: backgroundMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: farTerrainMeshNode, color: ambientColorForMaterial)
        }
        
        
        // MARK: - Day/Night Cycle Update Logic
        
        // Helper to update sun core color based on Alto logic
        func getAltoSunCoreColor(timeOfDay: Float) -> UIColor {
            let t = CGFloat(timeOfDay)
            let coldColor = TimeOfDayConstants.SunCoreColors.dawn
            let warmColor = TimeOfDayConstants.SunCoreColors.sunset
            let noonColor = TimeOfDayConstants.SunCoreColors.midday
            
            let tintColor: UIColor
            if t < 0.5 {
                let rawPhase = (t - CGFloat(TimeOfDayConstants.sunriseTime)) / 0.25
                let phase = clamp(rawPhase, min: 0.0, max: 1.0)
                tintColor = blendColors(coldColor, noonColor, t: phase)
            } else {
                let rawPhase = (t - CGFloat(TimeOfDayConstants.middayTime)) / 0.25
                let phase = clamp(rawPhase, min: 0.0, max: 1.0)
                tintColor = blendColors(noonColor, warmColor, t: phase)
            }
            return tintColor
        }
        
        
        func updateDayNightCycle(deltaTime: TimeInterval) {
            
            let timeIncrement = Float(deltaTime / dayLengthInSeconds)
            timeOfDay = (timeOfDay + timeIncrement).truncatingRemainder(dividingBy: 1.0)
            
            let T = TimeOfDayConstants.self
            let fullCycleDuration: Float = 1.0
            
            let dayDuration = T.sunsetTime - T.sunriseTime
            
            let nightDuration = fullCycleDuration - dayDuration
            var sunAngle: Float?
            = nil
            var moonAngle: Float?
            = nil
            
            // Calculate Sun/Moon Angles
            if timeOfDay >= T.sunriseTime && timeOfDay < T.sunsetTime { // Daytime
                let progress = (timeOfDay - T.sunriseTime) / dayDuration
                sunAngle = .pi - (progress *
                    .pi) // 0 at sunset,  pi at sunrise
            } else { // Nighttime
                let timeIntoNight: Float = (timeOfDay >= T.sunsetTime) ?
                (timeOfDay - T.sunsetTime) : (fullCycleDuration - T.sunsetTime + timeOfDay)
                let progress = timeIntoNight / nightDuration
                moonAngle = .pi - (progress * .pi) // 0 at moonset, pi at moonrise (opposite sun)
            }
            
            
            // Calculate Sun/Moon Positions
            
            var sunPosition = SCNVector3(0, -1000, celestialBodyZ) // Default offscreen
            if let angle = sunAngle { sunPosition = calculateArcPosition(angle: angle) }
            
            var moonPosition = SCNVector3(0, -1000, celestialBodyZ) // Default offscreen
            
            if let angle = moonAngle { moonPosition = calculateArcPosition(angle: angle) }
            
            
            // Get Time-Based Properties
            let sunIsVisible = (sunAngle != nil && sunAngle! > 0 && sunAngle! < .pi)
            // let sunProps = getSunProperties(timeOfDay: timeOfDay, sunAngle: sunAngle) // Old simple sun props
            let moonProps = getMoonProperties(timeOfDay: timeOfDay, moonAngle: moonAngle)
            
            let ambientProps = getAmbientLightProperties(timeOfDay: timeOfDay) // Get ambient properties
            let skyColors = getSkyGradientColors(timeOfDay: timeOfDay)
            
            let starsIntensity = getStarsIntensity(timeOfDay: timeOfDay)
            // let glowColor = getGlowColor(timeOfDay: timeOfDay, sunAngle: sunAngle) // Old glow color logic removed
            
            
            // --- Update Alto Sun Complex ---
            altoSunParentNode?.position = sunPosition
            altoSunParentNode?.isHidden = !sunIsVisible
            
            if sunIsVisible {
                //                // Update Core Color using the new logic
                //                let coreColor = getAltoSunCoreColor(timeOfDay: timeOfDay)
                //                if let coreMaterial = altoSunCoreNode?.geometry?.firstMaterial {
                //                    coreMaterial.emission.contents = coreColor
                //                    coreMaterial.emission.intensity = 1.0 // Keep it emissive when sun is visible
                //                }
                
                // --- Calculate Dynamic Sun Properties ---
                let coreColor = getAltoSunCoreColor(timeOfDay: timeOfDay) // Base color/tint for the sun core
                let altitudeFactor = sin(sunAngle ?? 0) // 0.0 on horizon, 1.0 at peak
                let baseGlowColor = UIColor(red: 1.0, green: 0.8, blue: 0.6, alpha: 1.0) // Warm base
                let peakGlowColor = UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1.0) // Slightly less saturated at peak
                let currentGlowColor = baseGlowColor.interpolate(to: peakGlowColor, fraction: CGFloat(altitudeFactor))
                
                // Example: Define dynamic glow scale (e.g., stronger near horizon)
                let minGlowScale: Float = 0.8
                let maxGlowScale: Float = 1.2
                // Make scale highest (maxGlowScale) at horizon (altitudeFactor=0) and lowest (minGlowScale) at peak (altitudeFactor=1)
                //let currentGlowScale = maxGlowScale - (maxGlowScale - minGlowScale) * altitudeFactor
                
                
                // --- Update Sun Core Material Uniforms ---
                // Modified section
                if let coreMaterial = altoSunCoreNode?.geometry?.firstMaterial {
                    // Update the shader uniforms
                    coreMaterial.setValue(coreColor.scnVector4, forKey: "u_color") // Update base tint
                }
                // 3. 更新 SunGlow 材质
//                // 假设你在 Coordinator 里存了一个引用：
//                if let scene = scene,
//                   let glowNode = scene.rootNode.childNode(withName: "SunGlow", recursively: true),
//                   let mat = glowNode.geometry?.firstMaterial {
//                    // 如果是使用 shader uniform：
//                    mat.setValue(NSValue(scnVector4: coreColor.scnVector4), forKey: "u_glowColor")
//                    mat.setValue(coreColor.scnVector4, forKey: "u_color");
//                    // 可选：如果你想同时动态调节发光强度
//                    //let scale = Float(sin(timeOfDay * .pi))
//                    let shifted = 0.001*sin((timeOfDay - 0.1) * .pi) // 向后偏移10%
//                    let scale = max(0.0, Float(shifted))
//                    mat.setValue(scale, forKey: "u_glowScale")
//                }
//                //4.flare
//                if let scene = scene,
//                      let sunFlare = scene.rootNode.childNode(withName: "SunFlare", recursively: true),
//                   let material = sunFlare.geometry?.firstMaterial{
//                   
//                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
//                    coreColor.getRed(&r, green: &g, blue: &b, alpha: &a)
//                    //let fadeAlpha = 0.1*cos((timeOfDay - 0.5) * .pi)
//                    //let clampedAlpha = max(0.0, fadeAlpha)
//                    let fadeAlpha = 0.0001 * max(0, cos((timeOfDay - 0.5) * .pi))
//                    
//
//                    let finalColor = SCNVector4(Float(r), Float(g), Float(b), fadeAlpha)
//                    material.setValue(finalColor, forKey:"_SunColor")
//                }
//                //plane flare
//                if let scene = scene,
//                      let sunFlare = scene.rootNode.childNode(withName: "PlaneSunFlare", recursively: true),
//                   let material = sunFlare.geometry?.firstMaterial{
//                   
//                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
//                    coreColor.getRed(&r, green: &g, blue: &b, alpha: &a)
//                    let fadeAlpha = 0.000001 * max(0, cos((timeOfDay - 0.5) * .pi))
//                    
//
//                    let finalColor = SCNVector4(Float(r), Float(g), Float(b), fadeAlpha)
//                    material.setValue(finalColor, forKey:"_SunColor")
//                }
                
                

                    
               
//                //6.大范围的光晕
//                guard let scene = scene,
//                      let glowNode = scene.rootNode.childNode(withName: "PlaneSunGlow", recursively: true),
//                      let bigMat = glowNode.geometry?.firstMaterial else { return }
//
//                //let bigGlowScale = pow(sin(timeOfDay * .pi), 1.8)
//                let shifted = 0.5*sin((timeOfDay - 0.1) * .pi) // 向后偏移10%
//                let bigGlowScale = max(0.0, Float(shifted))
//                   // 3. 更新 shader uniform
//                bigMat.setValue(NSValue(scnVector4: coreColor.scnVector4), forKey: "u_glowColor")
//                bigMat.setValue(coreColor.scnVector4, forKey: "u_color");
//                bigMat.setValue(bigGlowScale, forKey: "u_glowScale")
                    
                
                // - // TODO: Update other layers if needed
                
//                let scale = 1.0 + (1.0 - altitudeFactor) * (sunSetScaleFactor - 1.0)
//                altoSunParentNode?.scale = SCNVector3(scale, scale, scale)
                
                //                // Scale sun complex near horizon (optional, applied to parent)
                //                let altitudeFactor = sunAngle != nil ? max(0, sin(sunAngle!)) : 0 // 0 on horizon, 1 at peak
                //                let scale = 1.0 + (1.0 - altitudeFactor) * (sunSetScaleFactor - 1.0)
                //                altoSunParentNode?.scale = SCNVector3(scale, scale, scale) // Apply uniform scale to parent
                
                // TODO: Optionally update colors/intensities of other sun layers (Glow, Flare etc.) based on timeOfDay or sunAngle if needed.
                // For now, they use the fixed materials set up during creation.
            } else {
                // Ensure core emission is off when sun is down
                if let coreMaterial = altoSunCoreNode?.geometry?.firstMaterial {
                    coreMaterial.emission.intensity = 0.0
                }
            }
            
            
            // --- Update Moon Visual Node --- (Unchanged)
            moonVisualNode?.position = moonPosition
            
            moonVisualNode?.isHidden = !moonProps.isVisible
            if let material = moonVisualNode?.geometry?.firstMaterial {
                material.multiply.contents = moonProps.color // Tint moon texture
                
                material.emission.intensity = moonProps.isVisible ?
                0.9 : 0.0 // Make emissive only when visible
                moonVisualNode?.scale = SCNVector3(1, 1, 1) // Reset scale if needed
            }
            
            // Update Lights (Based on Sun/Moon Visibility and Position)
            if let light = directionalLightNode?.light {
                if sunIsVisible {
                    // Calculate intensity based on altitude similar to old sun logic
                    let altitudeFactor = sin(sunAngle ?? 0) // 0.0 on horizon, 1.0 at peak
                    light.intensity = T.sunIntensityDawnSunset + (T.sunIntensityMax
                                                                  - T.sunIntensityDawnSunset) * CGFloat(altitudeFactor) // Using constants from T
                    
                    // Use the calculated core color for the directional light, maybe interpolated towards white at noon
                    let sunLightBaseColor = getAltoSunCoreColor(timeOfDay: timeOfDay)
                    light.color = sunLightBaseColor.interpolate(to: T.LightColors.sunMidday, fraction: CGFloat(altitudeFactor))
                    
                    directionalLightNode?.look(at: SCNVector3(0, 0, 0)) // Point towards origin
                    directionalLightNode?.position = sunPosition // Position light with the sun
                    
                } else if moonProps.isVisible {
                    light.intensity = moonProps.intensity
                    
                    light.color = T.LightColors.moon // Use fixed moon color
                    
                    directionalLightNode?.look(at: SCNVector3(0, 0, 0)) // Point towards origin
                    directionalLightNode?.position = moonPosition // Position light with the moon
                } else {
                    light.intensity = 0 // No directional light when both are down
                }
            }
            ambientLightNode?.light?.intensity = ambientProps.intensity
            ambientLightNode?.light?.color = ambientProps.color
            
            
            // Update Background & Stars
            
            if let gradientImage = ParallaxTerrainSceneView().generateGradientImage(size: CGSize(width: 1, height: 512), topColor: skyColors.top, bottomColor: skyColors.bottom) {
                scene?.background.contents = gradientImage
            }
            starsNode?.particleSystems?.first?.particleIntensity = starsIntensity
            
            
            // *** Update Fog Color Uniform for Static Terrain Shaders  ***
            // Use a color slightly blended from the sky gradient for the fog
            let currentSkyFogColor = skyColors.bottom.interpolate(to: skyColors.top, fraction: 0.3)
            self.currentFogColor = currentSkyFogColor // Store for potential use elsewhere
            
            updateMeshUniformRecursively(node: midFrontMeshNode, key: "u_fogColor", value: currentSkyFogColor.scnVector4)
            updateMeshUniformRecursively(node: midBackMeshNode, key: "u_fogColor", value: currentSkyFogColor.scnVector4)
            
            updateMeshUniformRecursively(node: backgroundMeshNode, key: "u_fogColor", value: currentSkyFogColor.scnVector4)
            updateMeshUniformRecursively(node: farTerrainMeshNode, key: "u_fogColor", value: currentSkyFogColor.scnVector4)
            
            
            // NEW: Update Ambient Color Uniform for Static Terrain Shaders
            let ambientColorForShader = ambientProps.color // Use the color calculated for ambient light
            updateMeshUniformRecursively(node: midFrontMeshNode,  key: "u_ambientColor", value: ambientColorForShader.scnVector4)
            updateMeshUniformRecursively(node: midBackMeshNode, key: "u_ambientColor", value: ambientColorForShader.scnVector4)
            updateMeshUniformRecursively(node: backgroundMeshNode, key: "u_ambientColor", value: ambientColorForShader.scnVector4)
            
            updateMeshUniformRecursively(node: farTerrainMeshNode, key: "u_ambientColor", value: ambientColorForShader.scnVector4)
            
            
            // Also update the *material's* ambient property based on the  ambient light
            // This allows SceneKit's standard lighting to contribute ambient light *in addition*
            // to what the shader does with the diffuse color.
            // Keep this line, it might still influence the Blinn model's ambient term depending on SceneKit's internal handling.
            let ambientColorForMaterial = ambientProps.color
            updateMeshAmbientRecursively(node: midFrontMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: midBackMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: backgroundMeshNode, color: ambientColorForMaterial)
            updateMeshAmbientRecursively(node: farTerrainMeshNode, color: ambientColorForMaterial)
        }
        
        
        // Helper to update a specific shader uniform recursively
        
        private func updateMeshUniformRecursively(node: SCNNode?, key:  String, value: Any) {
            guard let node = node else { return }
            if let geometry = node.geometry {
                geometry.materials.forEach {
                    $0.setValue(value, forKey: key)
                    
                }
            }
            for child in node.childNodes {
                updateMeshUniformRecursively(node: child, key: key, value: value)
            }
        }
        
        
        
        // Helper to apply ambient color recursively (Unchanged)
        private func updateMeshAmbientRecursively(node:  SCNNode?, color: UIColor) {
            guard let node = node else { return }
            if let geometry = node.geometry {
                geometry.materials.forEach { $0.ambient.contents = color } // Apply to all materials
                
            }
            for child in node.childNodes {
                
                updateMeshAmbientRecursively(node: child, color: color)
            }
        }
        
        // MARK: - Property Calculation Helpers (Updated/Removed some)
        
        func calculateArcPosition(angle: Float) -> SCNVector3 {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView,
                  let cam = cameraNode.camera else {
                // 回退到老逻辑
                return SCNVector3(trajectoryRadiusX * cos(angle),
                                  trajectoryCenterY + trajectoryRadiusY * sin(angle),
                                  celestialBodyZ)
            }

            // 1. 计算视口世界尺寸
            let fovRad = cam.fieldOfView * .pi / 180.0
            let dist = abs(cameraNode.position.z - celestialBodyZ)
            let halfH = Float(tan(Double(fovRad) / 2.0) * Double(dist))
            let halfW = halfH * self.aspectRatio

            // 2. 归一化横纵坐标
            let xNorm = (cos(angle) + 1.0) / 2.0
            let yStart: Float = 1.0 - 3.0 / 7.0
            let yMid:   Float = 0.9
            let yNorm = yStart + (yMid - yStart) * sin(angle)

            // 3. 映射到世界坐标
            let xW = (xNorm - 0.5) * 2.0 * halfW
            let yW = (yNorm - 0.5) * 2.0 * halfH

            return SCNVector3(xW, yW, celestialBodyZ)
        }

        
        
        // --- REMOVED: getSunProperties (Replaced by Alto sun logic) ---
        // func getSunProperties(...) -> (...) { ... }
        
        // --- REMOVED: getGlowColor (Glow is now part of Alto sun complex) ---
        // func getGlowColor(...) -> UIColor { ... }
        
        
        // --- getMoonProperties, getAmbientLightProperties, getSkyGradientColors, getStarsIntensity remain UNCHANGED ---
        func getMoonProperties(timeOfDay: Float, moonAngle: Float?) -> (color: UIColor, intensity: CGFloat, isVisible: Bool) {
            guard let angle=moonAngle, angle>0&&angle < .pi else{return(.black, 0,  false)}// Moon below horizon
            let T=TimeOfDayConstants.self
            let altitudeFactor=sin(angle)// 0.0 on horizon, 1.0 at peak
            // Moon color slightly whiter/bluer when higher
            let color=T.MoonColors.low.interpolate(to: T.MoonColors.high, fraction:CGFloat(altitudeFactor))
            let intensity=T.moonIntensityMax*CGFloat(altitudeFactor)// Intensity based on altitude
            return(color, intensity, true)
        }
        func getAmbientLightProperties(timeOfDay: Float) -> (color: UIColor, intensity: CGFloat) {
            let T=TimeOfDayConstants.self
            
            var color=T.LightColors.ambientDay
            var intensity=T.ambientIntensityDay
            // Interpolate ambient light based on time of day transitions
            if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime { // Dawn
                
                let p=(timeOfDay-T.dawnStartTime)/T.dawnDuration
                color=T.LightColors.ambientNight.interpolate(to:T.LightColors.ambientDawn,
                                                             fraction:CGFloat(p))
                intensity=T.ambientIntensityNight+(T.ambientIntensityDawnSunset-T.ambientIntensityNight)*CGFloat(p)
            } else if timeOfDay>=T.sunriseTime&&timeOfDay<T.morningEndTime { // Sunrise transition
                let p=(timeOfDay-T.sunriseTime)/T.sunriseTransitionDuration
                
                color=T.LightColors.ambientDawn.interpolate(to:T.LightColors.ambientDay, fraction:CGFloat(p))
                intensity=T.ambientIntensityDawnSunset+(T.ambientIntensityDay-T.ambientIntensityDawnSunset)*CGFloat(p)
                
            } else if timeOfDay>=T.afternoonStartTime&&timeOfDay<T.sunsetTime { // Afternoon to Sunset
                let p=(timeOfDay-T.afternoonStartTime)/T.sunsetTransitionDuration
                color=T.LightColors.ambientDay.interpolate(to:T.LightColors.ambientSunset, fraction:CGFloat(p))
                intensity=T.ambientIntensityDay-(T.ambientIntensityDay-T.ambientIntensityDawnSunset)*CGFloat(p)
                
                
            } else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime { // Dusk
                
                let p=(timeOfDay-T.sunsetTime)/T.duskDuration
                color=T.LightColors.ambientSunset.interpolate(to:T.LightColors.ambientNight, fraction:CGFloat(p))
                intensity=T.ambientIntensityDawnSunset-(T.ambientIntensityDawnSunset-T.ambientIntensityNight)*CGFloat(p)
            } else if timeOfDay>=T.duskEndTime ||
                        timeOfDay<T.dawnStartTime { // Night
                color=T.LightColors.ambientNight
                intensity=T.ambientIntensityNight
            }
            // else: Day values are default
            return (color, intensity)
        }
        
        func getSkyGradientColors(timeOfDay: Float) -> (top: UIColor,  bottom: UIColor) {
            let T=TimeOfDayConstants.self
            var top=T.SkyColors.dayTop
            var bottom=T.SkyColors.dayBottom
            // Interpolate sky colors based on time of day transitions
            if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime { // Dawn
                
                let p=(timeOfDay-T.dawnStartTime)/T.dawnDuration
                
                top=T.SkyColors.nightTop.interpolate(to:T.SkyColors.dawnTop, fraction:CGFloat(p))
                bottom=T.SkyColors.nightBottom.interpolate(to:T.SkyColors.dawnBottom, fraction:CGFloat(p))
            } else if timeOfDay>=T.sunriseTime&&timeOfDay<T.morningEndTime { // Sunrise transition
                let p=(timeOfDay-T.sunriseTime)/T.sunriseTransitionDuration
                
                top=T.SkyColors.dawnTop.interpolate(to:T.SkyColors.dayTop, fraction:CGFloat(p))
                bottom=T.SkyColors.dawnBottom.interpolate(to:T.SkyColors.dayBottom,  fraction:CGFloat(p))
            } else if timeOfDay>=T.afternoonStartTime&&timeOfDay<T.sunsetTime { // Sunset transition
                let p=(timeOfDay-T.afternoonStartTime)/T.sunsetTransitionDuration
                top=T.SkyColors.dayTop.interpolate(to:T.SkyColors.sunsetTop, fraction:CGFloat(p))
                bottom=T.SkyColors.dayBottom.interpolate(to:T.SkyColors.sunsetBottom, fraction:CGFloat(p))
                
            } else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime { // Dusk
                
                let p=(timeOfDay-T.sunsetTime)/T.duskDuration
                top=T.SkyColors.sunsetTop.interpolate(to:T.SkyColors.nightTop, fraction:CGFloat(p))
                bottom=T.SkyColors.sunsetBottom.interpolate(to:T.SkyColors.nightBottom, fraction:CGFloat(p))
            } else if timeOfDay>=T.duskEndTime ||
                        timeOfDay<T.dawnStartTime { // Night
                top=T.SkyColors.nightTop
                bottom=T.SkyColors.nightBottom
            }
            // else: Day values are default
            return (top, bottom)
        }
        
        func getStarsIntensity(timeOfDay: Float) -> CGFloat {
            
            let T=TimeOfDayConstants.self
            var intensity:Float=0.0
            // Stars visible at night, fade in/out during dusk/dawn
            if timeOfDay>=T.duskEndTime||timeOfDay<T.dawnStartTime{ // Night
                intensity=1.0
                
            } else if timeOfDay>=T.sunsetTime&&timeOfDay<T.duskEndTime{ // Fading in during dusk
                
                intensity=(timeOfDay-T.sunsetTime)/T.duskDuration
            } else if timeOfDay>=T.dawnStartTime&&timeOfDay<T.sunriseTime{ // Fading out during dawn
                intensity=1.0-((timeOfDay-T.dawnStartTime)/T.dawnDuration)
            }
            // else: intensity is 0 during day
            return CGFloat(intensity)*T.starsIntensityMax
        }
        
        
        // MARK: - Terrain Update Logic (Unchanged)
        
        func updateNearTerrain(deltaTime: TimeInterval) {
            // This function MUST be called before others that depend on currentNearScrollAmount
            guard characterNode != nil, !nearTerrainNodes.isEmpty, !nearGlobalDenseTerrainPoints.isEmpty else{
                
                self.currentNearScrollAmount = 0.0 // Reset scroll amount if no terrain
                
                return
            }
            // Get character's global X position (inverse of terrain parent's X)
            let terrainGlobalX = -nearTerrainParent.position.x
            
            // Get terrain slope at character's position
            let slope = getSlope(at: CGFloat(terrainGlobalX)) ??
            0.0
            // Calculate speed factor based on slope
            let speedFactor = calculateSpeedFactor(slope: slope)
            
            // Calculate the scroll amount for this frame based on near terrain speed
            self.currentNearScrollAmount = Float(baseScrollUnitsPerSecond * deltaTime * speedFactor)
            
            // Apply scroll to near terrain parent (moves terrain left)
            
            nearTerrainParent.position.x -= self.currentNearScrollAmount
            
            // Adjust vertical position based on terrain height under character (at x=0 relative to parent)
            if let terrainY = getDenseTerrainHeight(at: CGFloat(terrainGlobalX)) {
                nearTerrainParent.position.y = fixedCharacterBaseY - Float(terrainY)
            }
            
            //  Manage dynamic segments (add/remove)
            manageTerrainSegments(type: .near)
        }
        
        func updateCloseTerrain(deltaTime: TimeInterval) {
            // Scrolls based on near terrain's calculated amount and its own speed factor
            guard !closeTerrainNodes.isEmpty else{return}
            
            let scrollAmount = self.currentNearScrollAmount * closeTerrainScrollSpeedFactor
            
            closeTerrainParent.position.x -= scrollAmount // Scroll close terrain
            manageTerrainSegments(type: .close) // Manage its segments
        }
        
        // *** Combined update for all static background layers WITH WRAPPING ***
        func updateMidAndFarTerrains(deltaTime: TimeInterval) {
            
            // Scroll each layer based on near terrain's amount and the layer's speed factor
            let baseScroll  = self.currentNearScrollAmount // Use the value calculated in updateNearTerrain
            
            // Update MidFront Layer with Wrapping
            if let parent = midFrontTerrainParent, midFrontMeshWidth > 0.001 { // Added tolerance
                parent.position.x -=
                baseScroll * midFrontTerrainScrollSpeedFactor
                let scaledWidth = midFrontMeshWidth * midFrontMeshScale
                // If the parent has scrolled left by more than one mesh width, reset its position
                if scaledWidth > 0.001 && parent.position.x <= -scaledWidth {
                    parent.position.x +=
                    scaledWidth
                    // print("Wrapped MidFront layer") // Less verbose logging
                }
            }
            
            // Update MidBack Layer with Wrapping
            if let parent = midBackTerrainParent, midBackMeshWidth > 0.001 { // Added tolerance
                
                parent.position.x -= baseScroll * midBackTerrainScrollSpeedFactor
                let scaledWidth = midBackMeshWidth * midBackMeshScale
                if scaledWidth > 0.001 && parent.position.x <= -scaledWidth {
                    parent.position.x += scaledWidth
                    //
                    print("Wrapped MidBack layer") // Less verbose logging
                }
            }
            
            // Update Background Layer with Wrapping
            if let parent = backgroundTerrainParent, backgroundMeshWidth > 0.001 { // Added tolerance
                parent.position.x -= baseScroll * backgroundTerrainScrollSpeedFactor
                
                let scaledWidth = backgroundMeshWidth * backgroundMeshScale
                if scaledWidth > 0.001 && parent.position.x <= -scaledWidth {
                    parent.position.x += scaledWidth
                    // print("Wrapped Background layer") // Less verbose logging
                }
                
            }
            
            // Update Far Layer (No Wrapping, as it's fixed or scrolls minimally)
            if let parent = farTerrainParent, farTerrainScrollSpeedFactor != 0 {
                parent.position.x -= baseScroll * farTerrainScrollSpeedFactor
                // No wrapping needed for the far layer in this setup
            }
        }
        
        // MARK: - Slope and Speed Calculation (Unchanged)
        func getSlope(at globalX: CGFloat) -> CGFloat?
        {
            guard nearGlobalDenseTerrainPoints.count >= 2 else{return nil}// Need at least two points
            // Find the segment containing globalX
            for i in 0..<(nearGlobalDenseTerrainPoints.count-1){
                let pA=nearGlobalDenseTerrainPoints[i]
                let pB=nearGlobalDenseTerrainPoints[i+1]
                
                let tolerance:CGFloat=0.0001 // Small tolerance for floating point comparison
                if (pA.x-tolerance)<=globalX&&globalX<=(pB.x+tolerance){
                    let deltaX=pB.x-pA.x
                    // Avoid division by zero if points are vertically aligned
                    
                    guard  abs(deltaX)>tolerance else{return pB.y>pA.y ?
                        .infinity : -.infinity}
                    // Calculate slope
                    return(pB.y-pA.y)/deltaX
                }
            }
            // Handle cases outside the known points (assume flat)
            
            
            if let firstPoint=nearGlobalDenseTerrainPoints.first, globalX<firstPoint.x{
                return 0.0 // Before the start
            }
            if let lastPoint=nearGlobalDenseTerrainPoints.last, globalX>lastPoint.x{
                return 0.0 // After the end
            }
            
            // Should ideally not be reached if globalX is within the generated range
            print("Warn: Slope lookup failed for X=\(globalX)")
            return nil
        }
        func calculateSpeedFactor(slope: CGFloat) -> CGFloat {
            var speedFactor:CGFloat=1.0
            // Default speed
            // Adjust speed based on  slope ranges
            if slope > 0 { // Uphill
                speedFactor = mapValue(slope, fromMin: 0, fromMax: maxUphillSlopeForSpeed, toMin: 1.0, toMax: minSpeedFactor)
            } else if slope < 0 { // Downhill
                
                speedFactor = mapValue(slope, fromMin: minDownhillSlopeForSpeed, fromMax: 0, toMin: maxSpeedFactor, toMax: 1.0)
                
            }
            // Clamp factor to defined min/max limits
            return max(minSpeedFactor, min(speedFactor, maxSpeedFactor))
        }
        
        
        // MARK: - Terrain Management (Near/Close Unchanged)
        
        enum TerrainType{case close,near}
        func manageTerrainSegments(type:TerrainType){
            // Get relevant nodes and parent based on type
            
            let terrainNodes=(type == .near) ?
            nearTerrainNodes : closeTerrainNodes
            let terrainParent=(type == .near) ?
            nearTerrainParent : closeTerrainParent
            let segmentWidth=terrainSegmentWidth
            let controlPointsPerSegment = controlPointsPerSegmentNear // Assuming same density for now
            
            // Check if the first segment is off-screen left
            guard let firstNode=terrainNodes.first else{return} // No nodes to manage
            // Calculate the right edge X-coordinate of the first segment in world  space
            let firstNodeRightLocal = firstNode.position.x + Float(segmentWidth)
            let firstNodeRightWorld = terrainParent.convertPosition(SCNVector3(firstNodeRightLocal, 0, 0), to:nil).x // nil means world coordinates
            
            // Define the removal threshold (e.g., 1.5 segments left of the view center)
            let removalThresholdX:Float = -Float(segmentWidth)*1.5
            
            
            if firstNodeRightWorld < removalThresholdX {
                
                // Remove the first node visually
                firstNode.removeFromParentNode()
                
                // Calculate number of control points and dense points to remove
                let controlPointsToRemove = controlPointsPerSegment > 1 ?
                controlPointsPerSegment-1 : 1; // Points per segment
                // Dense points calculation needs care depending on spline/linear
                let densePointsPerInterpolatedSegment = ((type == .near ? nearPointsPerSegmentSpline : closePointsPerSegmentSpline) > 0) ?
                (type == .near ? nearPointsPerSegmentSpline : closePointsPerSegmentSpline) : 1
                let densePointsToRemove = controlPointsToRemove * densePointsPerInterpolatedSegment
                
                // Remove corresponding data points
                if type == .near{
                    nearTerrainNodes.removeFirst()
                    
                    
                    // Remove control points carefully
                    if nearGlobalControlPoints.count>=controlPointsToRemove{nearGlobalControlPoints.removeFirst(controlPointsToRemove)}else{nearGlobalControlPoints.removeAll()}
                    // Remove dense points
                    if nearGlobalDenseTerrainPoints.count>densePointsToRemove{nearGlobalDenseTerrainPoints.removeFirst(densePointsToRemove)
                        
                    }else{
                        
                        nearGlobalDenseTerrainPoints.removeAll() // Clear if removing more than available
                    }
                }else{ // Close terrain
                    
                    closeTerrainNodes.removeFirst();
                    // Remove control points
                    if closeGlobalControlPoints.count>=controlPointsToRemove{
                        closeGlobalControlPoints.removeFirst(controlPointsToRemove)
                    }else{
                        
                        closeGlobalControlPoints.removeAll()
                        
                    }
                    // No global dense list needed for close terrain to manage here
                }
                // Add a new segment at the end
                
                addNewTerrainSegment(type:type)
                
            }
        }
        func addNewTerrainSegment(type:TerrainType){
            let pointsToAddAmount = controlPointsPerSegmentNear > 1 ?
            controlPointsPerSegmentNear-1 : 1 // Control points per new segment
            // Ensure last points exist and are aligned (simple check)
            guard let lastNearPoint=nearGlobalControlPoints.last, let lastMidPoint=closeGlobalControlPoints.last, abs(lastNearPoint.x-lastMidPoint.x)<0.01 else{
                print("Err: Cannot add seg - last points mismatch or missing.")
                return
                
            }
            
            var lastX = lastNearPoint.x;
            let dx=terrainSegmentWidth/CGFloat(controlPointsPerSegmentNear>1 ? controlPointsPerSegmentNear-1 : 1) // X step per control point
            let nearMinY = nearVerticalOffset-nearAmplitude
            let nearMaxY = nearVerticalOffset+nearAmplitude
            var lastNearY = lastNearPoint.y // Use last actual near Y
            
            // Generate new control points for the segment
            for _
                    in 0..<pointsToAddAmount{
                
                lastX+=dx // Increment X
                // Calculate next Y delta
                let deltaY=CGFloat(randomSource.nextUniform())*2*nearTerrainMaxDeltaYPerPoint - nearTerrainMaxDeltaYPerPoint
                let proposedNearY=lastNearY+deltaY
                
                // Clamp Y and calculate corresponding mid Y
                
                let nextNearY = max(nearMinY, min(proposedNearY, nearMaxY))
                let nearYDeviation=nextNearY-nearVerticalOffset
                let midYDeviation=nearYDeviation*(closeAmplitude/nearAmplitude)
                let nextMidY = closeVerticalOffset+midYDeviation
                
                // Add new points
                
                nearGlobalControlPoints.append(CGPoint(x:lastX, y:nextNearY))
                closeGlobalControlPoints.append(CGPoint(x:lastX, y:nextMidY))
                // Update last Y for next iteration
                lastNearY=nextNearY
                
            }
            
            // Add the new visual terrain node
            
            let newNodeIndex=(type == .near) ?
            nearTerrainNodes.count : closeTerrainNodes.count
            if addTerrainSegmentNode(type:type, atIndex:newNodeIndex, isInitialSetup:false)==nil{
                print("Err: Failed adding \(type) seg \(newNodeIndex).")
            }
        }
        private func addTerrainSegmentNode(type:TerrainType, atIndex index:Int, isInitialSetup:Bool) -> SCNNode?
        {
            // Select parameters based on terrain type
            let globalControlPoints=(type == .near) ?
            nearGlobalControlPoints : closeGlobalControlPoints
            let pointsPerSplineSegment=(type == .near) ?
            nearPointsPerSegmentSpline : closePointsPerSegmentSpline
            let extrusionDepth=(type == .near) ?
            nearExtrusionDepth : closeExtrusionDepth
            let terrainParent=(type == .near) ?
            nearTerrainParent : closeTerrainParent
            let verticalOffset=(type == .near) ?
            nearVerticalOffset : closeVerticalOffset
            let amplitude=(type == .near) ?
            nearAmplitude : closeAmplitude
            let controlPointsPerSegment = controlPointsPerSegmentNear // Assuming same for both for simplicity
            
            // Calculate indices for control points needed for this segment
            let startIndexInModel=index*(controlPointsPerSegment>1 ? controlPointsPerSegment-1 : 1)
            let endIndexInModel=startIndexInModel+controlPointsPerSegment
            // Include adjacent points for Catmull-Rom continuity
            
            let splineStartIndex = max(0, startIndexInModel-1)
            let splineEndIndex = min(globalControlPoints.count, endIndexInModel+1)
            
            // Ensure enough points for spline generation
            guard (splineEndIndex - splineStartIndex) >= 2 else{
                print("Err \(type) seg \(index): Not enough control points. Need indices \(splineStartIndex)..<\(splineEndIndex), have \(globalControlPoints.count)")
                
                return nil
            }
            let splineSegmentInputPoints=Array(globalControlPoints[splineStartIndex..<splineEndIndex])
            
            // Generate dense points using Catmull-Rom (only if enough points)
            let canUseRom = splineSegmentInputPoints.count>=4
            
            let effectivePointsPerSegment = canUseRom ?
            pointsPerSplineSegment : 0 // Use linear if not enough points for Catmull-Rom
            let allDensePointsForSpline = generateDenseCatmullRomPoints(controlPoints:splineSegmentInputPoints, pointsPerSegment:effectivePointsPerSegment)
            
            guard !allDensePointsForSpline.isEmpty else{print("Err \(type) seg \(index): Failed dense points generation.")
                return nil
            }
            
            
            // Calculate the slice of dense points relevant to *this* segment
            
            let indexShiftOrigin = startIndexInModel - splineStartIndex // How many segments back did spline start?
            guard indexShiftOrigin>=0 else { print("Err \(type) seg \(index): indexShiftOrigin < 0");
                return nil } // Should not happen
            
            let densePointsPerInterpolatedSegment = (effectivePointsPerSegment>0) ?
            effectivePointsPerSegment : 1 // If linear, 1 interval = 1 dense segment
            let densePointsOffset = indexShiftOrigin * densePointsPerInterpolatedSegment // Offset into dense points array
            let numInterpolatedSegments = controlPointsPerSegment>1 ?
            controlPointsPerSegment-1 : 1 // Segments between control points
            let densePointsCount = numInterpolatedSegments * densePointsPerInterpolatedSegment + 1 // +1 for the endpoint
            
            guard densePointsOffset>=0, densePointsCount>0, (densePointsOffset+densePointsCount)<=allDensePointsForSpline.count else{print("Err \(type) seg \(index): Dense points slice calculation error. Offset:\(densePointsOffset), Count:\(densePointsCount), Total:\(allDensePointsForSpline.count)")
                return nil
            }
            
            let  segmentDensePointsRelative = Array(allDensePointsForSpline[densePointsOffset..<(densePointsOffset+densePointsCount)])
            
            // Ensure we have points and the start X coordinate
            guard startIndexInModel<globalControlPoints.count else { print("Err \(type) seg \(index): startIndexInModel out of bounds.");
                return nil }
            let segmentStartX = globalControlPoints[startIndexInModel].x
            
            // Make points relative to the segment's starting X for the Bezier path
            let localDensePoints = segmentDensePointsRelative.map{CGPoint(x:$0.x-segmentStartX, y:$0.y)}
            guard !localDensePoints.isEmpty else{return nil}
            
            // Define base level for closing the shape
            
            let baseLevel = verticalOffset - amplitude*1.5 - 5 // Well below the terrain
            
            // Create Bezier path and the SCNNode
            let newPath = createPathFromDensePoints(points:localDensePoints, closePath:true, baseLevel:baseLevel)
            let newNode = createTerrainSegmentNode(path:newPath, type:type, extrusionDepth:extrusionDepth)
            newNode.position = SCNVector3(Float(segmentStartX), 0, 0) // Position segment correctly
            newNode.name  = "\(type)TSeg_\(index)" // Name for debugging
            terrainParent.addChildNode(newNode) // Add to scene
            
            // Append dense points to global list (for near terrain height lookups)
            // Handle potential overlap with previous segment's last point
            let globalDensePointsToAdd = segmentDensePointsRelative
            
            if type == .near{
                
                nearTerrainNodes.append(newNode)
                if let lastDense = nearGlobalDenseTerrainPoints.last, let firstNew = globalDensePointsToAdd.first, abs(lastDense.x-firstNew.x)<0.01, abs(lastDense.y-firstNew.y)<0.01{
                    // If first new point matches last existing point, drop the duplicate
                    
                    if globalDensePointsToAdd.count>1{
                        
                        nearGlobalDenseTerrainPoints.append(contentsOf:globalDensePointsToAdd.dropFirst())
                    } // else: only one point, it was a duplicate, do nothing
                }else if !globalDensePointsToAdd.isEmpty{
                    
                    // Otherwise, append all new points
                    
                    nearGlobalDenseTerrainPoints.append(contentsOf:globalDensePointsToAdd)
                }
            }else{ // Close terrain
                closeTerrainNodes.append(newNode)
                
                // No global dense list needed for close terrain usually
            }
            
            return newNode
        }
        func createTerrainSegmentNode(path:UIBezierPath, type:TerrainType, extrusionDepth:CGFloat) -> SCNNode {
            let shape=SCNShape(path:path, extrusionDepth:extrusionDepth)
            
            let material=SCNMaterial()
            // Set color based on type
            if type == .near{
                
                // Randomize near terrain color slightly
                let hue=nearTerrainBaseHue+CGFloat(randomSource.nextUniform())*2*nearTerrainHueVariance - nearTerrainHueVariance
                let saturation=CGFloat(randomSource.nextUniform())*(nearTerrainSaturationRange.upperBound -
                                                                    nearTerrainSaturationRange.lowerBound) + nearTerrainSaturationRange.lowerBound
                let brightness=CGFloat(randomSource.nextUniform())*(nearTerrainBrightnessRange.upperBound - nearTerrainBrightnessRange.lowerBound) + nearTerrainBrightnessRange.lowerBound
                material.diffuse.contents=UIColor(hue:hue, saturation:saturation, brightness:brightness, alpha:1.0)
            }else{ // Close  terrain uses fixed color
                material.diffuse.contents=closeTerrainColor
            }
            
            material.lightingModel = .blinn // React to lights
            material.isDoubleSided=false // Performance
            shape.materials=[material]
            let node=SCNNode(geometry:shape)
            
            // Near terrain casts shadows, close doesn't
            node.castsShadow=(type == .near)
            
            return node
        }
        func getDenseTerrainHeight(at globalX: CGFloat) -> CGFloat?
        {
            guard nearGlobalDenseTerrainPoints.count >= 2 else{return nil}// Need at least two points
            // Find the segment containing globalX
            for i in 0..<(nearGlobalDenseTerrainPoints.count-1){
                let pA=nearGlobalDenseTerrainPoints[i]
                let pB=nearGlobalDenseTerrainPoints[i+1]
                
                let tolerance:CGFloat=0.0001 // Tolerance for float comparison
                // Check if globalX is within the segment's bounds (inclusive)
                if(pA.x-tolerance)<=globalX&&globalX<=(pB.x+tolerance){
                    // Handle vertical segment (avoid division by zero)
                    
                    if abs(pB.x-pA.x)<tolerance{return(pA.y+pB.y)/2}//  Average Y
                    // Linear interpolation within the segment
                    let t = (globalX-pA.x)/(pB.x-pA.x)
                    let clampedT = max(0, min(1, t)) // Clamp t to [0, 1]
                    
                    
                    return pA.y + clampedT * (pB.y - pA.y)
                }
            }
            // Handle cases outside the known points
            if let firstPoint=nearGlobalDenseTerrainPoints.first, globalX<firstPoint.x{
                
                return firstPoint.y // Before the start, return first height
                
            }
            if let lastPoint=nearGlobalDenseTerrainPoints.last, globalX>lastPoint.x{
                return lastPoint.y // After the end, return last height
            }
            
            // Should not be reached if points cover the expected range
            print("Warn: Height lookup failed for X=\(globalX)")
            
            return nil
        }
        
        
        // MARK: - Cleanup
        deinit {
            print("Coordinator deinit.")
            
            // Remove dynamic terrain nodes
            nearTerrainParent.childNodes.forEach{$0.removeFromParentNode()}
            nearTerrainParent.removeFromParentNode()
            
            closeTerrainParent.childNodes.forEach{$0.removeFromParentNode()}
            closeTerrainParent.removeFromParentNode()
            
            // *** Remove static terrain nodes ***
            midFrontTerrainParent?.childNodes.forEach{$0.removeFromParentNode()}
            
            midFrontTerrainParent?.removeFromParentNode()
            midBackTerrainParent?.childNodes.forEach{$0.removeFromParentNode()}
            midBackTerrainParent?.removeFromParentNode()
            backgroundTerrainParent?.childNodes.forEach{$0.removeFromParentNode()}
            
            backgroundTerrainParent?.removeFromParentNode()
            farTerrainParent?.childNodes.forEach{$0.removeFromParentNode()}
            farTerrainParent?.removeFromParentNode()
            
            // *** Remove Alto Sun node ***
            altoSunParentNode?.childNodes.forEach{$0.removeFromParentNode()}
            altoSunParentNode?.removeFromParentNode()
            
            
            // Clear dynamic terrain state
            nearTerrainNodes.removeAll()
            nearGlobalControlPoints.removeAll()
            nearGlobalDenseTerrainPoints.removeAll()
            closeTerrainNodes.removeAll()
            
            closeGlobalControlPoints.removeAll()
            
            // Nil out static references
            
            midFrontMeshNode = nil
            midFrontTerrainParent = nil
            midFrontMeshWidth = 0 // Reset width
            midBackMeshNode = nil
            midBackTerrainParent = nil
            midBackMeshWidth = 0 // Reset width
            
            backgroundMeshNode = nil
            
            backgroundTerrainParent = nil
            backgroundMeshWidth = 0 // Reset width
            farTerrainMeshNode = nil
            farTerrainParent = nil
            
            // Nil out Alto Sun references
            altoSunParentNode = nil
            altoSunCoreNode = nil
        }
    }
}

 // Preview Provider (Unchanged)
struct ParallaxTerrainSceneView_Previews: PreviewProvider {
    static
    var previews: some View { ParallaxTerrainSceneView().edgesIgnoringSafeArea(.all)
    }
}
