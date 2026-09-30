// Offscreen preview of the 3D coyote (CatCart/Models/coyote_run.scn) on macOS.
//
//   swiftc -O -o /tmp/preview_coyote scripts/preview_coyote.swift
//   /tmp/preview_coyote [output-dir]
//
// Writes:
//   coyote_game.png   game camera, coyote at z = -8 in the middle lane, 1179x2556
//   coyote_34.png     close three-quarter front view
//   coyote_side.png   side view at four times across the 0.45 s stride (left to right)
//   coyote_clones.png six clones, to check clones animate too
// and prints the animation keys it found plus the jaw angle over time for the
// original and a clone, so you can see the pose really changes.

import AppKit
import SceneKit

func color(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: 1)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                  : NSTemporaryDirectory() + "coyote_preview")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let file = try! SCNScene(url: root.appendingPathComponent("CatCart/Models/coyote_run.scn"), options: nil)
let coyote = file.rootNode.childNode(withName: "coyote", recursively: false)!

var tris = 0
var animated: [String] = []
coyote.enumerateHierarchy { node, _ in
    tris += node.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0
    for key in node.animationKeys where node.animationPlayer(forKey: key) != nil {
        animated.append("\(node.name ?? "?").\(key)")
    }
}
let (lo, hi) = coyote.boundingBox
print("triangles: \(tris)")
print(String(format: "bounds: x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f", lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
print("animation players (\(animated.count)): \(animated.sorted().joined(separator: " "))")

/// A little world: ground, sky color, warm sun with shadows, ambient.
func stage() -> SCNScene {
    let s = SCNScene()
    s.background.contents = color(0x9ED8FF)
    let ground = SCNNode(geometry: SCNBox(width: 60, height: 0.1, length: 200, chamferRadius: 0))
    ground.geometry!.firstMaterial!.diffuse.contents = color(0x9C9A92)
    ground.geometry!.firstMaterial!.lightingModel = .lambert
    ground.position = SCNVector3(0, -0.05, -80)
    s.rootNode.addChildNode(ground)
    for x in [-1.1, 1.1] {   // lane lines
        let l = SCNNode(geometry: SCNBox(width: 0.06, height: 0.01, length: 200, chamferRadius: 0))
        l.geometry!.firstMaterial!.diffuse.contents = color(0xD8D2C4)
        l.position = SCNVector3(x, 0.005, -80)
        s.rootNode.addChildNode(l)
    }
    let sun = SCNLight()
    sun.type = .directional
    sun.color = NSColor(srgbRed: 1.0, green: 0.93, blue: 0.82, alpha: 1)
    sun.castsShadow = true
    sun.shadowMode = .deferred
    sun.shadowColor = NSColor(white: 0, alpha: 0.32)
    sun.shadowRadius = 2
    sun.shadowSampleCount = 4
    sun.shadowMapSize = CGSize(width: 2048, height: 2048)
    let sunNode = SCNNode()
    sunNode.light = sun
    sunNode.eulerAngles = SCNVector3(-0.95, 0.55, 0)
    s.rootNode.addChildNode(sunNode)
    let amb = SCNLight()
    amb.type = .ambient
    amb.color = NSColor(srgbRed: 0.62, green: 0.60, blue: 0.66, alpha: 1)
    let ambNode = SCNNode()
    ambNode.light = amb
    s.rootNode.addChildNode(ambNode)
    return s
}

func camera(_ s: SCNScene, pos: SCNVector3, look: SCNVector3, fov: CGFloat) -> SCNNode {
    let cam = SCNCamera()
    cam.projectionDirection = .horizontal
    cam.fieldOfView = fov
    cam.zNear = 0.1
    cam.zFar = 260
    let n = SCNNode()
    n.camera = cam
    n.position = pos
    n.look(at: look)
    s.rootNode.addChildNode(n)
    return n
}

let device = MTLCreateSystemDefaultDevice()!
func render(_ s: SCNScene, _ cam: SCNNode, size: CGSize, time: TimeInterval) -> NSImage {
    let r = SCNRenderer(device: device, options: nil)
    r.scene = s
    r.pointOfView = cam
    r.autoenablesDefaultLighting = false
    // Animations start at the first frame a renderer draws, so draw once at t = 0.
    _ = r.snapshot(atTime: 0, with: CGSize(width: 16, height: 16), antialiasingMode: .none)
    return r.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
}
func save(_ img: NSImage, _ name: String) {
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote \(outDir.appendingPathComponent(name).path)")
}
func strip(_ imgs: [NSImage]) -> NSImage {
    let w = imgs[0].size.width, h = imgs[0].size.height
    let out = NSImage(size: NSSize(width: w * CGFloat(imgs.count), height: h))
    out.lockFocus()
    for (i, im) in imgs.enumerated() { im.draw(in: NSRect(x: w * CGFloat(i), y: 0, width: w, height: h)) }
    out.unlockFocus()
    return out
}

// 1. Game camera.
do {
    let s = stage()
    let c = coyote.clone()
    c.position = SCNVector3(0, 0, -8)
    s.rootNode.addChildNode(c)
    let cam = camera(s, pos: SCNVector3(0, 2.9, 4.4), look: SCNVector3(0, 0.4, -10), fov: 56)
    save(render(s, cam, size: CGSize(width: 1179, height: 2556), time: 0.12), "coyote_game.png")
}
// 2. Close three-quarter front.
do {
    let s = stage()
    s.rootNode.addChildNode(coyote.clone())
    let cam = camera(s, pos: SCNVector3(1.5, 1.35, 2.6), look: SCNVector3(0, 0.62, 0), fov: 42)
    save(render(s, cam, size: CGSize(width: 1000, height: 1000), time: 0.12), "coyote_34.png")
}
// 3. Side view across the stride.
do {
    let s = stage()
    s.rootNode.addChildNode(coyote.clone())
    let cam = camera(s, pos: SCNVector3(3.4, 0.75, -0.1), look: SCNVector3(0, 0.6, -0.1), fov: 42)
    let times = (0..<4).map { 0.45 * Double($0) / 4 }
    save(strip(times.map { render(s, cam, size: CGSize(width: 700, height: 600), time: $0) }), "coyote_side.png")
}
// 4. Six clones, plus a numeric check that the original and a clone both move.
do {
    let s = stage()
    var clones: [SCNNode] = []
    for i in 0..<6 {
        let c = coyote.clone()
        c.position = SCNVector3(Float(i % 3 - 1) * 2.2, 0, -Float(i / 3) * 5)
        s.rootNode.addChildNode(c)
        clones.append(c)
    }
    let cam = camera(s, pos: SCNVector3(0, 2.9, 7), look: SCNVector3(0, 0.4, -4), fov: 56)
    save(render(s, cam, size: CGSize(width: 1000, height: 1000), time: 0.2), "coyote_clones.png")

    let r = SCNRenderer(device: device, options: nil)
    r.scene = s
    r.pointOfView = cam
    for t in stride(from: 0.0, through: 0.45, by: 0.075) {
        _ = r.snapshot(atTime: t, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        let a = clones[0].childNode(withName: "jaw", recursively: true)!.presentation.eulerAngles.x
        let b = clones[5].childNode(withName: "frontUpperL", recursively: true)!.presentation.eulerAngles.x
        print(String(format: "t=%.3f  clone0 jaw %.2f rad   clone5 front leg %.2f rad", t, a, b))
    }
}
