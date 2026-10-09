import SceneKit
import simd
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

// Roadside scenery for the four worlds.
//
// Everything outside the road (sidewalks, grass, floors, buildings, trees,
// furniture) is built here. The road itself belongs to GameScene.
//
// How it works:
// - The Kenney kit models were baked by scripts/fetch_models.sh into
//   CatCart/Models/scenery_*.scn. Each model is one mesh whose colors are
//   stored per vertex, so no textures ship.
// - SceneryLibrary loads those meshes once into plain arrays.
// - dressing(for:length:seed:) stamps copies of them (plus simple boxes and
//   cylinders for walls, curbs, barns, hay bales) into ONE mesh per segment.
//   One mesh and one shared material means one draw call per segment.
//
// Coordinates are meters. +y is up, the player sits at z = 0, ahead is -z.
// The road is |x| <= 3. Nothing here pokes into |x| < 3.2 unless it is higher
// than `overheadClear` (branches, garlands, ceiling beams).

/// The lowest anything may hang over the road. The run camera tops out near 9.1 m
/// (the top of a jump off a tall cat tree), and she reaches 7.7 m.
let overheadClear: Float = 9.8

enum WorldKind: Int, CaseIterable { case city, jungle, house, farm }

typealias SceneryRGB = SIMD3<Float>

/// sRGB hex to the linear color SceneKit expects in vertex colors.
private func rgb(_ h: UInt32) -> SceneryRGB {
    func f(_ x: Float) -> Float { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return SceneryRGB(f(Float((h >> 16) & 255) / 255), f(Float((h >> 8) & 255) / 255), f(Float(h & 255) / 255))
}

// MARK: - Small math helpers

private func translate(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(x, y, z, 1)
    return m
}

private func rotateY(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3(0, 1, 0)))
}

private func rotateX(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3(1, 0, 0)))
}

private func rotateZ(_ a: Float) -> simd_float4x4 {
    simd_float4x4(simd_quatf(angle: a, axis: SIMD3(0, 0, 1)))
}

private func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4(x, y, z, 1))
}

/// Seeded random numbers, so the same seed always builds the same segment.
private struct SeededRandom {
    var state: UInt64
    init(_ seed: Int, _ salt: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(salt &+ 1) &* 0xBF58_476D_1CE4_E5B9
        _ = next()
    }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func f(_ a: Float, _ b: Float) -> Float {
        a + (b - a) * Float(next() >> 40) / Float(1 << 24)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    mutating func chance(_ p: Float) -> Bool { f(0, 1) < p }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}

// MARK: - Mesh data

/// A baked model: triangles with per-vertex colors, sitting on y = 0, centered on x/z.
struct SceneryModel {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var colors: [SceneryRGB] = []
    var indices: [UInt32] = []
    var lo = SIMD3<Float>(repeating: 0)
    var hi = SIMD3<Float>(repeating: 0)
    var size: SIMD3<Float> { hi - lo }
    var triangleCount: Int { indices.count / 3 }
}

/// Collects triangles for one segment, then turns them into one SCNGeometry.
private final class MeshBuilder {
    var pos: [Float] = []
    var nrm: [Float] = []
    var col: [Float] = []
    var idx: [UInt32] = []
    var triangleCount: Int { idx.count / 3 }

    private func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ c: SceneryRGB) -> UInt32 {
        let i = UInt32(pos.count / 3)
        pos += [p.x, p.y, p.z]
        nrm += [n.x, n.y, n.z]
        col += [c.x, c.y, c.z, 1]
        return i
    }

    /// Stamp a baked model. `recolor` can remap its colors (used to paint buildings).
    func add(_ m: SceneryModel, _ t: simd_float4x4, recolor: ((SceneryRGB) -> SceneryRGB)? = nil) {
        let base = UInt32(pos.count / 3)
        let upper = simd_float3x3(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                                  SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                                  SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
        let nm = upper.inverse.transpose
        pos.reserveCapacity(pos.count + m.positions.count * 3)
        for i in 0..<m.positions.count {
            let p = t * SIMD4(m.positions[i], 1)
            let n = simd_normalize(nm * m.normals[i])
            let c = recolor?(m.colors[i]) ?? m.colors[i]
            pos += [p.x, p.y, p.z]
            nrm += [n.x, n.y, n.z]
            col += [c.x, c.y, c.z, 1]
        }
        idx += m.indices.map { $0 + base }
    }

    func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ color: SceneryRGB) {
        let n = simd_normalize(simd_cross(b - a, c - a))
        let i0 = vertex(a, n, color), i1 = vertex(b, n, color), i2 = vertex(c, n, color)
        idx += [i0, i1, i2]
    }

    /// Quad with corners o, o+u, o+u+v, o+v. It faces along cross(u, v).
    /// Long quads are split every 3 m along z, so the curved-world bend (which moves
    /// vertices, not pixels) can curve them with the road.
    func quad(_ o: SIMD3<Float>, _ u: SIMD3<Float>, _ v: SIMD3<Float>, _ color: SceneryRGB) {
        let n = simd_normalize(simd_cross(u, v))
        let nu = max(1, Int((abs(u.z) / 3).rounded(.up)))
        let nv = max(1, Int((abs(v.z) / 3).rounded(.up)))
        let base = UInt32(pos.count / 3)
        for j in 0...nv {
            for i in 0...nu {
                _ = vertex(o + u * (Float(i) / Float(nu)) + v * (Float(j) / Float(nv)), n, color)
            }
        }
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) {
            for i in 0..<UInt32(nu) {
                let a = base + j * row + i
                idx += [a, a + 1, a + row + 1, a, a + row + 1, a + row]
            }
        }
    }

    /// Flat ground patch at height y, spanning x0..x1 and z0..z1.
    func ground(_ x0: Float, _ x1: Float, _ z0: Float, _ z1: Float, y: Float, _ c: SceneryRGB) {
        let a = min(x0, x1), b = max(x0, x1), zn = min(z0, z1), zf = max(z0, z1)
        quad(SIMD3(a, y, zf), SIMD3(b - a, 0, 0), SIMD3(0, 0, zn - zf), c)
    }

    /// Axis-aligned box from lo to hi (in the frame of `t`). No bottom face.
    func box(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, _ c: SceneryRGB, top: SceneryRGB? = nil,
             _ t: simd_float4x4 = matrix_identity_float4x4) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            let p = t * SIMD4(x, y, z, 1); return SIMD3(p.x, p.y, p.z)
        }
        func face(_ o: SIMD3<Float>, _ u: SIMD3<Float>, _ v: SIMD3<Float>, _ col: SceneryRGB) {
            let a = P(o.x, o.y, o.z)
            let b = P(o.x + u.x, o.y + u.y, o.z + u.z)
            let d = P(o.x + v.x, o.y + v.y, o.z + v.z)
            quad(a, b - a, d - a, col)
        }
        let s = hi - lo
        face(SIMD3(hi.x, lo.y, hi.z), SIMD3(0, 0, -s.z), SIMD3(0, s.y, 0), c * 0.97)   // +x
        face(SIMD3(lo.x, lo.y, lo.z), SIMD3(0, 0, s.z), SIMD3(0, s.y, 0), c * 0.97)    // -x
        face(SIMD3(lo.x, lo.y, hi.z), SIMD3(s.x, 0, 0), SIMD3(0, s.y, 0), c)           // +z
        face(SIMD3(hi.x, lo.y, lo.z), SIMD3(-s.x, 0, 0), SIMD3(0, s.y, 0), c * 0.9)    // -z
        face(SIMD3(lo.x, hi.y, hi.z), SIMD3(s.x, 0, 0), SIMD3(0, 0, -s.z), top ?? c)   // +y
    }

    /// Frustum along +y (a cone when r1 is 0). Base center at the origin of `t`.
    func frustum(r0: Float, r1: Float, h: Float, sides: Int, _ c: SceneryRGB, cap: SceneryRGB? = nil,
                 bottom: Bool = false, _ t: simd_float4x4) {
        func P(_ p: SIMD3<Float>) -> SIMD3<Float> { let q = t * SIMD4(p, 1); return SIMD3(q.x, q.y, q.z) }
        for k in 0..<sides {
            let a0 = Float(k) / Float(sides) * 2 * .pi, a1 = Float(k + 1) / Float(sides) * 2 * .pi
            let b0 = SIMD3(cos(a0) * r0, 0, -sin(a0) * r0), b1 = SIMD3(cos(a1) * r0, 0, -sin(a1) * r0)
            let t0 = SIMD3(cos(a0) * r1, h, -sin(a0) * r1), t1 = SIMD3(cos(a1) * r1, h, -sin(a1) * r1)
            let shade: Float = 0.9 + 0.1 * cos(a0 - 0.8)
            if r1 > 0.0001 {
                quad(P(b0), P(b1) - P(b0), P(t0) - P(b0), c * shade)
                tri(P(t0), P(b1), P(t1), c * shade)
                tri(P(SIMD3(0, h, 0)), P(t0), P(t1), cap ?? c)
            } else {
                tri(P(b0), P(b1), P(SIMD3(0, h, 0)), c * shade)
            }
            if bottom { tri(P(.zero), P(b1), P(b0), cap ?? c) }
        }
    }

    /// Low-poly ellipsoid (bushes, hills, leaf clusters).
    func blob(_ center: SIMD3<Float>, _ r: SIMD3<Float>, _ c: SceneryRGB, segments: Int = 7, rings: Int = 4) {
        func pt(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let th = Float(j) / Float(rings) * .pi
            let ph = Float(i) / Float(segments) * 2 * .pi
            return center + SIMD3(sin(th) * cos(ph) * r.x, cos(th) * r.y, -sin(th) * sin(ph) * r.z)
        }
        for j in 0..<rings {
            let shade: Float = 1.05 - 0.25 * Float(j) / Float(rings)
            for i in 0..<segments {
                let a = pt(i, j), b = pt(i, j + 1), cc = pt(i + 1, j + 1), d = pt(i + 1, j)
                if j == 0 { tri(a, b, cc, c * shade) }
                else if j == rings - 1 { tri(a, b, d, c * shade) }
                else { tri(a, b, cc, c * shade); tri(a, cc, d, c * shade) }
            }
        }
    }

    func build(material: SCNMaterial) -> SCNGeometry {
        let n = pos.count / 3
        func source(_ a: [Float], _ sem: SCNGeometrySource.Semantic, _ comps: Int) -> SCNGeometrySource {
            let d = a.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: d, semantic: sem, vectorCount: n, usesFloatComponents: true,
                                     componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0,
                                     dataStride: comps * 4)
        }
        let id = idx.withUnsafeBufferPointer { Data(buffer: $0) }
        let el = SCNGeometryElement(data: id, primitiveType: .triangles, primitiveCount: idx.count / 3,
                                    bytesPerIndex: 4)
        let g = SCNGeometry(sources: [source(pos, .vertex, 3), source(nrm, .normal, 3), source(col, .color, 4)],
                            elements: [el])
        g.materials = [material]
        return g
    }
}

