// Turns the Blender export of the kitten into CatCart/Models/cat_kitten.scn.
//
//   /Applications/Blender.app/Contents/MacOS/Blender -b art/models/kitten/cat.blend \
//       --python scripts/blender/export_kitten.py -- /tmp/cat_kitten.usdc
//   swiftc -O -o /tmp/build_kitten scripts/build_kitten.swift
//   /tmp/build_kitten /tmp/cat_kitten.usdc CatCart/Models/cat_kitten.scn
//
// What it does:
// - Blender writes Z-up coordinates. SceneKit is Y-up and the kitten must face
//   -Z, so every position and normal goes (x, y, z) -> (x, z, -y).
// - Rebuilds a clean tree: kitten > body > head > (earL, earR, eyeL, eyeR),
//   body > tail > tailTip. Each named node carries its own geometry, and its
//   position is its joint, so rotating or scaling it animates around the joint.
// - Replaces the imported PBR materials with plain lambert/blinn colors, by
//   material name, so the look does not depend on the USD importer.
// - Paints the coat with vertex colors: lighter lilac-gray on the face front
//   and chest, darker on the back, top of the head, and the tail.
//   Vertex colors multiply the (white) coat diffuse. Non-coat parts get white.
//
// The old cartoon kitten (scripts/blender/make_cat.py) used the same material
// names, so either Blender script feeds this one.

import SceneKit
import AppKit

/// sRGB hex -> linear RGB (SceneKit reads vertex colors as linear).
func rgb(_ h: UInt32) -> SIMD3<Float> {
    func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
    return SIMD3(lin(Float((h >> 16) & 255) / 255), lin(Float((h >> 8) & 255) / 255), lin(Float(h & 255) / 255))
}
func nscolor(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: 1)
}
func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}
func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

// Coat palette (sRGB). Base is the study's warm dove gray, brighter than the
// render because the game's lights are flatter than Blender's studio.
let coatBase = rgb(0xA19DA2)
let coatLight = rgb(0xC4C0C6)   // face front and chest, faint lilac
let coatDark = rgb(0x86828A)    // back, crown, tail

func makeMaterial(_ name: String) -> SCNMaterial {
    let m = SCNMaterial()
    m.name = name
    m.lightingModel = .lambert
    switch name {
    case "kittenCoat": m.diffuse.contents = NSColor.white   // vertex colors carry the coat
    case "kittenMuzzle": m.diffuse.contents = nscolor(0xC6C4D2)
    case "kittenEarInner": m.diffuse.contents = nscolor(0xC39CA4)
    case "kittenNose": m.diffuse.contents = nscolor(0x6E5A62)
    case "kittenMouth": m.diffuse.contents = nscolor(0x3A3236)
    case "kittenWhisker":
        m.diffuse.contents = nscolor(0xECE8E2)
    case "kittenIris":
        m.lightingModel = .blinn
        m.diffuse.contents = nscolor(0xD2A846)
        m.emission.contents = nscolor(0x3C2C08)   // keeps the gold warm in shade
        m.specular.contents = NSColor(white: 0.5, alpha: 1)
        m.shininess = 0.6
    case "kittenPupil":
        m.lightingModel = .blinn
        m.diffuse.contents = nscolor(0x1A161E)
        m.specular.contents = NSColor(white: 0.6, alpha: 1)
        m.shininess = 0.7
    case "kittenShine":
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
    default: m.diffuse.contents = NSColor.magenta
    }
    return m
}

func readVec3(_ s: SCNGeometrySource) -> [SIMD3<Float>] {
    precondition(s.usesFloatComponents && s.bytesPerComponent == 4)
    var out = [SIMD3<Float>]()
    out.reserveCapacity(s.vectorCount)
    s.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        for i in 0..<s.vectorCount {
            let o = s.dataOffset + i * s.dataStride
            out.append(SIMD3(raw.load(fromByteOffset: o, as: Float.self),
                             raw.load(fromByteOffset: o + 4, as: Float.self),
                             raw.load(fromByteOffset: o + 8, as: Float.self)))
        }
    }
    return out
}

