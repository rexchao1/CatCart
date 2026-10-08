// Turns the kitten export (scripts/blender/export_kitten.py) into
// CatCart/Models/cat_kitten.scn. scripts/build_kitten.sh runs both steps:
//
//   swiftc -O -o /tmp/build_kitten scripts/build_kitten.swift
//   /tmp/build_kitten /tmp/kitten/kitten.json CatCart/Models/cat_kitten.scn
//
// What it does:
// - Rebuilds the tree the game animates: kitten > body > head > (earL, earR,
//   eyeL, eyeR), body > tail > tailTip. Each node's position is its joint, so
//   turning or scaling it moves the part around the joint.
// - Gives every material its in-game look by name (plain lambert and blinn
//   colors, so nothing depends on an importer), with the iris picture and the
//   coat grain embedded in the file.
// - Grows the fur. See "Shell fur" below.
//
// Coat colors arrive as vertex colors (painted in Blender, darkened in creases),
// and SceneKit multiplies them into the coat's diffuse.

import AppKit
import SceneKit

struct Part: Decodable { let name: String; let parent: String?; let position: [Float] }
struct Group: Decodable {
    let part: String
    let material: String
    let vertices: [Float]
    let normals: [Float]
    let colors: [Float]
    let uv: [Float]
    let fur: [Float]
    /// Which way the fur lies along the surface, one direction per vertex.
    let comb: [Float]
    let indices: [UInt32]
}
struct Export: Decodable { let parts: [Part]; let groups: [Group]; let textures: [String: String] }

let args = CommandLine.arguments
precondition(args.count == 3, "usage: build_kitten kitten.json cat_kitten.scn")
let input = URL(fileURLWithPath: args[1])
let export = try JSONDecoder().decode(Export.self, from: Data(contentsOf: input))

func picture(_ key: String) -> NSImage {
    let url = input.deletingLastPathComponent().appendingPathComponent(export.textures[key]!)
    guard let image = NSImage(contentsOf: url) else { fatalError("missing picture \(url.path)") }
    return image   // an NSImage is embedded in the SceneKit archive
}
let iris = picture("iris")
let grain = picture("grain")

func nscolor(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255,
            blue: CGFloat(h & 255) / 255, alpha: 1)
}

// MARK: - Shell fur
//
// Real-time fur the way most games do short fur: the coat is drawn once as the
// skin, then `furShells` more times, each copy pushed out along the surface a
// little further, up to `furDepth` times the painted fur length (long on her
// cheeks and chest, short on her face and paws), and combed over the way her
// fur lies.
//
// Each copy throws most of its pixels away. A fine grid is laid over the coat
// (its texture coordinates are meters across the kitten) and every cell is one
// tuft with a random height. A copy keeps only the middle of the tufts that
// reach it, smaller the higher it is, so tufts taper to points. Lower copies
// are darker, because light doesn't reach the roots, and the edges facing
// away from the camera glow a little, like light caught in fur.
// Together they make a soft coat with a fuzzy outline, where one smooth
// surface looked like a marshmallow.

/// How many copies over the skin. More is softer and costs a draw per part each.
let furShells = 8
/// How far the top copy stands off the skin where the fur length is 1 (meters,
/// before the cart's 1.25 scale).
let furDepth: Float = 0.017
/// How far the fur leans the way it lies (down her back, back from her nose),
/// for each meter it stands up. Cat fur lies down; it doesn't stand like a brush.
let furComb: Float = 0.9
/// Tufts per meter across the coat.
let furDensity: Float = 320