// MARK: - Library

final class SceneryLibrary {
    /// The one material every segment uses. White lambert; colors come from the vertices.
    /// Add the curved-world shader modifier here once and every segment gets it.
    let material: SCNMaterial

    private(set) var models: [String: SceneryModel] = [:]

    /// Loads and caches every model once. Heavy work happens here, not per segment.
    /// nil = Bundle.main (flat bundle). The preview passes CatCart/Models (searched recursively).
    init(searchDirectory: URL? = nil) {
        material = SCNMaterial()
        material.name = "scenery"
        material.lightingModel = .lambert
        material.diffuse.contents = PlatformColor.white
        material.isDoubleSided = false

        let files = ["scenery_city", "scenery_street", "scenery_suburb", "scenery_town",
                     "scenery_jungle", "scenery_farm", "scenery_house"]
        var found: [String: URL] = [:]
        if let dir = searchDirectory {
            let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
            while let u = e?.nextObject() as? URL {
                let name = u.deletingPathExtension().lastPathComponent
                if u.pathExtension == "scn", files.contains(name) { found[name] = u }
            }
        } else {
            for f in files { found[f] = Bundle.main.url(forResource: f, withExtension: "scn") }
        }
        for f in files {
            guard let url = found[f], let scene = try? SCNScene(url: url, options: nil) else {
                print("SceneryLibrary: missing \(f).scn")
                continue
            }
            for node in scene.rootNode.childNodes {
                guard let name = node.name, let g = node.geometry else { continue }
                models[name] = SceneryLibrary.read(g)
            }
        }
    }