func indices(_ e: SCNGeometryElement) -> [Int] {
    var out = [Int]()
    e.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let n = e.data.count / e.bytesPerIndex
        for i in 0..<n {
            switch e.bytesPerIndex {
            case 1: out.append(Int(raw.load(fromByteOffset: i, as: UInt8.self)))
            case 2: out.append(Int(raw.load(fromByteOffset: i * 2, as: UInt16.self)))
            default: out.append(Int(raw.load(fromByteOffset: i * 4, as: UInt32.self)))
            }
        }
    }
    return out
}

/// Triangle corners of an element, each as one index per channel.
/// The USD importer keeps polygons with two index channels, interleaved per
/// corner as (position, normal), because Blender writes face-varying normals.
func triangleCorners(_ e: SCNGeometryElement) -> [[Int]] {
    let all = indices(e)
    let ch = max(1, e.indicesChannelCount)
    func corner(_ k: Int, base: Int) -> [Int] { (0..<ch).map { all[base + k * ch + $0] } }
    switch e.primitiveType {
    case .triangles:
        return (0..<(all.count / ch)).map { corner($0, base: 0) }
    case .polygon:
        let counts = all[0..<e.primitiveCount]
        var at = 0
        var out = [[Int]]()
        let base = e.primitiveCount
        for c in counts {
            for k in 1..<(c - 1) {
                out += [corner(at, base: base), corner(at + k, base: base), corner(at + k + 1, base: base)]
            }
            at += c
        }
        return out
    default: fatalError("unsupported primitive type \(e.primitiveType)")
    }
}

/// Blender Z-up -> SceneKit Y-up, facing -Z.
func conv(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3(v.x, v.z, -v.y) }
func conv(_ v: SCNVector3) -> SCNVector3 { SCNVector3(v.x, v.z, -v.y) }

/// Coat shade for a point (SceneKit space, kitten root) with normal n.
func coatColor(part: String, p: SIMD3<Float>, n: SIMD3<Float>) -> SIMD3<Float> {
    var c = coatBase
    switch part {
    case "head", "earL", "earR":
        // front of the face lighter, crown and back of head darker
        let front = smooth(0.1, 0.8, -n.z)
        c = mix(c, coatDark, smooth(0.6, 1.0, n.y) * 0.35 + smooth(0.3, 1.0, n.z) * 0.25)
        c = mix(c, coatLight, front * 0.85)
    case "body":
        let front = smooth(0.0, 0.7, -n.z) * smooth(0.02, 0.2, p.y)
        let back = smooth(0.0, 0.8, n.z) * 0.6 + smooth(0.5, 1.0, n.y) * 0.3
        c = mix(c, coatDark, min(back, 1))
        c = mix(c, coatLight, front * 0.8)
    case "tail", "tailTip":
        c = mix(coatDark, coatBase, smooth(0.3, 1.0, n.y) * 0.4)
    default: break
    }
    // soft shade underneath, a cheap contact darkening
    c *= 1 - 0.18 * smooth(0.2, 1.0, -n.y)
    return c
}

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1])
let dst = URL(fileURLWithPath: args[2])
let imported = try SCNScene(url: src, options: nil)
guard let kittenIn = imported.rootNode.childNode(withName: "kitten", recursively: true) else {
    fatalError("no kitten node in \(src.path)")
}

var tris = 0

