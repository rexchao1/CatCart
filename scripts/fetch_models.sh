#!/bin/bash
# Download the CC0 Kenney kits and bake the curated scenery models into
# CatCart/Models/scenery_<world>.scn.
#
# Why bake: the kits ship OBJ + MTL + a shared palette texture (colormap.png).
# Xcode copies every file under CatCart/ flat into the app bundle, so relative
# texture paths break and same-named textures collide. Instead we sample each
# model's colors into per-vertex colors, merge every model into one mesh with a
# single plain material, and save them as SceneKit archives. No textures ship.
# One mesh + one material per model means a whole road segment can be flattened
# into a single draw call.
#
# Usage: scripts/fetch_models.sh [download-dir]
# Needs macOS with Xcode command line tools (swiftc, SceneKit). No Blender.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${TMPDIR:-/tmp}/catcart_models_src}"
OUT="$ROOT/CatCart/Models"
mkdir -p "$SRC" "$OUT"

KITS="city-kit-commercial city-kit-suburban city-kit-roads nature-kit furniture-kit fantasy-town-kit"
for kit in $KITS; do
  if [[ ! -d "$SRC/$kit/Models" ]]; then
    echo "download $kit"
    # The zip URL has a hash in it that changes when Kenney updates a kit,
    # so read it off the asset page.
    url=$(curl -sL "https://kenney.nl/assets/$kit" | grep -oE 'https://kenney.nl/media/pages/assets/[^"]+\.zip' | head -1)
    [[ -n "$url" ]] || { echo "no zip link found for $kit"; exit 1; }
    curl -sL "$url" -o "$SRC/$kit.zip"
    mkdir -p "$SRC/$kit"
    unzip -qo "$SRC/$kit.zip" -d "$SRC/$kit"
  fi
done

BAKE="$SRC/bake_scenery"
cat > "$BAKE.swift" <<'SWIFT'
import SceneKit
import AppKit
import simd

let src = CommandLine.arguments[1]
let out = CommandLine.arguments[2]

// MARK: color helpers

func hex(_ h: UInt32) -> SIMD3<Float> {
    SIMD3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255
}

/// Push colors a bit away from gray so the kits read brighter on a phone.
func saturate(_ c: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
    let l = simd_dot(c, SIMD3(0.299, 0.587, 0.114))
    return simd_clamp(SIMD3(repeating: l) + (c - SIMD3(repeating: l)) * amount, .zero, .one)
}

func toLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
    func f(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return SIMD3(f(c.x), f(c.y), f(c.z))
}