    private static func read(_ g: SCNGeometry) -> SceneryModel {
        func vectors(_ s: SCNGeometrySource?) -> [SIMD4<Float>] {
            guard let s = s else { return [] }
            var r = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, 1), count: s.vectorCount)
            s.data.withUnsafeBytes { raw in
                for i in 0..<s.vectorCount {
                    for c in 0..<min(4, s.componentsPerVector) {
                        let o = s.dataOffset + i * s.dataStride + c * s.bytesPerComponent
                        switch s.bytesPerComponent {
                        case 8: r[i][c] = Float(raw.loadUnaligned(fromByteOffset: o, as: Double.self))
                        case 1: r[i][c] = Float(raw.load(fromByteOffset: o, as: UInt8.self)) / 255
                        case 2:
                            // Half floats, in case Xcode's scene compression ever quantizes.
                            let h = raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)
                            let sign: Float = (h & 0x8000) != 0 ? -1 : 1
                            let e = Int((h >> 10) & 0x1F), f = Float(h & 0x3FF)
                            r[i][c] = e == 0 ? sign * f * pow(2, -24) : sign * (1 + f / 1024) * pow(2, Float(e - 15))
                        default: r[i][c] = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                        }
                    }
                }
            }
            return r
        }
        var m = SceneryModel()
        m.positions = vectors(g.sources(for: .vertex).first).map { SIMD3($0.x, $0.y, $0.z) }
        m.normals = vectors(g.sources(for: .normal).first).map { SIMD3($0.x, $0.y, $0.z) }
        m.colors = vectors(g.sources(for: .color).first).map { SIMD3($0.x, $0.y, $0.z) }
        if m.normals.count != m.positions.count { m.normals = Array(repeating: SIMD3(0, 1, 0), count: m.positions.count) }
        if m.colors.count != m.positions.count { m.colors = Array(repeating: SIMD3(1, 1, 1), count: m.positions.count) }
        for e in g.elements where e.primitiveType == .triangles {
            e.data.withUnsafeBytes { raw in
                for i in 0..<(e.primitiveCount * 3) {
                    switch e.bytesPerIndex {
                    case 1: m.indices.append(UInt32(raw.load(fromByteOffset: i, as: UInt8.self)))
                    case 2: m.indices.append(UInt32(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
                    default: m.indices.append(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
                    }
                }
            }
        }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for p in m.positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        m.lo = m.positions.isEmpty ? .zero : lo
        m.hi = m.positions.isEmpty ? .zero : hi
        return m
    }

    /// Roadside dressing for one track segment. Local space: spans z in [-length, 0], centered on x = 0.
    /// Includes the ground outside the road and scenery on both sides. Tiles with the next
    /// segment of the same world. Different seeds give variety.
    func dressing(for world: WorldKind, length: Float, seed: Int) -> SCNNode {
        let b = MeshBuilder()
        var r = SeededRandom(seed, world.rawValue)
        let L = max(length, 4)
        switch world {
        case .city: buildCity(b, L, &r)
        case .jungle: buildJungle(b, L, &r)
        case .house: buildHouse(b, L, &r)
        case .farm: buildFarm(b, L, &r)
        }
        let node = SCNNode(geometry: b.build(material: material))
        node.name = "scenery_\(world)_\(seed)"
        return node
    }

    // MARK: placing helpers

    /// Put a model on one side of the road with its front (+z in the kit) facing the road.
    /// `x` is distance from the center line to the model's center. `stretch` widens it along the road.
    private func placeFacing(_ b: MeshBuilder, _ name: String, side: Float, x: Float, y: Float = 0, z: Float,
                             s: Float, stretch: Float = 1, recolor: ((SceneryRGB) -> SceneryRGB)? = nil) {
        guard let m = models[name] else { return }
        let t = translate(side * x, y, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2) * scale(s * stretch, s, s)
        b.add(m, t, recolor: recolor)
    }

    /// Put a model at (x, z) with a free rotation.
    private func place(_ b: MeshBuilder, _ name: String, x: Float, y: Float = 0, z: Float, s: Float, yaw: Float,
                       recolor: ((SceneryRGB) -> SceneryRGB)? = nil) {
        guard let m = models[name] else { return }
        b.add(m, translate(x, y, z) * rotateY(yaw) * scale(s, s, s), recolor: recolor)
    }

    /// Half the widest footprint of a model at scale s (for keeping things off the road).
    private func radius(_ name: String, _ s: Float) -> Float {
        guard let m = models[name] else { return 0 }
        return max(m.size.x, m.size.z) * s * 0.5
    }

    /// Scatter models along one side between x0..x1 (distance from center), keeping
    /// each footprint clear of the road.
    private func scatter(_ b: MeshBuilder, _ r: inout SeededRandom, _ names: [String], count: Int, side: Float,
                         x0: Float, x1: Float, L: Float, s0: Float, s1: Float) {
        for _ in 0..<count {
            let name = r.pick(names)
            let s = r.f(s0, s1)
            let rad = radius(name, s)
            let x = max(r.f(x0, x1), 3.25 + rad)
            // Centers stay inside the segment; big crowns may hang into the neighbor
            // segment, which hides the seam between segments instead of leaving a gap.
            let z = r.f(-L + min(rad, 1), -min(rad, 1))
            place(b, name, x: side * x, z: z, s: s, yaw: r.f(0, 2 * .pi))
        }
    }

    // MARK: - City

    private static let wallPastels: [UInt32] = [0xFFB7C5, 0xFFE08A, 0xA8E6CF, 0xA6D8FF, 0xFFC49B, 0xD2BDFF,
                                                0xFFF1D6, 0xFF9E9E, 0xB8F0A0]
    private static let shopColors: [UInt32] = [0x1F9E9A, 0xD8433A, 0x3560C8, 0xF08A24, 0x7A4FB8, 0x2E9E55,
                                               0xE0457B]

    /// Paint a gray-and-white kit building: white walls take the pastel, dark gray
    /// storefront trim takes the shop color. Windows (blue) are left alone.
    private func buildingPaint(wall: SceneryRGB, shop: SceneryRGB) -> (SceneryRGB) -> SceneryRGB {
        return { c in
            let mx = max(c.x, c.y, c.z), mn = min(c.x, c.y, c.z)
            let chroma = mx > 0 ? (mx - mn) / mx : 0
            if chroma < 0.26 && mx > 0.4 { return wall * min(1, mx * 1.05) }
            if chroma < 0.5 && mx < 0.14 { return shop * min(1.2, mx / 0.11) }
            return c
        }
    }

    private func buildCity(_ b: MeshBuilder, _ L: Float, _ r: inout SeededRandom) {
        let curb = rgb(0xD9D5CC), curbTop = rgb(0xEEEBE4)
        let tileA = rgb(0xE9DCC4), tileB = rgb(0xDCCBAE)
        let back = rgb(0x8E8A84)
        let front: Float = 6.8
        let tilesZ = max(2, 2 * Int((L / 3).rounded()))
        let tz = L / Float(tilesZ)
        let buildings = (0..<14).map { "city_building_\(Character(UnicodeScalar(97 + $0)!))" }
            .filter { models[$0] != nil }
        let bigs: Set<String> = ["city_building_n", "city_building_m", "city_building_j"]

        for side: Float in [-1, 1] {
            // Curb and sidewalk.
            b.box(SIMD3(side > 0 ? 3.0 : -3.3, 0, -L), SIMD3(side > 0 ? 3.3 : -3.0, 0.2, 0), curb, top: curbTop)
            for i in 0..<tilesZ {
                for j in 0..<2 {
                    let x0: Float = 3.3 + Float(j) * (front - 3.3) / 2
                    let x1: Float = x0 + (front - 3.3) / 2
                    let c = (i + j) % 2 == 0 ? tileA : tileB
                    b.ground(side * x0, side * x1, -Float(i) * tz, -Float(i + 1) * tz, y: 0.16, c)
                }
            }
            b.ground(side * front, side * 42, 0, -L, y: 0.15, back)

            // Street wall: pack buildings along the segment, then stretch them to fit exactly.
            var row: [String] = []
            var total: Float = 0
            let S: Float = 7.6
            var bigUsed = false
            while total < L - 2 {
                var pool = buildings.filter { total + models[$0]!.size.x * S <= L + 2.5 }
                if bigUsed { pool = pool.filter { !bigs.contains($0) } }
                if pool.isEmpty { pool = [buildings.min { models[$0]!.size.x < models[$1]!.size.x }!] }
                let name = r.pick(pool)
                if bigs.contains(name) { bigUsed = true }
                row.append(name)
                total += models[name]!.size.x * S
            }
            let stretch = L / total
            var z: Float = 0
            for name in row {
                let m = models[name]!
                let w = m.size.x * S * stretch
                let depth = m.size.z * S
                let setback = r.f(0, 0.5)
                let wall = rgb(r.pick(Self.wallPastels)), shop = rgb(r.pick(Self.shopColors))
                let zc = z - w / 2
                placeFacing(b, name, side: side, x: front + setback + depth / 2, y: 0.15, z: zc, s: S,
                            stretch: stretch, recolor: buildingPaint(wall: wall, shop: shop))
                // Striped shop awning over part of the ground floor.
                if r.chance(0.65) && w > 4 {
                    let aw = min(w - 1.2, r.f(3.5, 6))
                    awning(b, side: side, face: front + setback, z: zc, width: aw, colorA: shop,
                           colorB: rgb(0xFFFFFF))
                }
                z -= w
            }

            // Tall pastel towers behind the street wall, so the skyline is full.
            let fars = ["city_far_a", "city_far_b", "city_far_c", "city_far_d", "city_far_e", "city_far_f",
                        "city_far_g", "city_far_h", "city_far_i", "city_far_j", "city_far_k", "city_far_l",
                        "city_far_m", "city_far_n", "city_far_wide_a", "city_far_wide_b"]
            var fz: Float = -r.f(1, 4)
            while fz > -L + 3 {
                let name = r.pick(fars)
                let s = r.f(9, 13)
                let rad = radius(name, s)
                if fz - 2 * rad < -L { break }
                let tint = rgb(r.pick(Self.wallPastels))
                place(b, name, x: side * r.f(22, 30), y: 0.15, z: fz - rad, s: s, yaw: side > 0 ? -.pi / 2 : .pi / 2,
                      recolor: { c in
                          let mx = max(c.x, c.y, c.z)
                          return mx > 0.4 ? tint * mx : c
                      })
                fz -= 2 * rad + r.f(1, 5)
            }

            // Sidewalk furniture. Lamps every half segment, trees and benches between.
            let q = L / 4
            for k in [1, 3] {
                let lz = -q * Float(k) + r.f(-0.5, 0.5)
                placeFacing(b, "street_lamp", side: side, x: 3.75, y: 0.16, z: lz, s: 8)
                if r.chance(0.5) {
                    hydrant(b, x: side * 3.8, z: lz + 1.6)
                    // A yellow-painted stretch of curb by the hydrant.
                    b.box(SIMD3(side > 0 ? 3.0 : -3.3, 0.2, lz + 0.5), SIMD3(side > 0 ? 3.3 : -3.0, 0.215, lz + 2.6),
                          rgb(0xF2C63C))
                }
            }
            // More street life, one piece per side: a mailbox, a trash can, a bus stop,
            // cones around a dumpster, or another tree. All on the sidewalk.
            let extraZ = -q * Float(r.int(3) + 1) + r.f(-1.5, 1.5)
            switch r.int(6) {
            case 0: mailbox(b, side: side, x: 4.6, z: extraZ)
            case 1: trashCan(b, x: side * 4.5, z: extraZ)
            case 2: busStop(b, side: side, x: 5.2, z: extraZ, r: &r)
            case 3:
                let ds = min(8, 1.4 / max(radius("street_dumpster", 1), 0.01))
                placeFacing(b, "street_dumpster", side: side, x: front - 1.1, y: 0.16, z: extraZ, s: ds)
                for k in 0..<2 {
                    place(b, "street_cone", x: side * r.f(3.6, 4.2), y: 0.16, z: extraZ + Float(k) * 0.9 - 0.4, s: 8,
                          yaw: r.f(0, 6.28))
                }
            case 4: planterTree(b, x: side * 4.4, z: extraZ, r: &r)
            default: break
            }
            for zc in [-2 * q, -L + 1.2] {
                switch r.int(4) {
                case 0, 1:
                    planterTree(b, x: side * 4.4, z: zc + r.f(-0.8, 0.8), r: &r)
                case 2:
                    bench(b, side: side, x: 4.2, z: zc)
                default:
                    if models["city_parasol"] != nil {
                        place(b, "city_parasol", x: side * 5.4, y: 0.16, z: zc, s: 6, yaw: 0)
                    }
                    bench(b, side: side, x: 4.2, z: zc + 2.4)
                }
            }
        }

        // A bunting garland across the street now and then, well above the cart.
        // Its flags hang 1.65 m below the poles' tops.
        if r.chance(0.45) {
            garland(b, z: -L * r.f(0.3, 0.7), x: front, y: overheadClear + 1.7, r: &r)
        }
    }

    private func awning(_ b: MeshBuilder, side: Float, face: Float, z: Float, width: Float,
                        colorA: SceneryRGB, colorB: SceneryRGB) {
        let depth: Float = 1.5, yTop: Float = 3.9, yLow: Float = 3.3
        let stripes = max(2, Int(width / 0.5))
        let sw = width / Float(stripes)
        for i in 0..<stripes {
            let c = i % 2 == 0 ? colorA : colorB
            let z0 = z + width / 2 - Float(i) * sw
            // Sloped top from the wall out toward the road, facing up and out.
            let wallP = SIMD3(side * face, yTop, z0)
            let outP = SIMD3(side * (face - depth), yLow, z0)
            let along = SIMD3<Float>(0, 0, -sw)
            if side > 0 { b.quad(outP, wallP - outP, along, c) } else { b.quad(outP, along, wallP - outP, c) }
            // Valance flap.
            let flapTop = outP, flapLow = outP - SIMD3(0, 0.35, 0)
            if side > 0 { b.quad(flapLow, along, flapTop - flapLow, c * 0.92) }
            else { b.quad(flapLow + along, -along, flapTop - flapLow, c * 0.92) }
        }
    }

    private func hydrant(_ b: MeshBuilder, x: Float, z: Float) {
        let red = rgb(0xE8392F), cap = rgb(0xFFD23F)
        b.frustum(r0: 0.26, r1: 0.26, h: 0.12, sides: 8, red, _: translate(x, 0.16, z))
        b.frustum(r0: 0.2, r1: 0.2, h: 0.6, sides: 8, red, _: translate(x, 0.28, z))
        b.frustum(r0: 0.22, r1: 0.05, h: 0.22, sides: 8, cap, _: translate(x, 0.88, z))
        b.box(SIMD3(-0.34, 0.5, -0.07), SIMD3(0.34, 0.64, 0.07), red, translate(x, 0.16, z))
    }

    /// A blue corner mailbox on two legs, its slot hood toward the road.
    private func mailbox(_ b: MeshBuilder, side: Float, x: Float, z: Float) {
        let blue = rgb(0x2F5FBF), dark = rgb(0x24467F)
        let t = translate(side * x, 0.16, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2)
        for lx: Float in [-0.22, 0.22] {
            b.box(SIMD3(lx - 0.04, 0, -0.04), SIMD3(lx + 0.04, 0.5, 0.04), dark, t)
        }
        b.box(SIMD3(-0.36, 0.5, -0.3), SIMD3(0.36, 1.15, 0.3), blue, t)
        b.box(SIMD3(-0.36, 1.15, -0.26), SIMD3(0.36, 1.3, 0.26), blue * 1.08, t)
        b.box(SIMD3(-0.2, 0.95, 0.3), SIMD3(0.2, 1.08, 0.34), dark, t)
    }

    private func trashCan(_ b: MeshBuilder, x: Float, z: Float) {
        let green = rgb(0x3E7C4A), lid = rgb(0x2E5E38)
        b.frustum(r0: 0.3, r1: 0.34, h: 0.9, sides: 10, green, cap: lid, bottom: false, translate(x, 0.16, z))
        b.frustum(r0: 0.37, r1: 0.3, h: 0.14, sides: 10, lid, cap: lid, bottom: false, translate(x, 1.06, z))
    }

    /// A bus shelter: steel posts, a glass back wall, a red roof, a bench, and a
    /// round sign on a pole. Built in a frame where +z faces the road.
    private func busStop(_ b: MeshBuilder, side: Float, x: Float, z: Float, r: inout SeededRandom) {
        let steel = rgb(0x4A5560), glass = rgb(0xBFE4F2), roof = rgb(0xD8453A)
        let t = translate(side * x, 0.16, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2)
        for lx: Float in [-1.4, 1.4] {
            b.box(SIMD3(lx - 0.06, 0, -0.7), SIMD3(lx + 0.06, 2.6, -0.58), steel, t)
            b.box(SIMD3(lx - 0.06, 0, 0.58), SIMD3(lx + 0.06, 2.6, 0.7), steel, t)
        }
        b.box(SIMD3(-1.4, 0.3, -0.7), SIMD3(1.4, 2.4, -0.64), glass, t)
        b.box(SIMD3(-1.55, 2.6, -0.85), SIMD3(1.55, 2.8, 0.85), roof, top: roof * 1.1, t)
        b.box(SIMD3(-1.1, 0.45, -0.5), SIMD3(1.1, 0.55, -0.1), rgb(0xC8834A), t)
        b.box(SIMD3(1.8, 0, -0.06), SIMD3(1.92, 3.2, 0.06), steel, t)
        let sign = rgb(r.pick([0x3560C8, 0xE0457B, 0x2E9E55]))
        b.frustum(r0: 0.32, r1: 0.32, h: 0.06, sides: 12, rgb(0xFFFFFF), cap: sign, bottom: true,
                  t * translate(1.86, 3.2, 0) * rotateX(.pi / 2))
    }

    private func bench(_ b: MeshBuilder, side: Float, x: Float, z: Float) {
        let wood = rgb(0xC8834A), iron = rgb(0x2F5D4A)
        let t = translate(side * x, 0.16, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2)
        b.box(SIMD3(-0.9, 0.45, -0.25), SIMD3(0.9, 0.55, 0.25), wood, t)
        b.box(SIMD3(-0.9, 0.6, -0.33), SIMD3(0.9, 1.05, -0.25), wood, t)
        for lx: Float in [-0.75, 0.75] {
            b.box(SIMD3(lx - 0.06, 0, -0.28), SIMD3(lx + 0.06, 0.45, 0.25), iron, t)
            b.box(SIMD3(lx - 0.06, 0.45, -0.36), SIMD3(lx + 0.06, 1.05, -0.25), iron, t)
        }
    }

    private func planterTree(_ b: MeshBuilder, x: Float, z: Float, r: inout SeededRandom) {
        let brick = rgb(0xC86A4A), soil = rgb(0x6B4A2F)
        b.box(SIMD3(x - 0.55, 0.16, z - 0.55), SIMD3(x + 0.55, 0.62, z + 0.55), brick, top: soil)
        let name = r.chance(0.5) ? "suburb_tree_large" : "suburb_tree_small"
        let s: Float = name == "suburb_tree_large" ? 7 : 6.5
        place(b, name, x: x, y: 0.6, z: z, s: s, yaw: r.f(0, 6.28))
    }

    /// A string of little flags across the road, sagging but always above 4.5 m.
    private func garland(_ b: MeshBuilder, z: Float, x: Float, y: Float, r: inout SeededRandom) {
        let flags: [UInt32] = [0xFF5A5F, 0xFFC93C, 0x3EC1D3, 0x7ED957, 0xB38CFF, 0xFF8FB1]
        let rope = rgb(0x5A4A3A)
        let n = 26
        var prev = SIMD3<Float>(-x, y, z)
        for i in 1...n {
            let t = Float(i) / Float(n)
            let px = -x + 2 * x * t
            let py = y - 1.1 * (1 - pow(2 * t - 1, 2))
            let p = SIMD3<Float>(px, py, z)
            b.box(SIMD3(-0.02, -0.02, -0.02), SIMD3(simd_length(p - prev), 0.02, 0.02), rope,
                  translate(prev.x, prev.y, prev.z) * rotateZ(atan2(p.y - prev.y, p.x - prev.x)))
            if i < n {
                let c = rgb(flags[i % flags.count])
                let a = p + SIMD3(-0.22, 0, 0), bb = p + SIMD3(0.22, 0, 0), tip = p + SIMD3(0, -0.55, 0)
                b.tri(a, tip, bb, c)
                b.tri(bb, tip, a, c * 0.8)
            }
            prev = p
        }
        // Poles on the sidewalks that hold the rope.
        for s: Float in [-1, 1] {
            b.box(SIMD3(-0.08, 0, -0.08), SIMD3(0.08, y + 0.1, 0.08), rgb(0x3B4452), translate(s * x, 0.15, z))
        }
    }

    // MARK: - Jungle

    private func buildJungle(_ b: MeshBuilder, _ L: Float, _ r: inout SeededRandom) {
        let dirt = rgb(0x9A6A3E), floorA = rgb(0x4FA83B), floorB = rgb(0x3E9433), floorC = rgb(0x62B845)
        let bigTrees = ["jungle_tree_oak", "jungle_tree_fat", "jungle_tree_detailed", "jungle_tree_default",
                        "jungle_tree_plateau", "jungle_tree_oak_dark", "jungle_tree_fat_darkh",
                        "jungle_tree_detailed_dark", "jungle_tree_default_dark", "jungle_tree_plateau_dark"]
        let palms = ["jungle_tree_palmTall", "jungle_tree_palmDetailedTall", "jungle_tree_palmBend",
                     "jungle_tree_palm"]
        let low = ["jungle_plant_bushLarge", "jungle_plant_bushDetailed", "jungle_plant_bush",
                   "jungle_plant_flatTall", "jungle_plant_flatShort", "jungle_grass_leafsLarge",
                   "jungle_grass_large"]
        let accents = ["jungle_flower_redA", "jungle_flower_yellowB", "jungle_flower_purpleA",
                       "jungle_mushroom_redGroup", "jungle_rock_largeA", "jungle_rock_largeC", "jungle_stump_old"]

        for side: Float in [-1, 1] {
            b.ground(side * 3.0, side * 3.9, 0, -L, y: 0.02, dirt)
            b.ground(side * 3.9, side * 42, 0, -L, y: 0.01, floorA)
            // Darker and lighter patches on the jungle floor.
            for _ in 0..<7 {
                let w = r.f(1.5, 4), d = r.f(2, 5)
                let x = r.f(4.2, 14), z = r.f(-L + d / 2, -d / 2)
                b.ground(side * x, side * (x + w), z + d / 2, z - d / 2, y: 0.02, r.chance(0.5) ? floorB : floorC)
            }
            // Low plants crowding the path edge.
            scatter(b, &r, low, count: 12, side: side, x0: 3.4, x1: 6.5, L: L, s0: 3.5, s1: 6)
            scatter(b, &r, accents, count: 5, side: side, x0: 3.6, x1: 6.5, L: L, s0: 2.5, s1: 4)
            if r.chance(0.6), let log = models["jungle_log_large"] {
                let s: Float = 3.5
                let len = log.size.x * s
                place(b, "jungle_log_large", x: side * r.f(4.4, 5.5), z: -r.f(len / 2 + 0.5, L - len / 2 - 0.5),
                      s: s, yaw: .pi / 2 + r.f(-0.2, 0.2))
            }
            // Ferns, rocks, flowers, and now and then a pond with lily pads by the path.
            for _ in 0..<(r.int(3) + 2) {
                fern(b, x: side * r.f(3.6, 5.2), z: -r.f(0.6, L - 0.6), s: r.f(0.7, 1.2), r: &r)
            }
            scatter(b, &r, ["jungle_rock_largeA", "jungle_rock_largeC"], count: 2, side: side, x0: 3.6, x1: 7, L: L,
                    s0: 2.5, s1: 4.5)
            scatter(b, &r, ["jungle_flower_redA", "jungle_flower_yellowB", "jungle_flower_purpleA"], count: 4,
                    side: side, x0: 3.5, x1: 5.5, L: L, s0: 3, s1: 4.5)
            if r.chance(0.3) { pond(b, x: side * r.f(5.6, 7.0), z: -r.f(4, L - 4), r: &r) }
            // Mid layer: big trees and palms.
            scatter(b, &r, bigTrees, count: 4, side: side, x0: 6.5, x1: 10, L: L, s0: 7, s1: 10)
            scatter(b, &r, palms, count: 3, side: side, x0: 5.5, x1: 9, L: L, s0: 6.5, s1: 8.5)
            scatter(b, &r, low, count: 6, side: side, x0: 6, x1: 11, L: L, s0: 5, s1: 8)
            // Back wall of giant trees and rocks.
            scatter(b, &r, bigTrees, count: 6, side: side, x0: 11, x1: 22, L: L, s0: 11, s1: 16)
            scatter(b, &r, ["jungle_rock_tallA", "jungle_rock_tallC"], count: 1, side: side, x0: 12, x1: 20, L: L,
                    s0: 7, s1: 10)
            scatter(b, &r, palms, count: 2, side: side, x0: 10, x1: 18, L: L, s0: 9, s1: 12)
        }

        // A big mossy branch arching over the path.
        if r.chance(0.7) {
            let z = -L * r.f(0.25, 0.75)
            let bark = rgb(0x7E4E2E), leaf = rgb(0x3FAE3A), leafDark = rgb(0x2E8F34)
            // High enough for 1.5 m of moss to hang over the road.
            let y: Float = overheadClear + 1.8
            // Trunks holding it up on both sides.
            for s: Float in [-1, 1] {
                b.frustum(r0: 0.75, r1: 0.55, h: y + 0.4, sides: 7, bark, _: translate(s * 7.5, 0, z))
                b.blob(SIMD3(s * 7.5, y + 1.8, z), SIMD3(3.2, 2.2, 3.0), leafDark)
                // Lianas hanging down the road side of each trunk.
                for _ in 0..<3 {
                    let vx = s * r.f(6.0, 6.7), vz = z + r.f(-0.8, 0.8)
                    let top = y - r.f(0, 2), bottom = r.f(0.5, 3)
                    b.box(SIMD3(vx - 0.05, bottom, vz - 0.05), SIMD3(vx + 0.05, top, vz + 0.05), rgb(0x4E7A2A))
                }
            }
            b.box(SIMD3(-7.5, -0.35, -0.35), SIMD3(7.5, 0.35, 0.35), bark, top: bark * 1.1, translate(0, y, z))
            var x: Float = -6
            while x <= 6 {
                b.blob(SIMD3(x, y + 0.6, z + r.f(-0.4, 0.4)), SIMD3(r.f(1.2, 1.8), r.f(0.8, 1.1), r.f(1.2, 1.7)),
                       r.chance(0.5) ? leaf : leafDark, segments: 6, rings: 3)
                if let moss = models["jungle_hanging_moss"], r.chance(0.8) {
                    let s = min(r.f(3, 4.5), (y - 0.3 - overheadClear) / moss.size.y)
                    b.add(moss, translate(x + r.f(-0.4, 0.4), y - 0.3 - moss.size.y * s, z + r.f(-0.3, 0.3))
                              * rotateY(r.f(0, 6.28)) * scale(s, s, s))
                }
                x += r.f(1.4, 2.0)
            }
        }
    }

    /// A fern: fronds arching out from a base, each a tapered blade drawn with
    /// both windings so it shows from either side.
    private func fern(_ b: MeshBuilder, x: Float, z: Float, s: Float, r: inout SeededRandom) {
        let greens: [UInt32] = [0x3F9E3A, 0x55B24A, 0x2E8A34]
        let fronds = 7
        let a0 = r.f(0, 6.28)
        for i in 0..<fronds {
            let a = a0 + Float(i) / Float(fronds) * 2 * .pi + r.f(-0.2, 0.2)
            let len = s * r.f(0.9, 1.4)
            let dir = SIMD3<Float>(cos(a), 0, -sin(a))
            let root = SIMD3<Float>(x, 0.05, z)
            let mid = root + dir * (len * 0.5) + SIMD3<Float>(0, s * 0.55, 0)
            let tip = root + dir * len + SIMD3<Float>(0, s * 0.35, 0)
            let across = SIMD3<Float>(-dir.z, 0, dir.x) * (0.16 * s)
            let c = rgb(greens[i % greens.count])
            b.tri(root - across, mid + across, mid - across, c)
            b.tri(root - across, root + across, mid + across, c)
            b.tri(root - across, mid - across, mid + across, c * 0.85)
            b.tri(root - across, mid + across, root + across, c * 0.85)
            b.tri(mid - across, tip, mid + across, c)
            b.tri(mid - across, mid + across, tip, c * 0.85)
        }
    }

    /// A small pond: a mud rim, still water, lily pads, a flower or two.
    private func pond(_ b: MeshBuilder, x: Float, z: Float, r: inout SeededRandom) {
        let mud = rgb(0x6B4A2F), water = rgb(0x7FD2CC), pad = rgb(0x4FA83B), bloom = rgb(0xFF9FC7)
        b.frustum(r0: 2.0, r1: 1.9, h: 0.05, sides: 14, mud, cap: mud, bottom: false, translate(x, 0, z))
        b.frustum(r0: 1.7, r1: 1.6, h: 0.03, sides: 14, water, cap: water, bottom: false, translate(x, 0.05, z))
        for _ in 0..<3 {
            let a = r.f(0, 6.28), d = r.f(0.3, 1.2)
            let px = x + cos(a) * d, pz = z + sin(a) * d
            b.frustum(r0: 0.22, r1: 0.22, h: 0.02, sides: 8, pad, cap: pad, bottom: false, translate(px, 0.08, pz))
            if r.chance(0.5) { b.blob(SIMD3(px, 0.16, pz), SIMD3(0.1, 0.08, 0.1), bloom, segments: 6, rings: 3) }
        }
    }

    // MARK: - House

    private static let wallPaints: [(UInt32, UInt32)] = [
        (0xFFE3B8, 0x8CC7B8), (0xCFE8FF, 0x5B8FD0), (0xFFD6DE, 0xC96B85), (0xE6F5C9, 0x7FB05B),
        (0xFFF0C2, 0xE39A4C), (0xE9DDFF, 0x8C74C9),
    ]

    private func buildHouse(_ b: MeshBuilder, _ L: Float, _ r: inout SeededRandom) {
        // The beams across the top of the walls must clear the camera.
        let wallX: Float = 7.0, wallH: Float = overheadClear + 0.2
        let white = rgb(0xFBF7EF)
        let woods: [UInt32] = [0xC98B55, 0xBF8150, 0xD29560, 0xB97A48]
        let paint = r.pick(Self.wallPaints)
        let upper = rgb(paint.0), lower = rgb(paint.1)

        for side: Float in [-1, 1] {
            // Wood plank floor: planks run along the road, board ends staggered.
            let plankW: Float = 0.5
            var x: Float = 3.0
            var row = 0
            while x < wallX - 0.01 {
                let x1 = min(wallX, x + plankW)
                var z: Float = 0
                var first = true
                while z > -L + 0.01 {
                    let len = first ? r.f(0.8, 3.2) : r.f(2.4, 4.2)
                    let z1 = max(-L, z - len)
                    b.ground(side * x, side * (x1 - 0.02), z, z1 + 0.02, y: 0.012, rgb(woods[(row + Int(-z)) % woods.count]))
                    z = z1
                    first = false
                }
                // Dark gaps between planks read as seams without any texture.
                b.ground(side * (x1 - 0.02), side * x1, 0, -L, y: 0.011, rgb(0x7A4E2C))
                x = x1
                row += 1
            }
            // Floor under the wall and beyond, so the fog never shows a hole.
            b.ground(side * wallX, side * 42, 0, -L, y: 0.005, rgb(0x8A5A34))

            // The wall: lower paint, chair rail, upper paint with soft stripes, crown molding.
            let face = side * wallX, thick = side * (wallX + 0.4)
            b.box(SIMD3(min(face, thick), 0, -L), SIMD3(max(face, thick), 1.7, 0), lower)
            let stripes = max(2, 2 * Int((L / 1.2).rounded() / 2))
            let sw = L / Float(stripes)
            for i in 0..<stripes {
                let c = i % 2 == 0 ? upper : upper * 0.93
                b.box(SIMD3(min(face, thick), 1.7, -Float(i + 1) * sw), SIMD3(max(face, thick), wallH, -Float(i) * sw),
                      c, top: white)
            }
            let inset = side * (wallX - 0.12)
            b.box(SIMD3(min(inset, face), 0, -L), SIMD3(max(inset, face), 0.32, 0), white)
            b.box(SIMD3(min(inset, face), 1.62, -L), SIMD3(max(inset, face), 1.8, 0), white)
            let crown = side * (wallX - 0.2)
            b.box(SIMD3(min(crown, face), wallH - 0.3, -L), SIMD3(max(crown, face), wallH, 0), white)
            // Pilaster at the start of each segment marks a new room (paint changes there).
            let pil = side * (wallX - 0.3)
            b.box(SIMD3(min(pil, face), 0, -0.5), SIMD3(max(pil, face), wallH + 0.1, 0), white)

            // Four bays along the wall, each with its own little scene.
            let bays = 4
            let bw = (L - 0.5) / Float(bays)
            for k in 0..<bays {
                let zc = -0.5 - bw * (Float(k) + 0.5)
                houseBay(b, &r, side: side, wallX: wallX, z: zc, width: bw, accent: lower)
                if r.chance(0.7) { houseExtras(b, &r, side: side, wallX: wallX, z: zc + r.f(-1, 1)) }
                if r.chance(0.55) {
                    picture(b, side: side, wallX: wallX, z: zc + r.f(-1, 1), y: 5.4, w: r.f(1.0, 1.6), h: 0.9, r: &r)
                }
            }
        }

        // Ceiling beams across the hall with pendant lamps. They frame the view like
        // the jungle branches. The lamps hang to 5.4 m, but beside the road.
        let beam = rgb(0xA8703F), shade = rgb(r.pick([0xFFD166, 0xFF8FA3, 0x7FD1C7, 0xFFFFFF])), cord = rgb(0x3A2F2F)
        for zb in [-L * 0.25, -L * 0.75] {
            b.box(SIMD3(-wallX - 0.1, wallH - 0.1, zb - 0.3), SIMD3(wallX + 0.1, wallH + 0.5, zb + 0.3), beam,
                  top: beam * 1.1)
            // No lamp over the middle lane: it would swing right through the camera.
            for lx: Float in [-4.2, 4.2] {
                b.box(SIMD3(lx - 0.03, 6.0, zb - 0.03), SIMD3(lx + 0.03, wallH - 0.1, zb + 0.03), cord)
                b.frustum(r0: 0.75, r1: 0.25, h: 0.6, sides: 10, shade, cap: shade, bottom: true,
                          translate(lx, 5.4, zb))
                b.blob(SIMD3(lx, 5.45, zb), SIMD3(0.28, 0.2, 0.28), rgb(0xFFF6C8), segments: 6, rings: 3)
            }
        }
    }

    private func houseBay(_ b: MeshBuilder, _ r: inout SeededRandom, side: Float, wallX: Float, z: Float,
                          width: Float, accent: SceneryRGB) {
        let S: Float = 3.0
        /// Put furniture with its back against the wall.
        func againstWall(_ name: String, dz: Float = 0, s: Float = S, gap: Float = 0.1) {
            guard let m = models[name] else { return }
            placeFacing(b, name, side: side, x: wallX - gap - m.size.z * s / 2, z: z + dz, s: s)
        }
        func onFloor(_ name: String, x: Float, dz: Float, s: Float = S, yaw: Float) {
            let rad = radius(name, s)
            place(b, name, x: side * max(x, 3.3 + rad), z: z + dz, s: s, yaw: yaw)
        }
        let rugYaw: Float = .pi / 2

        switch r.int(5) {
        case 0: // Doorway with a coat rack and a doormat.
            if let door = models["house_doorway"] {
                let s: Float = 2.8
                placeFacing(b, "house_doorway", side: side, x: wallX - door.size.z * s / 2 + 0.05, z: z, s: s)
            }
            againstWall("house_coatRackStanding", dz: 1.6, s: 2.6, gap: 0.5)
            onFloor("house_rugRounded", x: 5.8, dz: 0, s: 2.0, yaw: rugYaw)
            if r.chance(0.6) { onFloor("house_cardboardBoxClosed", x: 4.2, dz: -1.5, s: 2.2, yaw: r.f(-0.4, 0.4)) }
        case 1: // Window with curtains, sofa under it.
            window(b, side: side, wallX: wallX, z: z, w: 2.2, h: 2.0, y: 2.1, curtain: accent)
            againstWall(r.chance(0.5) ? "house_loungeSofa" : "house_loungeSofaLong", s: 2.7)
            againstWall("house_pottedPlant", dz: width / 2 - 0.6, s: 3.2)
            onFloor("house_rugRectangle", x: 4.4, dz: 0, s: 2.2, yaw: rugYaw)
            if r.chance(0.6) { onFloor("house_pillowBlue", x: 4.0, dz: -1.0, s: 2.4, yaw: r.f(0, 6.28)) }
        case 2: // Bookcases and a picture above.
            againstWall("house_bookcaseClosedWide", dz: -0.9, s: 2.6)
            againstWall(r.chance(0.5) ? "house_bookcaseOpen" : "house_bookcaseOpenLow", dz: 1.0, s: 2.6)
            picture(b, side: side, wallX: wallX, z: z + 1.0, y: 3.9, w: 1.3, h: 1.0, r: &r)
            if r.chance(0.7) { onFloor("house_books", x: 4.3, dz: 0.3, s: 2.4, yaw: r.f(0, 6.28)) }
        case 3: // Picture wall over a side table with a lamp, floor lamp and plant.
            picture(b, side: side, wallX: wallX, z: z - 0.8, y: 2.9, w: 1.4, h: 1.1, r: &r)
            picture(b, side: side, wallX: wallX, z: z + 0.9, y: 3.2, w: 1.0, h: 1.4, r: &r)
            if let t = models["house_sideTableDrawers"] {
                let s: Float = 2.6
                againstWall("house_sideTableDrawers", dz: 0, s: s)
                if let lamp = models["house_lampRoundTable"] {
                    let ls: Float = 2.4
                    place(b, "house_lampRoundTable", x: side * (wallX - 0.1 - t.size.z * s / 2), y: t.size.y * s,
                          z: z - 0.3, s: ls, yaw: 0)
                    _ = lamp
                }
            }
            againstWall("house_lampRoundFloor", dz: -width / 2 + 0.6, s: 3.0, gap: 0.3)
            againstWall(r.chance(0.5) ? "house_plantSmall1" : "house_plantSmall3", dz: width / 2 - 0.6, s: 3.2)
            onFloor("house_rugRound", x: 4.6, dz: 0, s: 2.2, yaw: 0)
        default: // TV corner with an armchair.
            window(b, side: side, wallX: wallX, z: z - 1.2, w: 1.4, h: 2.2, y: 2.2, curtain: accent)
            againstWall("house_cabinetTelevision", dz: 1.0, s: 2.6)
            if let c = models["house_cabinetTelevision"], models["house_televisionModern"] != nil {
                let s: Float = 2.6
                placeFacing(b, "house_televisionModern", side: side, x: wallX - 0.1 - c.size.z * s / 2,
                            y: c.size.y * s, z: z + 1.0, s: 2.4)
            }
            onFloor("house_loungeChair", x: 4.4, dz: -1.2, s: 2.5, yaw: side > 0 ? .pi / 2 + 0.5 : -.pi / 2 - 0.5)
            if r.chance(0.5) { onFloor("house_speaker", x: wallX - 0.6, dz: 2.3, s: 2.6, yaw: 0) }
        }
    }

    /// Cat things and small clutter in a bay: a cat bed, food bowls, a scratching
    /// post, toys on the floor, a wall clock, or a shelf of books.
    private func houseExtras(_ b: MeshBuilder, _ r: inout SeededRandom, side: Float, wallX: Float, z: Float) {
        let sisal = rgb(0xD9B36A), carpet = rgb(0xEBCFA0), dark = rgb(0x2F3A4A)
        switch r.int(6) {
        case 0: // Cat bed with a cushion.
            let x = side * 4.0
            let bed = rgb(r.pick([0x8CB8D8, 0xE8A0B0, 0xB8D8A0]))
            b.frustum(r0: 0.5, r1: 0.55, h: 0.22, sides: 12, bed, cap: bed, bottom: false, translate(x, 0.02, z))
            b.blob(SIMD3(x, 0.14, z), SIMD3(0.42, 0.1, 0.42), carpet, segments: 10, rings: 3)
        case 1: // Food and water bowls on a mat by the wall.
            let x = side * (wallX - 0.9)
            b.box(SIMD3(x - 0.45, 0.012, z - 0.3), SIMD3(x + 0.45, 0.027, z + 0.3), rgb(0x7FD1C7))
            b.frustum(r0: 0.16, r1: 0.2, h: 0.09, sides: 10, rgb(0xE8392F), cap: rgb(0x8A5A34), bottom: false,
                      translate(x, 0.03, z - 0.22))
            b.frustum(r0: 0.16, r1: 0.2, h: 0.09, sides: 10, rgb(0x3560C8), cap: rgb(0xBFE4F2), bottom: false,
                      translate(x, 0.03, z + 0.22))
        case 2: // A little scratching post.
            let x = side * 4.2
            b.box(SIMD3(x - 0.35, 0.02, z - 0.35), SIMD3(x + 0.35, 0.1, z + 0.35), carpet)
            b.frustum(r0: 0.1, r1: 0.1, h: 0.9, sides: 8, sisal, cap: sisal, bottom: false, translate(x, 0.1, z))
            b.frustum(r0: 0.26, r1: 0.26, h: 0.06, sides: 10, carpet, cap: carpet, bottom: false, translate(x, 1.0, z))
        case 3: // Toys: a ball, a felt mouse with a string tail, stacked blocks.
            let x = side * 3.9
            let ball = rgb(r.pick([0xFF5A5F, 0x3EC1D3, 0xFFC93C]))
            b.blob(SIMD3(x, 0.16, z), SIMD3(0.14, 0.14, 0.14), ball, segments: 8, rings: 4)
            b.blob(SIMD3(x + side * 0.5, 0.1, z + 0.5), SIMD3(0.14, 0.08, 0.09), rgb(0x9A9A9A), segments: 7, rings: 3)
            b.box(SIMD3(x + side * 0.5 - 0.01, 0.05, z + 0.58), SIMD3(x + side * 0.5 + 0.01, 0.07, z + 0.88), rgb(0xE8A0B0))
            let blocks: [UInt32] = [0xE8392F, 0xFFD23F, 0x3560C8]
            for (i, c) in blocks.enumerated() {
                let bx = x + side * 0.9 + Float(i) * 0.02, by = 0.02 + Float(i) * 0.24
                b.box(SIMD3(bx - 0.12, by, z - 0.82), SIMD3(bx + 0.12, by + 0.24, z - 0.58), rgb(c))
            }
        case 4: // Wall clock, face toward the hall.
            let t = translate(side * (wallX - 0.04), 4.6, z) * rotateZ(side > 0 ? .pi / 2 : -.pi / 2)
            b.frustum(r0: 0.42, r1: 0.42, h: 0.06, sides: 14, dark, cap: rgb(0xFFFFFF), bottom: true, t)
            b.box(SIMD3(-0.02, 0.06, -0.02), SIMD3(0.02, 0.08, 0.26), dark, t)
            b.box(SIMD3(-0.02, 0.06, -0.02), SIMD3(0.18, 0.08, 0.02), dark, t)
        default: // A shelf with a row of books.
            let x0 = side * (wallX - 0.3), x1 = side * wallX, inner = side * (wallX - 0.26)
            b.box(SIMD3(min(x0, x1), 3.4, z - 0.8), SIMD3(max(x0, x1), 3.46, z + 0.8), rgb(0xC98B55))
            let spines: [UInt32] = [0xE8392F, 0x3560C8, 0x2E9E55, 0xF08A24, 0x7A4FB8, 0xFFD23F]
            var bz = z - 0.7
            while bz < z + 0.6 {
                let w = r.f(0.08, 0.16), h = r.f(0.28, 0.4)
                b.box(SIMD3(min(inner, x1), 3.46, bz), SIMD3(max(inner, x1), 3.46 + h, bz + w), rgb(r.pick(spines)))
                bz += w + 0.01
            }
        }
    }

    private func window(_ b: MeshBuilder, side: Float, wallX: Float, z: Float, w: Float, h: Float, y: Float,
                        curtain: SceneryRGB) {
        let frame = rgb(0xFFFFFF), glass = rgb(0xAEE3FF), sky = rgb(0xD8F1FF)
        let f = side * (wallX - 0.06), g = side * (wallX - 0.02)
        func slab(_ z0: Float, _ z1: Float, _ y0: Float, _ y1: Float, _ x0: Float, _ x1: Float, _ c: SceneryRGB) {
            b.box(SIMD3(min(x0, x1), y0, min(z0, z1)), SIMD3(max(x0, x1), y1, max(z0, z1)), c)
        }
        slab(z - w / 2, z + w / 2, y, y + h, g, side * wallX, glass)
        slab(z - w / 2, z + w / 2, y + h * 0.55, y + h, side * (wallX - 0.03), g, sky)
        slab(z - w / 2 - 0.12, z + w / 2 + 0.12, y - 0.12, y, side * (wallX - 0.22), side * wallX, frame)
        slab(z - w / 2 - 0.12, z + w / 2 + 0.12, y + h, y + h + 0.12, f, side * wallX, frame)
        slab(z - w / 2 - 0.12, z - w / 2, y, y + h, f, side * wallX, frame)
        slab(z + w / 2, z + w / 2 + 0.12, y, y + h, f, side * wallX, frame)
        slab(z - 0.04, z + 0.04, y, y + h, f, side * wallX, frame)
        slab(z - w / 2, z + w / 2, y + h / 2 - 0.04, y + h / 2 + 0.04, f, side * wallX, frame)
        // Curtains hanging on both sides.
        let cx0 = side * (wallX - 0.25), cx1 = side * (wallX - 0.1)
        slab(z - w / 2 - 0.55, z - w / 2 + 0.05, y - 0.6, y + h + 0.45, cx0, cx1, curtain)
        slab(z + w / 2 - 0.05, z + w / 2 + 0.55, y - 0.6, y + h + 0.45, cx0, cx1, curtain)
        slab(z - w / 2 - 0.65, z + w / 2 + 0.65, y + h + 0.42, y + h + 0.52, side * (wallX - 0.3), side * wallX,
             rgb(0x8A5A34))
    }

    private func picture(_ b: MeshBuilder, side: Float, wallX: Float, z: Float, y: Float, w: Float, h: Float,
                         r: inout SeededRandom) {
        let frames: [UInt32] = [0xC98B55, 0x2F3A4A, 0xF2C14E, 0xFFFFFF]
        let arts: [UInt32] = [0xFF7A6B, 0x6BC6FF, 0x7ED957, 0xFFD166, 0xC792EA, 0xFF9FC7]
        let x0 = side * (wallX - 0.08), x1 = side * wallX
        func slab(_ z0: Float, _ z1: Float, _ y0: Float, _ y1: Float, _ xa: Float, _ c: SceneryRGB) {
            b.box(SIMD3(min(xa, x1), y0, min(z0, z1)), SIMD3(max(xa, x1), y1, max(z0, z1)), c)
        }
        slab(z - w / 2, z + w / 2, y - h / 2, y + h / 2, x0, rgb(r.pick(frames)))
        let inner = side * (wallX - 0.1)
        let bg = rgb(r.pick([0xFFF6E0, 0xE0F4FF, 0xFFE9F0]))
        slab(z - w / 2 + 0.1, z + w / 2 - 0.1, y - h / 2 + 0.1, y + h / 2 - 0.1, inner, bg)
        // Simple "art": a hill and a sun, or color blocks.
        let front = side * (wallX - 0.12)
        if r.chance(0.5) {
            slab(z - w / 2 + 0.1, z + w / 2 - 0.1, y - h / 2 + 0.1, y - h / 2 + 0.1 + h * 0.35, front, rgb(0x7ED957))
            slab(z + w * 0.1, z + w * 0.3, y + h * 0.08, y + h * 0.28, front, rgb(0xFFC93C))
        } else {
            slab(z - w / 2 + 0.2, z - 0.02, y - h / 2 + 0.2, y + h / 2 - 0.2, front, rgb(r.pick(arts)))
            slab(z + 0.02, z + w / 2 - 0.2, y - h / 2 + 0.2, y, front, rgb(r.pick(arts)))
        }
    }

    // MARK: - Farm

    private func buildFarm(_ b: MeshBuilder, _ L: Float, _ r: inout SeededRandom) {
        let shoulder = rgb(0xD9B57A), verge = rgb(0x7CCB4F)
        let fieldTypes: [(UInt32, UInt32)] = [
            (0xE8C45A, 0xD6AE45),   // wheat
            (0x6CC04A, 0x58AA3C),   // green crop
            (0x9C6B43, 0x86593A),   // plowed soil
            (0x8FD65E, 0x86CC57),   // pasture
        ]
        let farTrees = ["farm_tree_oak", "farm_tree_default", "farm_tree_fat", "farm_tree_detailed",
                        "farm_tree_oak_fall"]
        let feature = r.int(4)
        let featureSide: Float = r.chance(0.5) ? 1 : -1

        for side: Float in [-1, 1] {
            b.ground(side * 3.0, side * 3.5, 0, -L, y: 0.015, shoulder)
            b.ground(side * 3.5, side * 5.2, 0, -L, y: 0.01, verge)

            // White rail fence along the road.
            if let fence = models["farm_fence_simple"] {
                let n = max(1, Int((L / 3).rounded()))
                let s = L / Float(n) / fence.size.x
                for i in 0..<n {
                    placeFacing(b, "farm_fence_simple", side: side, x: 4.1, z: -(Float(i) + 0.5) * L / Float(n), s: s)
                }
            }

            // Near field (5.2..16) with real plants in rows, far field (16..42) as colored stripes.
            let near = r.int(3)
            let far = fieldTypes[r.int(fieldTypes.count)]
            let hasFeature = side == featureSide
            stripes(b, x0: 5.2, x1: 16, L: L, side: side,
                    colors: near == 2 ? (0xEAC85E, 0xD8B24A) : (0x9C6B43, 0x86593A))
            b.box(SIMD3(side > 0 ? 16 : -16.6, 0, -L), SIMD3(side > 0 ? 16.6 : -16, 0.9, 0), rgb(0x4FA53A),
                  top: rgb(0x5CB844))
            stripes(b, x0: 16.6, x1: 42, L: L, side: side, colors: far)

            let rowsX: [Float] = hasFeature ? [6.2, 7.7] : [6.2, 7.7, 9.2]
            switch near {
            case 0: // Corn
                cropRows(b, "farm_crops_cornStageD", rows: rowsX, side: side, L: L, spacing: 1.8, s: 2.5, r: &r)
            case 1: // Pumpkins and leafy rows
                cropRows(b, "farm_crop_pumpkin", rows: [rowsX[0]], side: side, L: L, spacing: 2.2, s: 2.2, r: &r)
                cropRows(b, "farm_crops_leafsStageB", rows: Array(rowsX.dropFirst()), side: side, L: L,
                         spacing: 1.2, s: 2.6, r: &r)
            default: // Wheat
                cropRows(b, "farm_crops_wheatStageB", rows: rowsX, side: side, L: L, spacing: 1.5, s: 2.2, r: &r)
            }

            // Trees scattered in the fields, and a line of them on the horizon.
            scatter(b, &r, farTrees, count: 3, side: side, x0: 17, x1: 30, L: L, s0: 7, s1: 10)
            scatter(b, &r, farTrees, count: 3, side: side, x0: 32, x1: 40, L: L, s0: 8, s1: 12)
            for _ in 0..<2 {
                let z = -r.f(4, L - 4)
                b.blob(SIMD3(side * r.f(34, 40), -1.5, z), SIMD3(r.f(9, 13), r.f(7, 10), r.f(6, 9)), rgb(0x6FBF4A),
                       segments: 8, rings: 4)
            }
            // Wooden power poles with sagging wires on the left side. Poles sit at a quarter
            // and three quarters of the segment, so spacing stays even across segments and
            // the wire meets the next segment's wire at the boundary.
            if side < 0 {
                let wood = rgb(0x8A5A34), wire = rgb(0x2E2A2A)
                let px: Float = -4.9, top: Float = 8.2, sag: Float = 0.9
                let poles = [-L * 0.25, -L * 0.75]
                for pz in poles {
                    b.box(SIMD3(px - 0.14, 0, pz - 0.14), SIMD3(px + 0.14, top + 0.4, pz + 0.14), wood)
                    b.box(SIMD3(px - 1.1, top - 0.1, pz - 0.1), SIMD3(px + 1.1, top + 0.1, pz + 0.1), wood)
                }
                // Wire height at distance t (0..1) along a span between two poles.
                func wireY(_ t: Float) -> Float { top - sag * (1 - pow(2 * t - 1, 2)) }
                let spans: [(Float, Float, Float, Float)] = [   // z0, z1, t0, t1
                    (0, poles[0], 0.5, 1), (poles[0], poles[1], 0, 1), (poles[1], -L, 0, 0.5),
                ]
                for wx: Float in [px - 0.9, px + 0.9] {
                    for (z0, z1, t0, t1) in spans {
                        let n = 6
                        for k in 0..<n {
                            let ta = t0 + (t1 - t0) * Float(k) / Float(n), tb = t0 + (t1 - t0) * Float(k + 1) / Float(n)
                            let za = z0 + (z1 - z0) * Float(k) / Float(n), zb = z0 + (z1 - z0) * Float(k + 1) / Float(n)
                            let a = SIMD3(wx, wireY(ta), za), c = SIMD3(wx, wireY(tb), zb)
                            b.quad(a - SIMD3(0.04, 0, 0), SIMD3(0.08, 0, 0), c - a, wire)
                            b.quad(a + SIMD3(0.04, 0, 0), SIMD3(-0.08, 0, 0), c - a, wire)
                        }
                    }
                }
            }

            // Little things by the fence.
            scatter(b, &r, ["farm_flower_yellowA", "farm_flower_redB", "farm_grass_large", "farm_plant_bush"],
                    count: 8, side: side, x0: 3.4, x1: 3.8, L: L, s0: 2, s1: 3)
            // Sunflowers behind the fence, a water trough, a scarecrow, haystacks, hens.
            if r.chance(0.5) {
                var sz: Float = -r.f(1, 3)
                while sz > -L + 1 {
                    sunflower(b, side: side, x: 4.7 + r.f(-0.2, 0.2), z: sz, h: r.f(1.5, 2.2), r: &r)
                    sz -= r.f(1.0, 1.6)
                }
            }
            if r.chance(0.4) { trough(b, side: side, x: 6.0, z: -L * r.f(0.2, 0.8)) }
            if r.chance(0.35) { scarecrow(b, side: side, x: r.f(7, 10), z: -L * r.f(0.2, 0.8), r: &r) }
            if r.chance(0.4) {
                for _ in 0..<(r.int(2) + 1) { haystack(b, x: side * r.f(10, 14), z: -L * r.f(0.15, 0.85)) }
            }
            if r.chance(0.5) {
                for _ in 0..<3 { hen(b, x: side * r.f(5.4, 8), z: -L * r.f(0.1, 0.9), r: &r) }
            }

            if hasFeature {
                let z = -L * 0.5
                switch feature {
                case 0: barn(b, side: side, x: 13, z: z); silo(b, x: side * 20, z: z - 7)
                case 1: windmill(b, side: side, x: 14, z: z, r: &r)
                case 2:
                    for i in 0..<4 { hayBale(b, x: side * (11 + Float(i % 2) * 2.2), z: z - 4 + Float(i) * 2.4, r: &r) }
                    place(b, "town_cart", x: side * 13.5, z: z + 6, s: 3.2, yaw: side * .pi / 2 + 0.3)
                default:
                    place(b, "town_stall_red", x: side * 12, z: z, s: 3.2, yaw: side > 0 ? -.pi / 2 : .pi / 2)
                    for i in 0..<3 {
                        place(b, "farm_crop_pumpkin", x: side * 11.5, z: z - 3 - Float(i) * 1.2, s: 2.2,
                              yaw: r.f(0, 6))
                    }
                    silo(b, x: side * 20, z: z - 5)
                }
            } else if r.chance(0.5) {
                for i in 0..<r.int(3) + 1 { hayBale(b, x: side * r.f(12, 15), z: -L * 0.3 - Float(i) * 2.5, r: &r) }
            }
        }
    }

    private func stripes(_ b: MeshBuilder, x0: Float, x1: Float, L: Float, side: Float, colors: (UInt32, UInt32)) {
        let a = rgb(colors.0), c = rgb(colors.1)
        let n = max(2, Int(((x1 - x0) / 1.4).rounded()))
        let w = (x1 - x0) / Float(n)
        for i in 0..<n {
            let xa = x0 + Float(i) * w
            b.ground(side * xa, side * (xa + w), 0, -L, y: 0.02, i % 2 == 0 ? a : c)
        }
    }

    private func cropRows(_ b: MeshBuilder, _ name: String, rows: [Float], side: Float, L: Float, spacing: Float,
                          s: Float, r: inout SeededRandom) {
        guard models[name] != nil else { return }
        let n = max(1, Int(L / spacing))
        let dz = L / Float(n)
        for x in rows {
            for i in 0..<n {
                place(b, name, x: side * x, z: -(Float(i) + 0.5) * dz + r.f(-0.15, 0.15),
                      s: s * r.f(0.9, 1.1), yaw: r.f(0, 6.28))
            }
        }
    }

    private func barn(_ b: MeshBuilder, side: Float, x: Float, z: Float) {
        let red = rgb(0xD8453A), roof = rgb(0x5B4A4A), white = rgb(0xFFFFFF)
        let w: Float = 10, d: Float = 8, h: Float = 5.5, rh: Float = 3.2
        // Built in a frame where +z faces the road.
        let t = translate(side * (x + d / 2), 0, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2)
        b.box(SIMD3(-w / 2, 0, -d / 2), SIMD3(w / 2, h, d / 2), red, t)
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { let q = t * SIMD4(x, y, z, 1); return SIMD3(q.x, q.y, q.z) }
        // Gable roof, ridge running along the road.
        let o: Float = 0.5
        b.quad(P(-w / 2 - o, h - 0.3, d / 2 + o), P(w / 2 + o, h - 0.3, d / 2 + o) - P(-w / 2 - o, h - 0.3, d / 2 + o),
               P(-w / 2 - o, h + rh, 0) - P(-w / 2 - o, h - 0.3, d / 2 + o), roof)
        b.quad(P(w / 2 + o, h - 0.3, -d / 2 - o), P(-w / 2 - o, h - 0.3, -d / 2 - o) - P(w / 2 + o, h - 0.3, -d / 2 - o),
               P(w / 2 + o, h + rh, 0) - P(w / 2 + o, h - 0.3, -d / 2 - o), roof * 0.85)
        b.tri(P(w / 2, h, d / 2), P(w / 2, h, -d / 2), P(w / 2, h + rh - 0.2, 0), red)
        b.tri(P(-w / 2, h, -d / 2), P(-w / 2, h, d / 2), P(-w / 2, h + rh - 0.2, 0), red)
        // Big white-trimmed doors with the X brace.
        let dw: Float = 4.2, dh: Float = 4.2
        b.box(SIMD3(-dw / 2 - 0.2, 0, d / 2), SIMD3(dw / 2 + 0.2, dh + 0.2, d / 2 + 0.05), white, t)
        b.box(SIMD3(-dw / 2, 0, d / 2 + 0.05), SIMD3(dw / 2, dh, d / 2 + 0.1), red * 0.85, t)
        let diag = sqrt(dw * dw + dh * dh)
        for sgn: Float in [-1, 1] {
            let a = atan2(dh, dw) * sgn
            b.box(SIMD3(-diag / 2, -0.12, 0), SIMD3(diag / 2, 0.12, 0.08), white,
                  t * translate(0, dh / 2, d / 2 + 0.1) * rotateZ(a))
        }
        // Loft window and corner trim.
        b.box(SIMD3(-0.8, h + 0.3, d / 2 - 0.1), SIMD3(0.8, h + 1.7, d / 2 + 0.06), white, t)
        b.box(SIMD3(-0.6, h + 0.5, d / 2), SIMD3(0.6, h + 1.5, d / 2 + 0.1), rgb(0x3A2F2F), t)
        for cx in [-w / 2, w / 2] {
            b.box(SIMD3(cx - 0.2, 0, d / 2 - 0.2), SIMD3(cx + 0.2, h, d / 2 + 0.08), white, t)
        }
    }

    private func silo(_ b: MeshBuilder, x: Float, z: Float) {
        let body = rgb(0xD9E2EA), band = rgb(0xAFBFCC), dome = rgb(0xE8453C)
        b.frustum(r0: 2.0, r1: 2.0, h: 11, sides: 12, body, _: translate(x, 0, z))
        for y: Float in [2.5, 5.5, 8.5] {
            b.frustum(r0: 2.05, r1: 2.05, h: 0.25, sides: 12, band, _: translate(x, y, z))
        }
        b.blob(SIMD3(x, 11, z), SIMD3(2.1, 1.6, 2.1), dome, segments: 12, rings: 4)
    }

    private func windmill(_ b: MeshBuilder, side: Float, x: Float, z: Float, r: inout SeededRandom) {
        let body = rgb(0xFFF4E0), roof = rgb(0xD8453A), door = rgb(0x8A5A34)
        b.frustum(r0: 2.4, r1: 1.5, h: 9, sides: 8, body, _: translate(side * x, 0, z))
        b.frustum(r0: 1.9, r1: 0, h: 2.6, sides: 8, roof, _: translate(side * x, 9, z))
        b.box(SIMD3(-0.6, 0, -0.1), SIMD3(0.6, 2.0, 0.1), door,
              translate(side * (x - 2.3), 0, z) * rotateY(.pi / 2))
        if let blades = models["town_windmill_blades"] {
            let s: Float = 3.4
            // The blades model spins about x. Put the hub on the road-facing side of the cap.
            b.add(blades, translate(side * (x - 2.0), 8.6, z) * rotateX(r.f(0, 1.5)) * scale(s, s, s))
        }
    }

    /// A sunflower facing the road: stem, two leaves, a disc of petals with a brown heart.
    private func sunflower(_ b: MeshBuilder, side: Float, x: Float, z: Float, h: Float, r: inout SeededRandom) {
        let stem = rgb(0x4E9630), petal = rgb(0xFFD23F), heart = rgb(0x5A3A1E)
        let px = side * x
        b.box(SIMD3(px - 0.04, 0, z - 0.04), SIMD3(px + 0.04, h, z + 0.04), stem)
        for lz: Float in [-1, 1] {
            let a = SIMD3<Float>(px, h * 0.45, z)
            let c = SIMD3<Float>(px, h * 0.5, z + lz * 0.45)
            let d = SIMD3<Float>(px + side * 0.05, h * 0.62, z + lz * 0.2)
            b.tri(a, c, d, stem)
            b.tri(a, d, c, stem * 0.9)
        }
        let t = translate(px, h, z) * rotateZ(side > 0 ? .pi / 2 : -.pi / 2)
        b.frustum(r0: 0.34, r1: 0.34, h: 0.04, sides: 12, petal, cap: petal, bottom: true, t)
        b.frustum(r0: 0.19, r1: 0.19, h: 0.05, sides: 12, heart, cap: heart, bottom: true, t * translate(0, 0.04, 0))
    }

    private func trough(_ b: MeshBuilder, side: Float, x: Float, z: Float) {
        let steel = rgb(0x9AA6B0), water = rgb(0x8FD0E8)
        let px = side * x
        b.box(SIMD3(px - 0.45, 0, z - 0.9), SIMD3(px + 0.45, 0.55, z + 0.9), steel)
        b.box(SIMD3(px - 0.38, 0.55, z - 0.83), SIMD3(px + 0.38, 0.565, z + 0.83), water)
    }

    private func scarecrow(_ b: MeshBuilder, side: Float, x: Float, z: Float, r: inout SeededRandom) {
        let wood = rgb(0x8A5A34), straw = rgb(0xE8C45A), hat = rgb(0x5A3A1E)
        let shirt = rgb(r.pick([0xD8453A, 0x3560C8, 0x2E9E55]))
        let t = translate(side * x, 0, z) * rotateY(side > 0 ? -.pi / 2 : .pi / 2)
        b.box(SIMD3(-0.07, 0, -0.07), SIMD3(0.07, 2.6, 0.07), wood, t)
        b.box(SIMD3(-1.0, 1.9, -0.06), SIMD3(1.0, 2.0, 0.06), wood, t)
        b.box(SIMD3(-0.42, 1.1, -0.2), SIMD3(0.42, 2.05, 0.2), shirt, t)
        b.box(SIMD3(-1.0, 1.78, -0.14), SIMD3(1.0, 2.08, 0.14), shirt * 0.95, t)
        for hx: Float in [-1.0, 1.0] {
            b.box(SIMD3(hx - 0.1, 1.72, -0.1), SIMD3(hx + 0.1, 1.84, 0.1), straw, t)
        }
        b.blob(SIMD3(side * x, 2.35, z), SIMD3(0.28, 0.3, 0.28), straw, segments: 8, rings: 4)
        b.frustum(r0: 0.5, r1: 0.5, h: 0.04, sides: 10, hat, cap: hat, bottom: true, translate(side * x, 2.56, z))
        b.frustum(r0: 0.28, r1: 0.24, h: 0.3, sides: 10, hat, cap: hat, bottom: false, translate(side * x, 2.6, z))
    }

    private func haystack(_ b: MeshBuilder, x: Float, z: Float) {
        let hay = rgb(0xF2CF5B), dark = rgb(0xD9B244)
        b.frustum(r0: 1.5, r1: 1.2, h: 0.9, sides: 10, dark, cap: dark, bottom: false, translate(x, 0, z))
        b.frustum(r0: 1.25, r1: 0.15, h: 1.9, sides: 10, hay, cap: hay, bottom: false, translate(x, 0.9, z))
    }

    /// A hen pecking about: a body, a head, a red comb, a beak.
    private func hen(_ b: MeshBuilder, x: Float, z: Float, r: inout SeededRandom) {
        let body = rgb(r.pick([0xFFFFFF, 0xD9823A, 0x3A3A3A])), comb = rgb(0xE8392F), beak = rgb(0xFFB13F)
        let a = r.f(0, 6.28)
        let dx = cos(a) * 0.22, dz = -sin(a) * 0.22
        b.blob(SIMD3(x, 0.26, z), SIMD3(0.24, 0.2, 0.3), body, segments: 7, rings: 4)
        b.blob(SIMD3(x + dx, 0.5, z + dz), SIMD3(0.11, 0.11, 0.11), body, segments: 6, rings: 3)
        b.blob(SIMD3(x + dx, 0.62, z + dz), SIMD3(0.04, 0.06, 0.08), comb, segments: 5, rings: 3)
        b.blob(SIMD3(x + dx * 1.5, 0.48, z + dz * 1.5), SIMD3(0.05, 0.03, 0.05), beak, segments: 5, rings: 3)
    }

    private func hayBale(_ b: MeshBuilder, x: Float, z: Float, r: inout SeededRandom) {
        let hay = rgb(0xF2CF5B), end = rgb(0xE0B544)
        // Round bale lying on its side, axis along the road.
        b.frustum(r0: 0.85, r1: 0.85, h: 1.5, sides: 10, hay, cap: end, bottom: true,
                  translate(x, 0.85, z + 0.75) * rotateX(-.pi / 2) * rotateY(r.f(0, 1)))
    }
}
