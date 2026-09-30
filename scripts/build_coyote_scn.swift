// Turns the coyote JSON from scripts/blender/make_coyote.py into a SceneKit archive
// with the gallop baked in as looping keyframe animations.
//
//   swift scripts/build_coyote_scn.swift coyote_run.json CatCart/Models/coyote_run.scn
//
// Node tree (all rigid, pivots at the joints):
//   coyote > body > head > jaw, eyes
//                 > frontUpperL/R > frontLowerL/R
//                 > hindUpperL/R  > hindLowerL/R
//                 > tail1 > tail2 > tail3
// Every animated node gets one CAAnimationGroup under the key "run" (position +
// orientation, 0.45 s, repeats forever). They are saved in the .scn, so they play as
// soon as the node is in a scene, and clone() copies them.

import Foundation
import SceneKit

struct Part: Decodable {
    let name: String
    let parent: String?
    let material: String
    let position: [Float]
    let vertices: [Float]?
    let normals: [Float]?
    let colors: [Float]?
    let indices: [UInt32]?
}
struct Track: Decodable { let position: [[Float]]; let orientation: [[Float]] }
struct Rig: Decodable {
    let fps: Int
    let frames: Int
    let duration: Double
    let parts: [Part]
    let anim: [String: Track]
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: build_coyote_scn in.json out.scn"); exit(1) }
let rig = try JSONDecoder().decode(Rig.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))

// Same idea as the scenery: white lambert, the colors live in the vertices.
let coat = SCNMaterial()
coat.name = "coyote"
coat.lightingModel = .lambert
coat.diffuse.contents = NSColor.white
// The eyes glow a little so the amber reads from far down the road.
let eyes = SCNMaterial()
eyes.name = "coyoteEyes"
eyes.lightingModel = .lambert
eyes.diffuse.contents = NSColor.white
eyes.emission.contents = NSColor(srgbRed: 0.75, green: 0.45, blue: 0.02, alpha: 1)

func geometry(_ p: Part) -> SCNGeometry? {
    guard let v = p.vertices, let n = p.normals, let c = p.colors, let idx = p.indices else { return nil }
    func source(_ a: [Float], _ sem: SCNGeometrySource.Semantic, _ comps: Int) -> SCNGeometrySource {
        let d = a.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: d, semantic: sem, vectorCount: a.count / comps, usesFloatComponents: true,
                                 componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0,
                                 dataStride: comps * 4)
    }
    let id = idx.withUnsafeBufferPointer { Data(buffer: $0) }
    let el = SCNGeometryElement(data: id, primitiveType: .triangles, primitiveCount: idx.count / 3, bytesPerIndex: 4)
    let g = SCNGeometry(sources: [source(v, .vertex, 3), source(n, .normal, 3), source(c, .color, 4)], elements: [el])
    g.name = p.name
    g.materials = [p.material == "eyes" ? eyes : coat]
    return g
}

var nodes: [String: SCNNode] = [:]
var root: SCNNode!
for p in rig.parts {
    let node = SCNNode()
    node.name = p.name
    node.geometry = geometry(p)
    node.position = SCNVector3(p.position[0], p.position[1], p.position[2])
    nodes[p.name] = node
    if let parent = p.parent { nodes[parent]!.addChildNode(node) } else { root = node }
}

let n = rig.frames
let keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
for (name, track) in rig.anim {
    let pos = CAKeyframeAnimation(keyPath: "position")
    pos.values = track.position.map { NSValue(scnVector3: SCNVector3($0[0], $0[1], $0[2])) }
    let rot = CAKeyframeAnimation(keyPath: "orientation")
    rot.values = track.orientation.map { NSValue(scnVector4: SCNVector4($0[0], $0[1], $0[2], $0[3])) }
    for a in [pos, rot] { a.keyTimes = keyTimes; a.calculationMode = .linear; a.duration = rig.duration }
    let g = CAAnimationGroup()
    g.animations = [pos, rot]
    g.duration = rig.duration
    g.repeatCount = .infinity
    g.isRemovedOnCompletion = false
    nodes[name]!.addAnimation(g, forKey: "run")
}

let scene = SCNScene()
scene.rootNode.addChildNode(root)
let out = URL(fileURLWithPath: args[2])
guard scene.write(to: out, options: nil, delegate: nil, progressHandler: nil) else {
    print("write failed"); exit(1)
}
var tris = 0
root.enumerateHierarchy { node, _ in tris += node.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0 }
print("wrote \(out.path): \(nodes.count) nodes, \(tris) triangles, \(rig.anim.count) animated, \(rig.duration)s loop")