final class Palette {
    let w: Int, h: Int
    var px: [UInt8]
    init(_ path: String) {
        let img = NSImage(contentsOfFile: path)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        w = img.width; h = img.height
        px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    func sample(_ uv: SIMD2<Float>) -> SIMD3<Float> {
        let x = min(w - 1, max(0, Int(uv.x * Float(w))))
        let y = min(h - 1, max(0, Int(uv.y * Float(h))))
        let i = (y * w + x) * 4
        return SIMD3(Float(px[i]), Float(px[i + 1]), Float(px[i + 2])) / 255
    }
}

// MARK: geometry reading

func floats(_ s: SCNGeometrySource) -> [SIMD4<Float>] {
    var r: [SIMD4<Float>] = []
    s.data.withUnsafeBytes { raw in
        for i in 0..<s.vectorCount {
            var v = SIMD4<Float>(0, 0, 0, 1)
            for c in 0..<s.componentsPerVector {
                let o = s.dataOffset + i * s.dataStride + c * s.bytesPerComponent
                v[c] = s.bytesPerComponent == 8 ? Float(raw.loadUnaligned(fromByteOffset: o, as: Double.self))
                                                : raw.loadUnaligned(fromByteOffset: o, as: Float.self)
            }
            r.append(v)
        }
    }
    return r
}

func indices(_ e: SCNGeometryElement) -> [Int] {
    var r: [Int] = []
    e.data.withUnsafeBytes { raw in
        let n = e.primitiveCount * 3
        for i in 0..<n {
            switch e.bytesPerIndex {
            case 1: r.append(Int(raw.load(fromByteOffset: i, as: UInt8.self)))
            case 2: r.append(Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
            default: r.append(Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
            }
        }
    }
    return r
}

struct VKey: Hashable { let p: SIMD3<Float>; let n: SIMD3<Float>; let c: SIMD3<Float> }

/// Bake one OBJ into a single vertex-colored geometry.
/// anchor "base": centered on x/z, sitting on y = 0. "center": centered on all axes.
func bake(_ path: String, palette: Palette?, remap: [String: UInt32], anchor: String) -> SCNGeometry {
    let scene = try! SCNScene(url: URL(fileURLWithPath: path), options: nil)
    var pos: [SIMD3<Float>] = [], nrm: [SIMD3<Float>] = [], col: [SIMD3<Float>] = []
    scene.rootNode.enumerateHierarchy { node, _ in
        guard let g = node.geometry else { return }
        let m = simd_float4x4(node.worldTransform)
        let nm = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                               SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                               SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)).inverse.transpose
        let P = floats(g.sources(for: .vertex)[0])
        let N = g.sources(for: .normal).first.map(floats)
        let T = g.sources(for: .texcoord).first.map(floats)
        for (ei, e) in g.elements.enumerated() {
            precondition(e.primitiveType == .triangles)
            let mat = g.materials[ei % g.materials.count]
            let name = mat.name ?? ""
            var flat = SIMD3<Float>(1, 1, 1)
            if let c = mat.diffuse.contents as? NSColor, let s = c.usingColorSpace(.sRGB) {
                flat = SIMD3(Float(s.redComponent), Float(s.greenComponent), Float(s.blueComponent))
            }
            if let h = remap[name] { flat = hex(h) }
            let textured = !(mat.diffuse.contents is NSColor) && palette != nil
            let idx = indices(e)
            for t in stride(from: 0, to: idx.count, by: 3) {
                let tri = [idx[t], idx[t + 1], idx[t + 2]]
                var faceN = SIMD3<Float>(0, 1, 0)
                let ps = tri.map { i -> SIMD3<Float> in
                    let p = m * SIMD4(P[i].x, P[i].y, P[i].z, 1); return SIMD3(p.x, p.y, p.z)
                }
                let fn = simd_cross(ps[1] - ps[0], ps[2] - ps[0])
                if simd_length(fn) > 0 { faceN = simd_normalize(fn) }
                for (k, i) in tri.enumerated() {
                    pos.append(ps[k])
                    if let N = N { nrm.append(simd_normalize(nm * SIMD3(N[i].x, N[i].y, N[i].z))) } else { nrm.append(faceN) }
                    var c = flat
                    if textured, let T = T { c = palette!.sample(SIMD2(T[i].x, T[i].y)) }
                    col.append(c)
                }
            }
        }
    }
    // Recenter.
    var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
    for p in pos { lo = simd_min(lo, p); hi = simd_max(hi, p) }
    var shift = -(lo + hi) / 2
    if anchor == "base" { shift.y = -lo.y }
    // Dedupe and emit.
    var map: [VKey: UInt32] = [:]
    var vp: [SCNVector3] = [], vn: [SCNVector3] = [], vc: [Float] = [], ix: [UInt32] = []
    for i in 0..<pos.count {
        let c = toLinear(saturate(col[i], 1.15))
        let key = VKey(p: pos[i] + shift, n: nrm[i], c: c)
        if let j = map[key] { ix.append(j); continue }
        let j = UInt32(vp.count); map[key] = j; ix.append(j)
        let p = key.p, n = key.n
        vp.append(SCNVector3(p.x, p.y, p.z)); vn.append(SCNVector3(n.x, n.y, n.z))
        vc += [c.x, c.y, c.z, 1]
    }
    let cdata = vc.withUnsafeBufferPointer { Data(buffer: $0) }
    let csrc = SCNGeometrySource(data: cdata, semantic: .color, vectorCount: vp.count, usesFloatComponents: true,
                                 componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
    let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: vp), SCNGeometrySource(normals: vn), csrc],
                          elements: [SCNGeometryElement(indices: ix, primitiveType: .triangles)])
    let mat = SCNMaterial()
    mat.name = "scenery"
    mat.lightingModel = .lambert
    mat.diffuse.contents = NSColor.white
    geo.materials = [mat]
    return geo
}

