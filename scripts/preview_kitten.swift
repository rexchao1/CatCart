// Offscreen preview of the 3D kitten (CatCart/Models/cat_kitten.scn) in a
// stand-in light-blue box, on macOS.
//
//   swiftc -O -o /tmp/preview_kitten scripts/preview_kitten.swift
//   /tmp/preview_kitten [output-dir]
//
// Writes kitten_game.png (the run camera, behind and above), kitten_front.png
// (home screen 3/4 front), kitten_face.png (close on her face), and kitten_side.png.

import SceneKit
import AppKit

func color(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: 1)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                  : NSTemporaryDirectory() + "catcart_kitten")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let scene = SCNScene()
scene.background.contents = color(0x9FD8FF)

let kittenScene = try SCNScene(url: root.appendingPathComponent("CatCart/Models/cat_kitten.scn"), options: nil)
let kitten = kittenScene.rootNode.childNode(withName: "kitten", recursively: true)!
kitten.removeFromParentNode()
scene.rootNode.addChildNode(kitten)

// Open-top box: 1.3 wide, 0.95 deep, 0.5 tall, bottom at y = -0.08.
let boxMat = SCNMaterial()
boxMat.diffuse.contents = color(0x8CCBF0)
boxMat.lightingModel = .lambert
let t: CGFloat = 0.035, w: CGFloat = 1.3, d: CGFloat = 0.95, hgt: CGFloat = 0.5, y0: CGFloat = -0.08
func slab(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat, _ p: SCNVector3) {
    let b = SCNBox(width: sx, height: sy, length: sz, chamferRadius: 0.01)
    b.materials = [boxMat]
    let n = SCNNode(geometry: b)
    n.position = p
    scene.rootNode.addChildNode(n)
}
slab(w, t, d, SCNVector3(0, y0 + t / 2, 0))
slab(w, hgt, t, SCNVector3(0, y0 + hgt / 2, -d / 2 + t / 2))
slab(w, hgt, t, SCNVector3(0, y0 + hgt / 2, d / 2 - t / 2))
slab(t, hgt, d, SCNVector3(-w / 2 + t / 2, y0 + hgt / 2, 0))
slab(t, hgt, d, SCNVector3(w / 2 - t / 2, y0 + hgt / 2, 0))

// Ground
let ground = SCNFloor()
ground.reflectivity = 0
let gm = SCNMaterial()
gm.diffuse.contents = color(0x8A8F96)
gm.lightingModel = .lambert
ground.materials = [gm]
let gn = SCNNode(geometry: ground)
gn.position = SCNVector3(0, -0.2, 0)
scene.rootNode.addChildNode(gn)

let sun = SCNNode()
sun.light = SCNLight()
sun.light!.type = .directional
sun.light!.color = color(0xFFF1D6)
sun.light!.intensity = 1000
sun.light!.castsShadow = true
sun.light!.shadowColor = NSColor(white: 0, alpha: 0.3)
sun.light!.orthographicScale = 3
sun.eulerAngles = SCNVector3(-0.95, 0.55, 0)
scene.rootNode.addChildNode(sun)
let amb = SCNNode()
amb.light = SCNLight()
amb.light!.type = .ambient
amb.light!.intensity = 520
amb.light!.color = color(0xEAF2FF)
scene.rootNode.addChildNode(amb)

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene

func shot(_ name: String, from: SCNVector3, at: SCNVector3, fov: CGFloat, size: CGSize) {
    let cam = SCNNode()
    cam.camera = SCNCamera()
    cam.camera!.fieldOfView = fov
    cam.camera!.projectionDirection = .horizontal
    cam.camera!.zNear = 0.05
    cam.camera!.zFar = 100
    cam.position = from
    cam.look(at: at)
    scene.rootNode.addChildNode(cam)
    renderer.pointOfView = cam
    let img = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    cam.removeFromParentNode()
    print(url.path)
}

let portrait = CGSize(width: 1179, height: 2556)
shot("kitten_game.png", from: SCNVector3(0, 2.6, 4.0), at: SCNVector3(0, 0.5, -3), fov: 56, size: portrait)
shot("kitten_front.png", from: SCNVector3(1.2, 1.1, -2.6), at: SCNVector3(0, 0.55, 0), fov: 30, size: portrait)
shot("kitten_face.png", from: SCNVector3(0.4, 0.95, -1.55), at: SCNVector3(0, 0.76, -0.1), fov: 24, size: CGSize(width: 1200, height: 1200))
shot("kitten_side.png", from: SCNVector3(3.2, 0.5, 0), at: SCNVector3(0, 0.45, 0), fov: 30, size: CGSize(width: 1200, height: 1200))