func furShader(level: Float) -> String {
    """
    #pragma body
    float furLevel = \(level);
    float2 furUV = _surface.diffuseTexcoord * \(furDensity);
    float2 furCell = floor(furUV);
    float2 furIn = fract(furUV);
    // Two small hashes of the cell: its tuft's height, and where in the cell it grows.
    float3 furP = fract(float3(furCell.xyx) * 0.1031);
    furP += dot(furP, furP.yzx + 33.33);
    float furH = fract((furP.x + furP.y) * furP.z);
    float3 furQ = fract(float3(furCell.xyx + 17.17) * float3(0.1031, 0.1030, 0.0973));
    furQ += dot(furQ, furQ.yzx + 33.33);
    float2 furAt = fract((furQ.xx + furQ.yz) * furQ.zy);
    float furD = length(furIn - (0.3 + 0.4 * furAt));
    // Far away a tuft is smaller than a pixel: fatten them so the coat doesn't sparkle.
    float furFar = saturate((fwidth(furUV.x) + fwidth(furUV.y)) * 0.8 - 0.4);
    float furR = mix(0.64 * (1.0 - 0.75 * furLevel * furLevel), 0.72, furFar);
    if (furLevel > 0.0 && (furH < furLevel * 0.92 || furD > furR)) {
        discard_fragment();
    }
    _surface.diffuse.rgb *= (0.76 + 0.36 * furLevel) * (0.94 + 0.12 * furH);
    float furRim = 1.0 - saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
    _surface.emission.rgb += _surface.diffuse.rgb * (furRim * furRim * furRim) * (0.1 + 0.28 * furLevel);
    """
}

func coatMaterial(level: Float, name: String) -> SCNMaterial {
    let m = SCNMaterial()
    m.name = name
    m.lightingModel = .lambert
    m.diffuse.contents = grain
    m.diffuse.wrapS = .repeat
    m.diffuse.wrapT = .repeat
    m.diffuse.mipFilter = .linear
    m.shaderModifiers = [.surface: furShader(level: level)]
    return m
}

// MARK: - Materials

func makeMaterial(_ name: String) -> SCNMaterial {
    let m = SCNMaterial()
    m.name = name
    m.lightingModel = .lambert
    switch name {
    case "kittenCoat": return coatMaterial(level: 0, name: name)
    case "kittenEarInner": m.diffuse.contents = nscolor(0xD49FA9)
    case "kittenNose":
        // A wet little nose: lilac pink with a soft shine.
        m.lightingModel = .blinn
        m.diffuse.contents = nscolor(0xC08A96)
        m.specular.contents = NSColor(white: 0.45, alpha: 1)
        m.shininess = 0.5
    case "kittenMouth": m.diffuse.contents = nscolor(0x5E4C55)
    case "kittenCrease": m.diffuse.contents = nscolor(0x7A727A)
    case "kittenWhisker": m.diffuse.contents = nscolor(0xF4F1EC)
    case "kittenEye":
        // The painted iris, glossy like a wet eye, and lit a little from
        // inside so the gold stays warm in shade.
        m.lightingModel = .blinn
        m.diffuse.contents = iris
        m.diffuse.mipFilter = .linear
        m.emission.contents = iris
        m.emission.intensity = 0.32
        m.specular.contents = NSColor(white: 0.85, alpha: 1)
        m.shininess = 0.9
    case "kittenShine":
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
    case "kittenCollar": m.diffuse.contents = nscolor(0xFF7A12)
    case "kittenCollarStitch": m.diffuse.contents = nscolor(0xFFE6B8)
    case "kittenBell":
        m.lightingModel = .blinn
        m.diffuse.contents = nscolor(0xE8B63A)
        m.emission.contents = nscolor(0x3C2C08)
        m.specular.contents = NSColor(white: 0.7, alpha: 1)
        m.shininess = 0.6
    case "kittenBellSlit": m.diffuse.contents = nscolor(0x3A2A10)
    default:
        print("WARNING: no look for material \(name)")
        m.diffuse.contents = NSColor.magenta
    }
    return m
}

// MARK: - Geometry

func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
    let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
    return SCNGeometrySource(data: data, semantic: semantic, vectorCount: values.count / components,
                             usesFloatComponents: true, componentsPerVector: components,
                             bytesPerComponent: 4, dataOffset: 0, dataStride: components * 4)
}

func element(_ indices: [UInt32]) -> SCNGeometryElement {
    let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
    return SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: indices.count / 3,
                              bytesPerIndex: 4)
}

/// One geometry from several groups: their vertices end to end, one element
/// (and material) per group.
func geometry(_ groups: [Group], materials: [SCNMaterial]) -> SCNGeometry {
    var v = [Float](), n = [Float](), c = [Float](), t = [Float]()
    var elements = [SCNGeometryElement]()
    for g in groups {
        let base = UInt32(v.count / 3)
        v += g.vertices; n += g.normals; c += g.colors; t += g.uv
        elements.append(element(g.indices.map { $0 + base }))
    }
    let geo = SCNGeometry(sources: [source(v, .vertex, 3), source(n, .normal, 3), source(c, .color, 4),
                                    source(t, .texcoord, 2)], elements: elements)
    geo.materials = materials
    return geo
}