/// Rebuild one named node. `origin` is its world position (SceneKit space).
func rebuild(_ n: SCNNode, parentWorld: SIMD3<Float>) -> SCNNode {
    let out = SCNNode()
    out.name = n.name
    let world = conv(SIMD3<Float>(Float(n.worldPosition.x), Float(n.worldPosition.y), Float(n.worldPosition.z)))
    let local = world - parentWorld
    out.position = SCNVector3(local.x, local.y, local.z)
    for c in n.childNodes {
        if let g = c.geometry, c.name?.hasSuffix("Mesh") == true {
            // Mesh child: bake its vertices into this node's space (child is at 0).
            let rawV = readVec3(g.sources(for: .vertex)[0]).map(conv)
            let rawN = readVec3(g.sources(for: .normal)[0]).map { simd_normalize(conv($0)) }
            let mats = g.materials.map { $0.name ?? "" }
            // Weld (position, normal) pairs into single-index vertices.
            var vs = [SIMD3<Float>](), ns = [SIMD3<Float>](), colors = [SIMD3<Float>]()
            var seen = [[Int]: UInt32]()
            var elements = [SCNGeometryElement]()
            for (ei, e) in g.elements.enumerated() {
                let coat = mats[ei] == "kittenCoat"
                var idx = [UInt32]()
                for c in triangleCorners(e) {
                    let key = [c[0], c.count > 1 ? c[1] : c[0], coat ? 1 : 0]
                    if let i = seen[key] { idx.append(i); continue }
                    let p = rawV[c[0]], nn = rawN[c.count > 1 ? c[1] : c[0]]
                    let i = UInt32(vs.count)
                    vs.append(p); ns.append(nn)
                    colors.append(coat ? coatColor(part: n.name ?? "", p: p + world, n: nn) : SIMD3(1, 1, 1))
                    seen[key] = i
                    idx.append(i)
                }
                let el = SCNGeometryElement(indices: idx, primitiveType: .triangles)
                tris += el.primitiveCount
                elements.append(el)
            }
            let vsrc = SCNGeometrySource(vertices: vs.map { SCNVector3($0.x, $0.y, $0.z) })
            let nsrc = SCNGeometrySource(normals: ns.map { SCNVector3($0.x, $0.y, $0.z) })
            let cdata = colors.withUnsafeBufferPointer { buf -> Data in
                var d = Data()
                for c in buf { for f in [c.x, c.y, c.z, 1] { withUnsafeBytes(of: f) { d.append(contentsOf: $0) } } }
                return d
            }
            let csrc = SCNGeometrySource(data: cdata, semantic: .color, vectorCount: colors.count,
                                         usesFloatComponents: true, componentsPerVector: 4,
                                         bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let geo = SCNGeometry(sources: [vsrc, nsrc, csrc], elements: elements)
            geo.name = n.name
            geo.materials = mats.map(makeMaterial)
            out.geometry = geo
        } else if c.name != nil {
            out.addChildNode(rebuild(c, parentWorld: world))
        }
    }
    return out
}

let kitten = rebuild(kittenIn, parentWorld: SIMD3(0, 0, 0))
let scene = SCNScene()
scene.rootNode.addChildNode(kitten)

let (mn, mx) = kitten.boundingBox
func bbox(_ n: SCNNode) -> (SCNVector3, SCNVector3) {
    var lo = SCNVector3(1e9, 1e9, 1e9), hi = SCNVector3(-1e9, -1e9, -1e9)
    n.enumerateHierarchy { c, _ in
        guard let g = c.geometry else { return }
        let (a, b) = g.boundingBox
        for corner in [a, b] {
            let w = c.convertPosition(corner, to: nil)
            lo = SCNVector3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
            hi = SCNVector3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
        }
    }
    return (lo, hi)
}
_ = (mn, mx)
let (lo, hi) = bbox(kitten)
print("bounds min \(lo) max \(hi)")
kitten.enumerateHierarchy { c, _ in
    if let name = c.name { print("  \(name) at \(c.worldPosition)") }
}
print("triangles \(tris)")
try? FileManager.default.removeItem(at: dst)
let ok = scene.write(to: dst, options: nil, delegate: nil, progressHandler: nil)
print(ok ? "wrote \(dst.path)" : "WRITE FAILED")
