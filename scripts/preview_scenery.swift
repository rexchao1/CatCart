// Offscreen preview of the roadside scenery, one PNG per world, on macOS.
//
// Build and run from the repo root:
//   swiftc -O -o /tmp/preview_scenery scripts/preview_scenery.swift CatCart/Scenery.swift
//   /tmp/preview_scenery [output-dir]
//
// It uses the same camera, fog, light and curved-world bend the game plans to use,
// a plain gray road, and the cat picture at z = 0, so the shots show how the
// scenery frames the run.

import SceneKit
import AppKit

@main
struct PreviewScenery {
    static let bend = """
    float4 wp = scn_node.modelTransform * _geometry.position;
    float d = max(0.0, -wp.z - 8.0);
    wp.y -= 0.0016 * d * d;
    _geometry.position = scn_node.inverseModelTransform * wp;
    """

    /// Suggested sky and fog colors per world (sRGB hex).
    static let sky: [WorldKind: (sky: UInt32, fog: UInt32)] = [
        .city: (0x8FD3FF, 0xCBEBFF),
        .jungle: (0x9FE3D0, 0xBFEBC8),
        .house: (0xFFF1DC, 0xF6E4CC),
        .farm: (0x92D6FF, 0xD4F0FF),
    ]

    static func color(_ h: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
                blue: CGFloat(h & 255) / 255, alpha: 1)
    }

    static func main() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                          : NSTemporaryDirectory() + "catcart_preview")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var t0 = Date()
        let lib = SceneryLibrary(searchDirectory: root.appendingPathComponent("CatCart/Models"))
        print(String(format: "library: %d models in %.0f ms", lib.models.count, -t0.timeIntervalSinceNow * 1000))
        lib.material.shaderModifiers = [.geometry: bend]

        let playerURL = root.appendingPathComponent("CatCart/Assets.xcassets/playerBack.imageset/playerBack.png")
        let player = NSImage(contentsOf: playerURL)

        let only = ProcessInfo.processInfo.environment["WORLD"]
        let seedBase = Int(ProcessInfo.processInfo.environment["SEED"] ?? "0") ?? 0
        for world in WorldKind.allCases {
            if let only = only, only != "\(world)" { continue }
            let scene = SCNScene()
            let (skyHex, fogHex) = sky[world]!
            scene.background.contents = color(skyHex)
            scene.fogStartDistance = 35
            scene.fogEndDistance = 120
            scene.fogColor = color(fogHex)

            var tris = 0
            t0 = Date()
            for i in -1..<6 {
                let seg = lib.dressing(for: world, length: 24, seed: seedBase + i + 1)
                seg.position = SCNVector3(0, 0, CGFloat(-24 * i))
                tris = max(tris, seg.geometry!.elements[0].primitiveCount)
                scene.rootNode.addChildNode(seg)
            }
            let ms = -t0.timeIntervalSinceNow * 1000 / 7

            // Road: plain dark strip, |x| <= 3.
            // Split along z so the bend can curve it (the bend moves vertices).
            let roadBox = SCNBox(width: 6, height: 0.02, length: 200, chamferRadius: 0)
            roadBox.lengthSegmentCount = 100
            let road = SCNNode(geometry: roadBox)
            road.position = SCNVector3(0, 0, -80)
            let roadMat = SCNMaterial()
            roadMat.diffuse.contents = world == .house ? color(0x6B7FA8) : color(0x55585F)
            roadMat.lightingModel = .lambert
            roadMat.shaderModifiers = [.geometry: bend]
            road.geometry!.materials = [roadMat]
            scene.rootNode.addChildNode(road)

            // The cat, a flat picture at z = 0, 1.4 m wide, bottom on the ground.
            if let img = player {
                let w: CGFloat = 1.4
                let h = w * img.size.height / img.size.width
                let plane = SCNPlane(width: w, height: h)
                let m = SCNMaterial()
                m.diffuse.contents = img
                m.lightingModel = .constant
                m.shaderModifiers = [.geometry: bend]
                plane.materials = [m]
                let n = SCNNode(geometry: plane)
                n.position = SCNVector3(0, h / 2, 0)
                scene.rootNode.addChildNode(n)
            }

            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera!.fieldOfView = 52
            cam.camera!.projectionDirection = .horizontal
            cam.camera!.zNear = 0.1
            cam.camera!.zFar = 200
            cam.position = SCNVector3(0, 3.6, 6.8)
            cam.look(at: SCNVector3(0, 0.4, -10))
            scene.rootNode.addChildNode(cam)

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light!.type = .directional
            sun.light!.color = color(0xFFF1D6)
            sun.light!.intensity = 1000
            sun.light!.castsShadow = true
            sun.light!.shadowMode = .deferred
            sun.light!.shadowColor = NSColor(white: 0, alpha: 0.3)
            sun.light!.orthographicScale = 40
            sun.light!.automaticallyAdjustsShadowProjection = true
            sun.eulerAngles = SCNVector3(-0.95, 0.55, 0)
            scene.rootNode.addChildNode(sun)
            let amb = SCNNode()
            amb.light = SCNLight()
            amb.light!.type = .ambient
            amb.light!.intensity = 520
            amb.light!.color = color(0xEAF2FF)
            scene.rootNode.addChildNode(amb)

            let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            r.scene = scene
            r.pointOfView = cam
            let img = r.snapshot(atTime: 0, with: CGSize(width: 1179, height: 2556), antialiasingMode: .multisampling4X)
            let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
            let url = outDir.appendingPathComponent("preview_\(world).png")
            try! rep.representation(using: .png, properties: [:])!.write(to: url)
            print(String(format: "%@: max %d triangles per segment, %.1f ms per segment -> %@",
                         "\(world)", tris, ms, url.path))
        }
    }
}