// MARK: the curated list

let K = (
    commercial: "\(src)/city-kit-commercial/Models/OBJ format",
    suburban: "\(src)/city-kit-suburban/Models/OBJ format",
    roads: "\(src)/city-kit-roads/Models/OBJ format",
    nature: "\(src)/nature-kit/Models/OBJ format",
    furniture: "\(src)/furniture-kit/Models/OBJ format",
    town: "\(src)/fantasy-town-kit/Models/OBJ format"
)

// Nature kit greens are teal and trunks are orange. Push them to cartoon green and brown.
let jungleRemap: [String: UInt32] = [
    "leafsGreen": 0x46C23C, "leafsDark": 0x2A9A3A, "grass": 0x5BCB45, "leafsFall": 0x9BD43A,
    "woodBark": 0x9A6238, "woodBarkDark": 0x7E4E2E, "wood": 0xA8703F, "woodDark": 0x80522F,
    "dirt": 0x9C9A8C, "dirtDark": 0x7D7B70, "woodInner": 0xE8CFA0,
]
let farmRemap: [String: UInt32] = [
    "leafsGreen": 0x6BCB3C, "leafsDark": 0x3FA83A, "grass": 0x7ED34A, "leafsFall": 0xF2A33A,
    "woodBark": 0xA2683E, "woodBarkDark": 0x86532F, "wood": 0xF4EEE2, "woodDark": 0xD9D0C0,
    "dirt": 0x9A6A42, "dirtDark": 0x7A5033, "woodInner": 0xE8CFA0,
]
let houseRemap: [String: UInt32] = [
    "carpet": 0xE9505A, "carpetDarker": 0xB63A48, "carpetBlue": 0x4E86E8, "plant": 0x3DBE55,
]

typealias Item = (name: String, dir: String, file: String, anchor: String)
typealias World = (file: String, palette: String?, remap: [String: UInt32], items: [Item])
var worlds: [World] = []
func kitItems(_ prefix: String, _ dir: String, _ names: [String]) -> [Item] {
    names.map { (name: prefix + $0, dir: dir, file: $0, anchor: "base") }
}