/// One material per shell, shared by every part's fur.
let furMaterials = (1...furShells).map { shell in
    coatMaterial(level: Float(shell) / Float(furShells), name: "kittenFur\(shell)")
}

/// The fur over one part's coat: `furShells` copies of it, each pushed out along
/// its normals by its share of the fur depth, each with its own level.
func furGeometry(_ coat: Group) -> SCNGeometry {
    var v = [Float](), n = [Float](), c = [Float](), t = [Float]()
    var elements = [SCNGeometryElement]()
    let count = coat.vertices.count / 3
    for shell in 1...furShells {
        let level = Float(shell) / Float(furShells)
        let base = UInt32(v.count / 3)
        for i in 0..<count {
            // Out from the skin, and leaning along the fur more the further out it is.
            let push = furDepth * coat.fur[i] * level
            let lean = push * furComb * level
            for k in 0..<3 {
                v.append(coat.vertices[i * 3 + k] + coat.normals[i * 3 + k] * push + coat.comb[i * 3 + k] * lean)
            }
        }
        n += coat.normals; c += coat.colors; t += coat.uv
        elements.append(element(coat.indices.map { $0 + base }))
    }
    let geo = SCNGeometry(sources: [source(v, .vertex, 3), source(n, .normal, 3), source(c, .color, 4),
                                    source(t, .texcoord, 2)], elements: elements)
    geo.materials = furMaterials
    return geo
}

// MARK: - Build

var nodes = [String: SCNNode]()
let scene = SCNScene()
for p in export.parts {
    let node = SCNNode()
    node.name = p.name
    node.position = SCNVector3(p.position[0], p.position[1], p.position[2])
    nodes[p.name] = node
    if let parent = p.parent { nodes[parent]!.addChildNode(node) } else { scene.rootNode.addChildNode(node) }
}

var triangles = 0, furTriangles = 0
var materialCache = [String: SCNMaterial]()
for (part, groups) in Dictionary(grouping: export.groups, by: \.part) {
    let node = nodes[part]!
    let mats = groups.map { g -> SCNMaterial in
        if let m = materialCache[g.material] { return m }
        let m = makeMaterial(g.material)
        materialCache[g.material] = m
        return m
    }
    node.geometry = geometry(groups, materials: mats)
    node.geometry?.name = part
    triangles += groups.reduce(0) { $0 + $1.indices.count / 3 }
    if let coat = groups.first(where: { $0.material == "kittenCoat" }) {
        let fur = SCNNode(geometry: furGeometry(coat))
        fur.name = "fur"
        fur.castsShadow = false
        node.addChildNode(fur)
        furTriangles += coat.indices.count / 3 * furShells
    }
}

let kitten = nodes["kitten"]!
var lo = SCNVector3(1e9, 1e9, 1e9), hi = SCNVector3(-1e9, -1e9, -1e9)
kitten.enumerateHierarchy { n, _ in
    guard let g = n.geometry, n.name != "fur" else { return }
    let (a, b) = g.boundingBox
    for corner in [a, b] {
        let w = n.convertPosition(corner, to: nil)
        lo = SCNVector3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
        hi = SCNVector3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
    }
}
print("bounds min \(lo) max \(hi)")
kitten.enumerateHierarchy { n, _ in
    if let name = n.name, name != "fur" { print("  \(name) at \(n.worldPosition)") }
}
print("triangles \(triangles), fur shells \(furTriangles)")

let output = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: output)
precondition(scene.write(to: output, options: nil, delegate: nil, progressHandler: nil), "write failed")
let restored = try SCNScene(url: output, options: nil)
precondition(restored.rootNode.childNode(withName: "kitten", recursively: false) != nil, "no kitten in \(output.path)")
var restoredFur = 0
restored.rootNode.enumerateHierarchy { n, _ in
    for m in n.geometry?.materials ?? [] where m.shaderModifiers?[.surface] != nil { restoredFur += 1 }
}
precondition(restoredFur > furShells, "the fur shaders didn't survive the save")
print("wrote \(output.path)")