var city: [Item] = []
for l in "abcdefghijklmn" { city.append(("city_building_\(l)", K.commercial, "building-\(l)", "base")) }
for l in "abcdefghijklmn" { city.append(("city_far_\(l)", K.commercial, "low-detail-building-\(l)", "base")) }
city += [
    ("city_far_wide_a", K.commercial, "low-detail-building-wide-a", "base"),
    ("city_far_wide_b", K.commercial, "low-detail-building-wide-b", "base"),
    ("city_awning", K.commercial, "detail-awning", "base"),
    ("city_awning_wide", K.commercial, "detail-awning-wide", "base"),
    ("city_parasol", K.commercial, "detail-parasol-a", "base"),
]
worlds.append(("scenery_city", "\(K.commercial)/Textures/colormap.png", [:], city))
worlds.append(("scenery_street", "\(K.roads)/Textures/colormap.png", [:], [
    ("street_lamp", K.roads, "light-curved", "base"),
    ("street_lamp_double", K.roads, "light-square-double", "base"),
    ("street_dumpster", K.roads, "dumpster", "base"),
    ("street_cone", K.roads, "construction-cone", "base"),
]))
worlds.append(("scenery_suburb", "\(K.suburban)/Textures/colormap.png", [:], [
    ("suburb_planter", K.suburban, "planter", "base"),
    ("suburb_tree_large", K.suburban, "tree-large", "base"),
    ("suburb_tree_small", K.suburban, "tree-small", "base"),
]))
worlds.append(("scenery_town", "\(K.town)/Textures/colormap.png", [:], [
    ("town_windmill_blades", K.town, "windmill", "center"),
    ("town_cart", K.town, "cart", "base"),
    ("town_stall_red", K.town, "stall-red", "base"),
    ("town_stall_green", K.town, "stall-green", "base"),
    ("town_lantern", K.town, "lantern", "base"),
]))
worlds.append(("scenery_jungle", nil as String?, jungleRemap, kitItems("jungle_", K.nature, [
    "tree_palmTall", "tree_palmDetailedTall", "tree_palmBend", "tree_palm", "tree_palmShort",
    "tree_detailed", "tree_fat", "tree_oak", "tree_default", "tree_plateau", "tree_thin",
    "tree_default_dark", "tree_oak_dark", "tree_fat_darkh", "tree_detailed_dark", "tree_plateau_dark",
    "plant_bushLarge", "plant_bushDetailed", "plant_bush", "plant_flatTall", "plant_flatShort",
    "grass_leafsLarge", "grass_large", "rock_largeA", "rock_largeC", "rock_tallA", "rock_tallC",
    "log_large", "stump_old", "mushroom_redGroup", "mushroom_redTall", "hanging_moss",
    "flower_redA", "flower_yellowB", "flower_purpleA",
])))
worlds.append(("scenery_farm", nil as String?, farmRemap, kitItems("farm_", K.nature, [
    "crops_cornStageD", "crops_cornStageC", "crops_wheatStageB", "crops_wheatStageA", "crops_dirtRow",
    "crop_pumpkin", "crop_melon", "crops_leafsStageB", "fence_simple", "fence_planks", "fence_gate",
    "tree_oak", "tree_default", "tree_fat", "tree_detailed", "tree_oak_fall", "plant_bush", "plant_bushLarge",
    "flower_yellowA", "flower_redB", "grass_large", "log_stack", "stump_round",
])))
worlds.append(("scenery_house", nil as String?, houseRemap, kitItems("house_", K.furniture, [
    "bookcaseOpen", "bookcaseClosedWide", "bookcaseOpenLow", "loungeSofa", "loungeSofaLong", "loungeChair",
    "loungeDesignChair", "loungeDesignSofa", "sideTable", "sideTableDrawers", "lampRoundFloor", "lampSquareFloor",
    "lampRoundTable", "pottedPlant", "plantSmall1", "plantSmall2", "rugRectangle", "rugRound", "rugRounded",
    "tableCoffee", "cabinetTelevision", "televisionModern", "coatRackStanding", "kitchenFridge", "benchCushion",
    "chairCushion", "desk", "books", "speaker", "radio", "doorway", "bear", "trashcan", "cardboardBoxOpen",
    "cardboardBoxClosed", "tableRound", "washer", "pillow", "pillowBlue", "plantSmall3",
])))

var total = 0
for w in worlds {
    let pal = w.palette.map(Palette.init)
    let root = SCNScene()
    var tris = 0
    for it in w.items {
        let g = bake("\(it.dir)/\(it.file).obj", palette: pal, remap: w.remap, anchor: it.anchor)
        let n = SCNNode(geometry: g)
        n.name = it.name
        root.rootNode.addChildNode(n)
        tris += g.elements[0].primitiveCount
    }
    let url = URL(fileURLWithPath: "\(out)/\(w.file).scn")
    guard root.write(to: url, options: nil, delegate: nil, progressHandler: nil) else { fatalError("write \(url)") }
    print("\(w.file).scn: \(w.items.count) models, \(tris) triangles")
    total += w.items.count
}
print("baked \(total) models")
SWIFT

swiftc -O -o "$BAKE" "$BAKE.swift"
"$BAKE" "$SRC" "$OUT"
du -sh "$OUT"
