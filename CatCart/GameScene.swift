import SceneKit
import SpriteKit
import UIKit

// Cat Cart. This file is the game: the 3D world, the rules, the camera, and input.
// Hud.swift draws the pills and panels on top. Scenery.swift builds the roadside
// for each world out of 3D models.
//
// How the world works:
// - Real 3D in meters. +y is up. The cat sits at z = 0. Ahead of her is -z.
// - The cat never moves forward. The whole track (road, scenery, coyotes, food,
//   cat trees) slides toward +z every frame at one shared speed. The camera's
//   perspective makes near things rush and far things crawl, so everything that
//   sits on the road leaves the screen together. No per-object speed tricks.
// - A shader bends everything down with distance ("curved world"), so the road
//   rolls away over the horizon like Subway Surfers. The same shader adds fog.
// - The cat, coyotes, and food are flat pictures standing in the 3D world
//   ("billboards"). The cat trees are real 3D boxes, so their roof is obviously
//   something you can ride.
//
// SceneKit calls renderer(_:updateAtTime:) once per frame. That's our game loop.
// It runs on SceneKit's render thread, so touches (main thread) are queued and
// handled at the start of the next frame.

final class GameScene: NSObject, SCNSceneRendererDelegate {

    private enum State {
        case ready
        case running
        case dead
    }

    private enum Kind {
        case coyote
        case food
        case tree
    }

    private enum Intent {
        case tap, left, right, up, down
    }

    /// One thing on the track. `z` is its front edge (the end nearest the cat).
    /// A cat tree also has a length that stretches away from the cat, toward -z.
    private final class TrackItem {
        let kind: Kind
        let lane: Int
        let node: SCNNode
        var z: Float
        var length: Float = 0
        var picture: SCNMaterial?
        var frame = 0
        var frameClock: Float = 0
        var back: Float { z - length }

        init(kind: Kind, lane: Int, node: SCNNode, z: Float) {
            self.kind = kind
            self.lane = lane
            self.node = node
            self.z = z
        }
    }

    /// One 24 m slice of road plus the roadside for one world.
    private final class Segment {
        let node: SCNNode
        let world: WorldKind
        var inUse = false
        /// z of the near edge. The slice covers near - length ... near.
        var near: Float { node.position.z }

        init(node: SCNNode, world: WorldKind) {
            self.node = node
            self.world = world
        }
    }

    /// Everything that changes color when you drive into a new world.
    private struct WorldLook {
        let sky: String
        let fog: SIMD3<Float>
        let sun: SIMD3<Float>
        let ambient: SIMD3<Float>
    }

    private struct Spawn {
        let kind: Kind
        let lane: Int
        /// Extra meters further ahead than the wave's front.
        let ahead: Float
        /// Food that sits on a cat tree's roof.
        var onRoof = false
    }

    /// Best distance, saved on the phone. The 2D build counted "meters" about 7x faster
    /// under the key "bestMeters", so the 3D build keeps real meters under a new key.
    private static let bestKey = "bestMeters3D"

    // MARK: - Tuning (meters and seconds)

    private let laneSpacing: Float = 1.9
    private let segmentLength: Float = 24
    /// Coyotes, food, and trees appear this far ahead, inside the fog.
    private let spawnAhead: Float = 118
    /// The road is built out to here so the horizon never shows a gap.
    private let trackDepth: Float = 190
    /// Anything this far behind the cat is off camera and gets recycled.
    private let trackBehind: Float = 10
    private let roofY: Float = 1.5
    private let jumpPeak: Float = 2.1
    /// Above this height a coyote passes under you and a tree front is a landing, not a crash.
    private let clearHeight: Float = 0.7
    private let worldSeconds: Float = 10

    private let cameraBase = SIMD3<Float>(0, 2.9, 4.4)
    private let cameraPitch: Float = -0.055
    private let baseFOV: CGFloat = 56

    /// Running speed in meters per second. Starts friendly, speeds up as you survive.
    private func runSpeed() -> Float {
        min(30, 17 + timeAlive * 0.22)
    }

    // MARK: - Shaders

    // Curved world. Every vertex drops by k * d^2, where d is how far ahead of the cat
    // it is, so the road rolls over a hill. A slow sideways sway makes it feel like the
    // street bends left and right. Runs on the GPU for every 3D thing we draw.
    private static let bendModifier = """
    float4 wp = scn_node.modelTransform * _geometry.position;
    float d = max(0.0, -wp.z - 10.0);
    wp.y -= 0.0011 * d * d;
    wp.x += sin(scn_frame.time * 0.11) * 0.0007 * d * d;
    _geometry.position = scn_node.inverseModelTransform * wp;
    """

    // Fog. Far pixels fade into the world's horizon color, which is also the bottom
    // of the sky picture, so the ground melts into the sky with no seam.
    private static let fogModifier = """
    #pragma arguments
    float3 fogColor;
    #pragma body
    float dist = length(_surface.position);
    float f = clamp((dist - 32.0) / 88.0, 0.0, 1.0);
    _output.color.rgb = mix(_output.color.rgb, fogColor * _output.color.a, f);
    """

    // MARK: - Scene objects

    private weak var view: GameSCNView?
    private let scene = SCNScene()
    private let hud: Hud
    private let scenery: SceneryLibrary

    private let cameraNode = SCNNode()
    private let skyA = SCNNode()
    private let skyB = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()

    private let playerRoot = SCNNode()
    private var catNode: SCNNode!
    private var catShadow: SCNNode!
    private var dust: SCNParticleSystem!

    private var segments: [Segment] = []
    private var segmentPool: [WorldKind: [Segment]] = [:]
    private var items: [TrackItem] = []
    private var itemPool: [String: [SCNNode]] = [:]

    private var lookMaterials: [SCNMaterial] = []
    private var lookSeen = Set<ObjectIdentifier>()
    private var fogNow = SIMD3<Float>(1, 1, 1)
    private var skyAWorld: WorldKind?
    private var skyBWorld: WorldKind?

    private lazy var roadMaterials: [WorldKind: SCNMaterial] = {
        var out: [WorldKind: SCNMaterial] = [:]
        for world in WorldKind.allCases {
            let m = SCNMaterial()
            m.diffuse.contents = UIImage(named: world.roadName) ?? world.roadFallback
            m.diffuse.wrapS = .clamp
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(1, segmentLength / 6, 1)
            Self.smoothSampling(m.diffuse)
            m.lightingModel = .lambert
            out[world] = m
        }
        return out
    }()

    private lazy var coyoteFrames: [UIImage] = {
        ["coyoteOpen", "coyoteMid", "coyoteClosed", "coyoteMid"].compactMap { UIImage(named: $0) }
    }()

    private lazy var shadowMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = UIImage(named: "blobShadow") ?? Self.drawBlob()
        m.lightingModel = .constant
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        Self.smoothSampling(m.diffuse)
        return m
    }()

    private lazy var puffImage: UIImage = UIImage(named: "puffDot") ?? Self.drawPuff()

    // MARK: - Game state

    private var state: State = .ready
    private var lane = 1
    private var visualX: Float = 0
    private var tilt: Float = 0
    private var jumping = false
    private var height: Float = 0
    private var hangLeft: Float = 0
    private var wasAirborne = false
    private var onPlatform = false
    private var cameraLift: Float = 0
    private var landSquash: Float = 0

    private var timeAlive: Float = 0
    private var meters: Float = 0
    private var food = 0
    private var bestMeters: Float = 0
    private var untilWave: Float = 30
    private var lineClock: Float = 0
    private var lastTime: TimeInterval = 0

    private var startWorld = 0
    private var genWorld = 0
    private var genSegmentsLeft = 0
    private var genSeed = 0

    private var inputLock = NSLock()
    private var pending: [Intent] = []
    private var swipeStart: CGPoint?
    private var swipeConsumed = false

    private let e2eAutoRun = ProcessInfo.processInfo.environment["CATCART_AUTO_RUN"] == "1"
    private let e2eGod = ProcessInfo.processInfo.environment["CATCART_GOD"] == "1"
    private let e2ePilot = ProcessInfo.processInfo.environment["CATCART_PILOT"] == "1"

    private var isHighEnough: Bool { height > clearHeight || onPlatform }
    private var floorY: Float { onPlatform ? roofY : 0 }

    // MARK: - Setup

    init(view: GameSCNView) {
        self.view = view
        self.hud = Hud(size: CGSize(width: 390, height: 844))
        self.scenery = SceneryLibrary()
        super.init()
        bestMeters = Float(UserDefaults.standard.double(forKey: Self.bestKey))
        switch ProcessInfo.processInfo.environment["CATCART_WORLD"]?.lowercased() {
        case "jungle": startWorld = 1
        case "house": startWorld = 2
        case "farm": startWorld = 3
        default: startWorld = 0
        }

        buildCamera()
        buildLights()
        buildPlayer()
        prewarmSegments()
        resetTrack()

        view.game = self
        view.scene = scene
        view.delegate = self
        view.overlaySKScene = hud
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor(look(currentPlayerWorld()).fog)
        view.isMultipleTouchEnabled = false

        hud.showReady()
        if e2eAutoRun {
            startRun()
        }
        if ProcessInfo.processInfo.environment["CATCART_STATS"] == "1" {
            view.showsStatistics = true
        }
        scheduleTestSwipes()
    }

    /// Test-only: CATCART_SWIPES="2:left,3.5:up,5:right" plays swipes at those
    /// seconds after launch through the same touch code a finger uses.
    private func scheduleTestSwipes() {
        guard let script = ProcessInfo.processInfo.environment["CATCART_SWIPES"] else { return }
        for step in script.split(separator: ",") {
            let parts = step.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[0]) else { continue }
            let move: CGPoint
            switch parts[1] {
            case "left": move = CGPoint(x: -80, y: 0)
            case "right": move = CGPoint(x: 80, y: 0)
            case "up": move = CGPoint(x: 0, y: -80)
            case "down": move = CGPoint(x: 0, y: 80)
            default: continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                let start = CGPoint(x: 200, y: 500)
                self?.touchBegan(at: start)
                self?.touchMoved(to: CGPoint(x: start.x + move.x, y: start.y + move.y), minimum: 22)
                self?.touchEnded()
            }
        }
    }

    func viewDidLayout(size: CGSize, topSafe: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        hud.size = size
        hud.layout(topSafe: topSafe)
        sizeSky(aspect: Float(size.height / size.width))
    }

    private func buildCamera() {
        let camera = SCNCamera()
        // Portrait phone: fix the horizontal view so the road fits the width.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = baseFOV
        camera.zNear = 0.3
        camera.zFar = 260
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(cameraBase.x, cameraBase.y, cameraBase.z)
        cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // The sky is two big pictures hung far in front of the camera. B fades in
        // over A as you drive toward the next world.
        for (node, order) in [(skyA, -100), (skyB, -99)] {
            let plane = SCNPlane(width: 1, height: 1)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            plane.materials = [m]
            node.geometry = plane
            node.renderingOrder = order
            node.position = SCNVector3(0, 0, -200)
            cameraNode.addChildNode(node)
        }
        skyB.opacity = 0
        sizeSky(aspect: 844 / 390)
    }

    private func sizeSky(aspect: Float) {
        let halfW = tan(Float(baseFOV + 14) * .pi / 360) * 200
        let w = CGFloat(halfW * 2 * 1.1)
        let h = CGFloat(halfW * 2 * aspect * 1.1)
        for node in [skyA, skyB] {
            (node.geometry as? SCNPlane)?.width = w
            (node.geometry as? SCNPlane)?.height = h
        }
    }

    private func buildLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowColor = UIColor(white: 0, alpha: 0.32)
        sun.shadowRadius = 2
        sun.shadowSampleCount = 4
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.maximumShadowDistance = 55
        sun.shadowCascadeCount = 2
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.95, 0.55, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func buildPlayer() {
        scene.rootNode.addChildNode(playerRoot)

        catShadow = SCNNode(geometry: groundPlane(width: 1.7, length: 1.3, material: shadowMaterial))
        catShadow.position = SCNVector3(0, 0.03, 0)
        catShadow.renderingOrder = 5
        playerRoot.addChildNode(catShadow)

        // The kitten in the La Croix cart, seen from behind.
        catNode = billboard(image: UIImage(named: "playerBack"), width: 1.35)
        catNode.childNode(withName: "picture", recursively: false)?.renderingOrder = 3000
        playerRoot.addChildNode(catNode)

        // Dust kicked up by the wheels. Particles live in the world, not on the cart,
        // and drift toward the camera, so they trail behind her.
        dust = SCNParticleSystem()
        dust.particleImage = puffImage
        dust.birthRate = 22
        dust.particleLifeSpan = 0.45
        dust.particleLifeSpanVariation = 0.15
        dust.particleSize = 0.12
        dust.particleSizeVariation = 0.05
        dust.particleColor = UIColor(white: 1, alpha: 0.4)
        dust.emittingDirection = SCNVector3(0, 0.35, 1)
        dust.spreadingAngle = 25
        dust.particleVelocity = 4.5
        dust.particleVelocityVariation = 1.5
        dust.emitterShape = SCNBox(width: 1.1, height: 0.02, length: 0.1, chamferRadius: 0)
        dust.blendMode = .alpha
        dust.isLocal = false
        dust.propertyControllers = [.opacity: Self.fadeOutController()]
        let dustNode = SCNNode()
        dustNode.position = SCNVector3(0, 0.08, 0.35)
        dustNode.addParticleSystem(dust)
        playerRoot.addChildNode(dustNode)

        placePlayer()
    }

    private func placePlayer() {
        visualX = laneX(lane)
        playerRoot.position = SCNVector3(visualX, 0, 0)
        catNode.position = SCNVector3(0, 0, 0)
        catNode.eulerAngles = SCNVector3Zero
        catNode.scale = SCNVector3(1, 1, 1)
    }

    private func laneX(_ lane: Int) -> Float {
        Float(lane - 1) * laneSpacing
    }

    // MARK: - Building blocks

    /// A flat picture standing upright in the world, bottom edge at the node's origin.
    private func billboard(image: UIImage?, width: CGFloat) -> SCNNode {
        let aspect = (image?.size.height ?? 1) / max(image?.size.width ?? 1, 1)
        let h = width * aspect
        let plane = SCNPlane(width: width, height: h)
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.blendMode = .alpha
        Self.smoothSampling(m.diffuse)
        plane.materials = [m]
        let holder = SCNNode()
        let pic = SCNNode(geometry: plane)
        pic.name = "picture"
        pic.position = SCNVector3(0, Float(h / 2), 0)
        pic.castsShadow = false
        holder.addChildNode(pic)
        applyLook(to: holder)
        return holder
    }

    /// A flat rectangle lying on the ground, centered on the node.
    private func groundPlane(width: CGFloat, length: CGFloat, material: SCNMaterial) -> SCNGeometry {
        let plane = SCNPlane(width: width, height: length)
        // Cut long strips into ~3 m pieces so the curved-world bend can bend them.
        // One flat piece would stay straight and drift away from the sidewalks.
        plane.heightSegmentCount = max(1, Int((length / 3).rounded()))
        plane.materials = [material]
        // Flattening bakes in the children's transforms, not the node's own,
        // so the plane is laid flat as a child and the parent gets flattened.
        let lying = SCNNode(geometry: plane)
        lying.eulerAngles.x = -.pi / 2
        let holder = SCNNode()
        holder.addChildNode(lying)
        let flat = holder.flattenedClone()
        flat.geometry?.materials = [material]
        return flat.geometry ?? plane
    }

    /// Gives every material the curved-world bend and the fog. Each material is
    /// only touched once, even if a hundred copies of a building share it.
    private func applyLook(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for m in geometry.materials where !lookSeen.contains(ObjectIdentifier(m)) {
                lookSeen.insert(ObjectIdentifier(m))
                m.shaderModifiers = [.geometry: Self.bendModifier, .fragment: Self.fogModifier]
                m.setValue(NSValue(scnVector3: SCNVector3(fogNow.x, fogNow.y, fogNow.z)), forKey: "fogColor")
                lookMaterials.append(m)
            }
        }
    }

    private static func smoothSampling(_ p: SCNMaterialProperty) {
        // Mipmaps keep far-away texture detail from shimmering.
        p.mipFilter = .linear
        p.minificationFilter = .linear
        p.magnificationFilter = .linear
        p.maxAnisotropy = 8
    }

    private static func fadeOutController() -> SCNParticlePropertyController {
        let fade = CAKeyframeAnimation()
        fade.values = [0.9, 0.6, 0]
        fade.keyTimes = [0, 0.4, 1]
        return SCNParticlePropertyController(animation: fade)
    }

    // MARK: - Worlds

    private func look(_ world: WorldKind) -> WorldLook {
        switch world {
        case .city:
            return WorldLook(sky: "skyCity", fog: Self.rgb(0xF2C9A5), sun: SIMD3(1.0, 0.93, 0.82), ambient: SIMD3(0.62, 0.60, 0.66))
        case .jungle:
            return WorldLook(sky: "skyJungle", fog: Self.rgb(0xCFD89E), sun: SIMD3(1.0, 0.96, 0.80), ambient: SIMD3(0.55, 0.64, 0.55))
        case .house:
            return WorldLook(sky: "skyHouse", fog: Self.rgb(0xF3E2C6), sun: SIMD3(1.0, 0.92, 0.80), ambient: SIMD3(0.70, 0.64, 0.58))
        case .farm:
            return WorldLook(sky: "skyFarm", fog: Self.rgb(0xCDE7F6), sun: SIMD3(1.0, 0.97, 0.88), ambient: SIMD3(0.60, 0.64, 0.70))
        }
    }

    private static func rgb(_ hex: Int) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    private func worldAt(_ index: Int) -> WorldKind {
        WorldKind.allCases[index % WorldKind.allCases.count]
    }

    private func currentPlayerWorld() -> WorldKind {
        segments.first { $0.near >= 0 && $0.near - segmentLength < 0 }?.world ?? worldAt(startWorld)
    }

    /// Drive-into-it world change. As the first slice of the next world gets close,
    /// the sky, fog, and light blend toward it, and finish as the cat crosses over.
    private func updateWorldBlend() {
        let here = currentPlayerWorld()
        var next = here
        var t: Float = 0
        if let border = segments.first(where: { $0.world != here && $0.near < 0 }) {
            next = border.world
            let dist = -border.near
            let raw = max(0, min(1, 1 - dist / 70))
            t = raw * raw * (3 - 2 * raw)
        }
        let a = look(here)
        let b = look(next)

        if skyAWorld != here {
            skyAWorld = here
            skyA.geometry?.firstMaterial?.diffuse.contents = UIImage(named: a.sky) ?? UIColor(a.fog)
        }
        if skyBWorld != next {
            skyBWorld = next
            skyB.geometry?.firstMaterial?.diffuse.contents = UIImage(named: b.sky) ?? UIColor(b.fog)
        }
        skyB.opacity = CGFloat(t)

        let fog = mix(a.fog, b.fog, t: t)
        if fog != fogNow {
            fogNow = fog
            let value = NSValue(scnVector3: SCNVector3(fog.x, fog.y, fog.z))
            for m in lookMaterials { m.setValue(value, forKey: "fogColor") }
            view?.backgroundColor = UIColor(fog)
        }
        sunNode.light?.color = UIColor(mix(a.sun, b.sun, t: t))
        ambientNode.light?.color = UIColor(mix(a.ambient, b.ambient, t: t))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    // MARK: - Track

    private func resetTrack() {
        for seg in segments {
            seg.node.removeFromParentNode()
            seg.inUse = false
        }
        segments.removeAll()
        genWorld = startWorld
        // The first world also covers the slices already behind the cat.
        genSegmentsLeft = segmentsPerWorld() + Int(((trackBehind + segmentLength) / segmentLength).rounded(.up))
        var near = trackBehind + segmentLength
        while near - segmentLength > -trackDepth {
            addSegment(near: near)
            near -= segmentLength
        }
        skyAWorld = nil
        skyBWorld = nil
        updateWorldBlend()
    }

    /// How many 24 m slices make about 10 seconds at the current speed.
    private func segmentsPerWorld() -> Int {
        max(5, Int((worldSeconds * runSpeed() / segmentLength).rounded()))
    }

    private func addSegment(near: Float) {
        if genSegmentsLeft <= 0 {
            genWorld += 1
            genSegmentsLeft = segmentsPerWorld()
        }
        genSegmentsLeft -= 1
        let seg = takeSegment(worldAt(genWorld))
        seg.node.position = SCNVector3(0, 0, near)
        scene.rootNode.addChildNode(seg.node)
        segments.append(seg)
    }

    private func takeSegment(_ world: WorldKind) -> Segment {
        if let free = segmentPool[world]?.first(where: { !$0.inUse }) {
            free.inUse = true
            return free
        }
        genSeed += 1
        let node = SCNNode()
        let road = SCNNode(geometry: groundPlane(width: 6, length: CGFloat(segmentLength), material: roadMaterials[world]!))
        road.position = SCNVector3(0, 0.01, -segmentLength / 2)
        node.addChildNode(road)
        node.addChildNode(scenery.dressing(for: world, length: segmentLength, seed: genSeed))
        applyLook(to: node)
        let seg = Segment(node: node, world: world)
        seg.inUse = true
        segmentPool[world, default: []].append(seg)
        return seg
    }

    /// Builds each world's slices up front so no slice is built mid-run.
    private func prewarmSegments() {
        let perWorld = Int((trackDepth + trackBehind) / segmentLength) + 2
        for world in WorldKind.allCases {
            let built = (0..<perWorld).map { _ in takeSegment(world) }
            built.forEach { $0.inUse = false }
        }
    }

    private func moveTrack(dz: Float) {
        for seg in segments {
            seg.node.position.z += dz
        }
        while let first = segments.first, first.near - segmentLength > trackBehind {
            first.node.removeFromParentNode()
            first.inUse = false
            segments.removeFirst()
        }
        while let last = segments.last, last.near - segmentLength > -trackDepth {
            addSegment(near: last.near - segmentLength)
        }
    }

    // MARK: - Loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = Float(lastTime == 0 ? 1.0 / 60.0 : min(1.0 / 30.0, time - lastTime))
        lastTime = time
        handleInput()

        switch state {
        case .running:
            step(dt: dt)
        case .ready:
            // The title screen drives slowly so the world is alive behind the panel.
            moveTrack(dz: runSpeed() * 0.45 * dt)
            updateWorldBlend()
            updateCamera(dt: dt)
        case .dead:
            updateCamera(dt: dt)
        }
    }

    private func step(dt: Float) {
        timeAlive += dt
        let speed = runSpeed()
        let dz = speed * dt
        meters += dz

        pilot()
        moveTrack(dz: dz)
        updateWorldBlend()

        untilWave -= dz
        if untilWave <= 0 {
            untilWave = spawnWave()
        }

        updateJump(dt: dt)
        updateSteer(dt: dt)
        updateRide()
        moveItems(dz: dz, dt: dt)
        resolveContacts(dz: dz)
        guard state == .running else { return }
        updateCamera(dt: dt)

        dust.birthRate = height < 0.05 || (onPlatform && height - roofY < 0.05) ? 22 : 0

        lineClock -= dt
        if lineClock <= 0 {
            lineClock = 0.12
            hud.speedLine(strength: CGFloat(min(1, (speed - 12) / 14)))
        }
        hud.setMeters(Int(meters))
        hud.setFood(food)
    }

    private func updateCamera(dt: Float) {
        // The camera trails the cat a little: it follows her lane at 60%, and rises
        // when she rides a tree, but it lags so lane changes and landings feel weighty.
        cameraLift += (floorY - cameraLift) * min(1, 4 * dt)
        let goalX = visualX * 0.6
        let x = cameraNode.position.x + (goalX - cameraNode.position.x) * min(1, 9 * dt)
        let y = cameraBase.y + cameraLift * 0.75 + max(0, height - floorY) * 0.12
        cameraNode.position = SCNVector3(x, y, cameraBase.z)
        cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, -tilt * 0.08)
        // A slightly wider view as the run speeds up.
        let boost = CGFloat(max(0, runSpeed() - 17) * 0.45)
        cameraNode.camera?.fieldOfView = baseFOV + (state == .running ? boost : 0)
    }

    private func updateJump(dt: Float) {
        if jumping {
            hangLeft -= dt
            if hangLeft <= 0 {
                slamDown()
            }
        }

        let target = floorY + (jumping ? jumpPeak : 0)
        let rate: Float = jumping ? 9 : 15
        height += (target - height) * min(1, rate * dt)
        if !onPlatform && height < 0.01 { height = 0 }

        let airborne = isHighEnough && !onPlatform || (onPlatform && height - roofY > clearHeight)
        if wasAirborne && !airborne && !jumping {
            landSquash = 1
            puff(at: SCNVector3(visualX, floorY + 0.1, 0.2), count: 10, color: UIColor(white: 1, alpha: 0.9))
            haptic(.medium)
        }
        wasAirborne = airborne

        // Squash on landing, stretch in the air. Small, so she still reads as sitting.
        landSquash = max(0, landSquash - dt * 5)
        let air = min(1, (height - floorY) / jumpPeak)
        let squash = sin(landSquash * .pi) * 0.12
        catNode.scale = SCNVector3(1 + squash - air * 0.03, 1 - squash + air * 0.05, 1)

        // Road bumps while rolling.
        let bump = height - floorY < 0.02 ? sin(timeAlive * 38) * 0.018 : 0
        catNode.position.y = height + bump

        // The shadow stays on whatever is under her, and shrinks as she rises.
        let lift = max(0, height - floorY)
        catShadow.position.y = floorY + 0.03
        let s = max(0.45, 1 - lift * 0.22)
        catShadow.scale = SCNVector3(s, s, s)
        catShadow.opacity = CGFloat(max(0.35, 1 - lift * 0.25))
    }

    private func updateSteer(dt: Float) {
        let goal = laneX(lane)
        visualX += (goal - visualX) * min(1, 18 * dt)
        playerRoot.position.x = visualX
        tilt *= max(0, 1 - 9 * dt)
        if abs(tilt) < 0.005 { tilt = 0 }
        catNode.eulerAngles.z = tilt
    }

    private func updateRide() {
        guard onPlatform else { return }
        let stillOn = items.contains { $0.kind == .tree && $0.lane == lane && overlapsCat($0) }
        if !stillOn {
            onPlatform = false
        }
    }

    private func overlapsCat(_ item: TrackItem) -> Bool {
        item.z >= -0.3 && item.back <= 0.3
    }

    private func moveItems(dz: Float, dt: Float) {
        for item in items {
            item.z += dz
            item.node.position.z = item.z
            // Transparent pictures draw far to near so they overlap correctly.
            if item.kind != .tree {
                item.node.renderingOrder = 1000 + Int(item.z * 4)
                item.node.childNodes.first?.renderingOrder = 1000 + Int(item.z * 4)
            }
            if item.kind == .coyote, let pic = item.picture, !coyoteFrames.isEmpty {
                item.frameClock += dt
                if item.frameClock > 0.11 {
                    item.frameClock = 0
                    item.frame = (item.frame + 1) % coyoteFrames.count
                    pic.diffuse.contents = coyoteFrames[item.frame]
                }
            }
        }
        items.removeAll { item in
            if item.back > trackBehind {
                recycle(item)
                return true
            }
            return false
        }
    }

    // MARK: - Spawning

    /// Drops one wave of coyotes, food, and trees far ahead.
    /// Returns how many meters until the next wave.
    private func spawnWave() -> Float {
        let patterns: [[Spawn]] = [
            [Spawn(kind: .coyote, lane: 0, ahead: 0)],
            [Spawn(kind: .coyote, lane: 1, ahead: 0)],
            [Spawn(kind: .coyote, lane: 2, ahead: 0)],
            [Spawn(kind: .coyote, lane: 0, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 0)],
            [Spawn(kind: .coyote, lane: 0, ahead: 0), Spawn(kind: .coyote, lane: 2, ahead: 0)],
            [Spawn(kind: .coyote, lane: 0, ahead: 0), Spawn(kind: .coyote, lane: 1, ahead: 0)],
            // Food right after a coyote: the reward for jumping it.
            [Spawn(kind: .coyote, lane: 1, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 6),
             Spawn(kind: .food, lane: 1, ahead: 9), Spawn(kind: .food, lane: 1, ahead: 12)],
            [Spawn(kind: .tree, lane: 1, ahead: 0)],
            [Spawn(kind: .tree, lane: 1, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 4, onRoof: true),
             Spawn(kind: .food, lane: 1, ahead: 7, onRoof: true), Spawn(kind: .food, lane: 1, ahead: 10, onRoof: true)],
            [Spawn(kind: .tree, lane: 0, ahead: 0), Spawn(kind: .coyote, lane: 2, ahead: 0)],
            [Spawn(kind: .tree, lane: 2, ahead: 0), Spawn(kind: .coyote, lane: 0, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 0)],
            [Spawn(kind: .tree, lane: 0, ahead: 0), Spawn(kind: .tree, lane: 1, ahead: 0), Spawn(kind: .food, lane: 2, ahead: 0)],
            [Spawn(kind: .food, lane: 0, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 4), Spawn(kind: .food, lane: 2, ahead: 8)],
            [Spawn(kind: .food, lane: 1, ahead: 0), Spawn(kind: .food, lane: 1, ahead: 3), Spawn(kind: .food, lane: 1, ahead: 6),
             Spawn(kind: .food, lane: 1, ahead: 9), Spawn(kind: .food, lane: 1, ahead: 12)],
            [Spawn(kind: .coyote, lane: 0, ahead: 0), Spawn(kind: .tree, lane: 2, ahead: 0)],
            [Spawn(kind: .coyote, lane: 1, ahead: 0), Spawn(kind: .tree, lane: 0, ahead: 0), Spawn(kind: .coyote, lane: 2, ahead: 0)]
        ]
        let pattern = patterns.randomElement() ?? patterns[0]
        let rot = Int.random(in: 0...2)
        var reach: Float = 0
        var treeLength: [Int: Float] = [:]
        for spawn in pattern where spawn.kind == .tree {
            let lane = (spawn.lane + rot) % 3
            let length = [11, 14, 17].randomElement().map(Float.init) ?? 14
            treeLength[lane] = length
            addItem(.tree, lane: lane, z: -spawnAhead - spawn.ahead, length: length)
            reach = max(reach, spawn.ahead + length)
        }
        for spawn in pattern where spawn.kind != .tree {
            let lane = (spawn.lane + rot) % 3
            addItem(spawn.kind, lane: lane, z: -spawnAhead - spawn.ahead, onRoof: spawn.onRoof && treeLength[lane] != nil)
            reach = max(reach, spawn.ahead)
        }
        // Leave room to land after the longest thing in this wave.
        let gap = max(20, 30 - timeAlive * 0.12)
        return reach + gap
    }

    private func addItem(_ kind: Kind, lane: Int, z: Float, length: Float = 0, onRoof: Bool = false) {
        let node: SCNNode
        var picture: SCNMaterial?
        switch kind {
        case .coyote:
            node = takeNode("coyote") { self.makeCoyote() }
            picture = node.childNode(withName: "picture", recursively: true)?.geometry?.firstMaterial
            picture?.diffuse.contents = coyoteFrames.first
        case .food:
            node = takeNode("food") { self.makeFood() }
        case .tree:
            node = takeNode("tree\(Int(length))") { self.makeCatTree(length: length) }
        }
        let item = TrackItem(kind: kind, lane: lane, node: node, z: z)
        item.length = length
        item.picture = picture
        item.frame = Int.random(in: 0..<4)
        node.position = SCNVector3(laneX(lane), onRoof ? roofY + 0.05 : 0, z)
        scene.rootNode.addChildNode(node)
        items.append(item)
    }

    private func takeNode(_ key: String, make: () -> SCNNode) -> SCNNode {
        if var free = itemPool[key], let node = free.popLast() {
            itemPool[key] = free
            return node
        }
        let node = make()
        node.name = key
        return node
    }

    private func recycle(_ item: TrackItem) {
        item.node.removeFromParentNode()
        if let key = item.node.name {
            itemPool[key, default: []].append(item.node)
        }
    }

    private func makeCoyote() -> SCNNode {
        let node = billboard(image: coyoteFrames.first, width: 1.85)
        // Its own material, so each coyote can snarl on its own beat.
        if let pic = node.childNode(withName: "picture", recursively: true), let m = pic.geometry?.firstMaterial?.copy() as? SCNMaterial {
            pic.geometry = pic.geometry?.copy() as? SCNGeometry
            pic.geometry?.materials = [m]
            // A mean little lope toward the cat.
            pic.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.12, z: 0, duration: 0.14),
                .moveBy(x: 0, y: -0.12, z: 0, duration: 0.14)
            ])))
        }
        // The copied material needs the fog color kept up to date too.
        applyLook(to: node)
        node.addChildNode(shadowNode(width: 1.8, length: 1.3))
        return node
    }

    private func makeFood() -> SCNNode {
        let node = billboard(image: UIImage(named: "wetFood"), width: 1.0)
        if let pic = node.childNode(withName: "picture", recursively: true) {
            pic.position.y += 0.3
            pic.runAction(.repeatForever(.sequence([
                .group([.moveBy(x: 0, y: 0.14, z: 0, duration: 0.45), .rotateBy(x: 0, y: 0, z: 0.08, duration: 0.45)]),
                .group([.moveBy(x: 0, y: -0.14, z: 0, duration: 0.45), .rotateBy(x: 0, y: 0, z: -0.08, duration: 0.45)])
            ])))
        }
        node.addChildNode(shadowNode(width: 0.7, length: 0.55))
        return node
    }

    private func shadowNode(width: CGFloat, length: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: groundPlane(width: width, length: length, material: shadowMaterial))
        node.position = SCNVector3(0, 0.03, 0)
        node.renderingOrder = 5
        node.castsShadow = false
        return node
    }

    // MARK: - Cat tree

    private lazy var carpetTop: SCNMaterial = carpetMaterial("carpetTop", fallback: UIColor(red: 0.90, green: 0.82, blue: 0.68, alpha: 1))
    private lazy var carpetSide: SCNMaterial = carpetMaterial("carpetSide", fallback: UIColor(red: 0.80, green: 0.70, blue: 0.56, alpha: 1))
    private lazy var sisal: SCNMaterial = carpetMaterial("sisalRope", fallback: UIColor(red: 0.78, green: 0.62, blue: 0.38, alpha: 1))

    private func carpetMaterial(_ name: String, fallback: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIImage(named: name) ?? fallback
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        Self.smoothSampling(m.diffuse)
        m.lightingModel = .lambert
        return m
    }

    /// A long carpeted cat tree that fills one lane like a Subway Surfers train.
    /// Front edge at z = 0, stretching back to z = -length. The roof is the ride.
    private func makeCatTree(length: Float) -> SCNNode {
        let root = SCNNode()
        let width: CGFloat = 1.75
        let L = CGFloat(length)

        let topTex = carpetTop.copy() as! SCNMaterial
        topTex.diffuse.contentsTransform = SCNMatrix4MakeScale(1, Float(L / width), 1)
        let sideLong = carpetSide.copy() as! SCNMaterial
        sideLong.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(L / width), 0.2, 1)

        // Roof: thick, fluffy, and a lighter color than the road, so it reads as a platform.
        let roof = SCNBox(width: width, height: 0.26, length: L, chamferRadius: 0.1)
        roof.materials = [carpetSide, sideLong, carpetSide, sideLong, topTex, carpetSide]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, roofY - 0.13, -length / 2)
        root.addChildNode(roofNode)

        // Base plate on the ground.
        let base = SCNBox(width: width, height: 0.16, length: L, chamferRadius: 0.05)
        base.materials = [carpetSide, sideLong, carpetSide, sideLong, carpetSide, carpetSide]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.08, -length / 2)
        root.addChildNode(baseNode)

        // Sisal posts down both sides.
        let postHeight = CGFloat(roofY - 0.3)
        let post = SCNCylinder(radius: 0.13, height: postHeight)
        let rope = sisal.copy() as! SCNMaterial
        rope.diffuse.contentsTransform = SCNMatrix4MakeScale(2, Float(postHeight) * 1.5, 1)
        post.materials = [rope, carpetSide, carpetSide]
        let bays = max(2, Int((length / 3.2).rounded()))
        for i in 0...bays {
            let z = -0.35 - Float(i) * (length - 0.7) / Float(bays)
            for x: Float in [-0.72, 0.72] {
                let p = SCNNode(geometry: post)
                p.position = SCNVector3(x, 0.16 + Float(postHeight) / 2, z)
                root.addChildNode(p)
            }
        }

        // Cubbies in every other bay, each with a dark round doorway facing the cat.
        let cubby = SCNBox(width: 1.25, height: 0.85, length: 1.3, chamferRadius: 0.12)
        cubby.materials = [carpetSide]
        let hole = SCNCylinder(radius: 0.28, height: 0.02)
        let holeMat = SCNMaterial()
        holeMat.diffuse.contents = UIColor(red: 0.20, green: 0.13, blue: 0.10, alpha: 1)
        holeMat.lightingModel = .constant
        hole.materials = [holeMat]
        for i in stride(from: 0, to: bays, by: 2) {
            let z = -0.35 - (Float(i) + 0.5) * (length - 0.7) / Float(bays)
            let c = SCNNode(geometry: cubby)
            c.position = SCNVector3(0, 0.16 + 0.425, z)
            root.addChildNode(c)
            let h = SCNNode(geometry: hole)
            h.eulerAngles.x = .pi / 2
            h.position = SCNVector3(0, -0.05, 0.66)
            c.addChildNode(h)
        }

        // A pom-pom toy swinging off the front corner, like the 2D art.
        let string = SCNCylinder(radius: 0.012, height: 0.55)
        let stringMat = SCNMaterial()
        stringMat.diffuse.contents = UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1)
        string.materials = [stringMat]
        let pomMat = SCNMaterial()
        pomMat.diffuse.contents = UIColor(red: 0.98, green: 0.30, blue: 0.55, alpha: 1)
        pomMat.lightingModel = .lambert
        let pom = SCNSphere(radius: 0.14)
        pom.materials = [pomMat]
        let hanger = SCNNode()
        hanger.position = SCNVector3(0.7, roofY - 0.26, -0.3)
        let stringNode = SCNNode(geometry: string)
        stringNode.position = SCNVector3(0, -0.275, 0)
        hanger.addChildNode(stringNode)
        let pomNode = SCNNode(geometry: pom)
        pomNode.position = SCNVector3(0, -0.6, 0)
        hanger.addChildNode(pomNode)
        hanger.runAction(.repeatForever(.sequence([
            .rotateTo(x: 0, y: 0, z: 0.35, duration: 0.6, usesShortestUnitArc: true),
            .rotateTo(x: 0, y: 0, z: -0.35, duration: 0.6, usesShortestUnitArc: true)
        ])))
        root.addChildNode(hanger)

        // A soft shadow the length of the tree.
        let shade = SCNNode(geometry: groundPlane(width: width + 0.7, length: L + 0.8, material: shadowMaterial))
        shade.position = SCNVector3(0, 0.025, -length / 2)
        shade.castsShadow = false
        root.addChildNode(shade)

        applyLook(to: root)
        return root
    }

    // MARK: - Contacts

    private func resolveContacts(dz: Float) {
        for item in items where item.lane == lane {
            let prevZ = item.z - dz
            if item.kind == .tree {
                handleTree(item, prevZ: prevZ)
                if state != .running { return }
                continue
            }
            let crossed = prevZ < 0 && item.z >= 0
            guard crossed else { continue }
            switch item.kind {
            case .food:
                collect(item)
            case .coyote:
                if isHighEnough { continue }
                if !e2eGod {
                    crash()
                    return
                }
            case .tree:
                break
            }
        }
    }

    private func handleTree(_ item: TrackItem, prevZ: Float) {
        let entered = prevZ < 0 && item.z >= 0
        guard entered || overlapsCat(item) else { return }
        if onPlatform { return }
        if isHighEnough {
            mountTree()
            return
        }
        if entered, !e2eGod {
            crash()
        }
    }

    private func mountTree() {
        guard !onPlatform else { return }
        onPlatform = true
        jumping = false
        hangLeft = 0
        landSquash = 1
        haptic(.medium)
        puff(at: SCNVector3(visualX, roofY + 0.1, 0.2), count: 10, color: UIColor(red: 0.92, green: 0.82, blue: 0.64, alpha: 1))
    }

    private func collect(_ item: TrackItem) {
        food += 1
        meters += 5
        let spot = SCNVector3(laneX(item.lane), item.node.position.y + 0.6, 0.2)
        recycle(item)
        items.removeAll { $0 === item }
        haptic(.light)
        puff(at: spot, count: 12, color: UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1))
    }

    private func crash() {
        state = .dead
        jumping = false
        onPlatform = false
        dust.birthRate = 0
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        hud.flashWhite()
        hud.clearLines()
        shakeCamera()
        // A silly tip-over, not a punishment.
        catNode.runAction(.group([
            .rotateBy(x: 0, y: 0, z: tilt >= 0 ? 0.9 : -0.9, duration: 0.25),
            .sequence([.moveBy(x: 0, y: 0.5, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.5, z: 0, duration: 0.18)])
        ]), forKey: "tip")
        if meters > bestMeters {
            bestMeters = meters
            UserDefaults.standard.set(Double(bestMeters), forKey: Self.bestKey)
        }
        hud.showDead(meters: Int(meters), food: food, best: Int(bestMeters))
    }

    private func shakeCamera() {
        cameraNode.removeAction(forKey: "shake")
        let shake = SCNAction.sequence([
            .moveBy(x: 0.18, y: 0.08, z: 0, duration: 0.03),
            .moveBy(x: -0.30, y: -0.12, z: 0, duration: 0.04),
            .moveBy(x: 0.22, y: 0.06, z: 0, duration: 0.04),
            .moveBy(x: -0.10, y: -0.02, z: 0, duration: 0.04)
        ])
        cameraNode.runAction(shake, forKey: "shake")
    }

    private func puff(at point: SCNVector3, count: Int, color: UIColor) {
        let ps = SCNParticleSystem()
        ps.particleImage = puffImage
        ps.birthRate = CGFloat(count) * 20
        ps.emissionDuration = 0.05
        ps.loops = false
        ps.particleLifeSpan = 0.4
        ps.particleSize = 0.2
        ps.particleSizeVariation = 0.08
        ps.particleColor = color
        ps.particleVelocity = 2.6
        ps.particleVelocityVariation = 1
        ps.emittingDirection = SCNVector3(0, 1, 0.3)
        ps.spreadingAngle = 75
        ps.acceleration = SCNVector3(0, -3, 3)
        ps.blendMode = .alpha
        ps.propertyControllers = [.opacity: Self.fadeOutController()]
        let holder = SCNNode()
        holder.position = point
        holder.addParticleSystem(ps)
        scene.rootNode.addChildNode(holder)
        holder.runAction(.sequence([.wait(duration: 1), .removeFromParentNode()]))
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    // MARK: - Input

    // Touches arrive on the main thread. We turn them into intents and let the
    // render thread act on them at the start of the next frame.

    func touchBegan(at point: CGPoint) {
        swipeStart = point
        swipeConsumed = false
        enqueue(.tap)
    }

    func touchMoved(to point: CGPoint, minimum: CGFloat) {
        guard !swipeConsumed, let start = swipeStart else { return }
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard hypot(dx, dy) > minimum else { return }
        swipeConsumed = true
        if abs(dx) > abs(dy) {
            enqueue(dx > 0 ? .right : .left)
        } else {
            // UIKit's y grows downward, so a swipe up is a negative dy.
            enqueue(dy < 0 ? .up : .down)
        }
    }

    func touchEnded() {
        swipeStart = nil
    }

    private func enqueue(_ intent: Intent) {
        inputLock.lock()
        pending.append(intent)
        inputLock.unlock()
    }

    private func handleInput() {
        inputLock.lock()
        let intents = pending
        pending.removeAll()
        inputLock.unlock()

        for intent in intents {
            switch (state, intent) {
            case (.ready, .tap):
                startRun()
            case (.dead, .tap):
                resetRun()
                startRun()
            case (.running, .left):
                moveLane(-1)
            case (.running, .right):
                moveLane(1)
            case (.running, .up):
                jump()
            case (.running, .down):
                slamDown()
            default:
                break
            }
        }
    }

    private func moveLane(_ delta: Int) {
        let next = max(0, min(2, lane + delta))
        guard next != lane else { return }
        let treeThere = items.contains { $0.kind == .tree && $0.lane == next && overlapsCat($0) }
        if treeThere && !isHighEnough {
            // Bumped the side of a cat tree from the ground: bounce back, stay in lane.
            tilt = delta > 0 ? 0.12 : -0.12
            visualX += Float(delta) * 0.35
            haptic(.rigid)
            return
        }
        if onPlatform && !treeThere {
            // Stepped off the tree into an empty lane: fall.
            onPlatform = false
        }
        if !onPlatform && treeThere && isHighEnough {
            mountTree()
        }
        lane = next
        tilt = delta > 0 ? -0.2 : 0.2
        DispatchQueue.main.async {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func jump() {
        guard !jumping else { return }
        jumping = true
        hangLeft = onPlatform ? 0.95 : 1.15
        haptic(.light)
    }

    private func slamDown() {
        guard jumping || height - floorY > 0.05 else { return }
        jumping = false
        hangLeft = 0
    }

    /// Test-only autopilot (CATCART_PILOT=1): jumps coyotes and hops onto trees,
    /// so screenshot runs show the real moves.
    private func pilot() {
        guard e2ePilot, state == .running else { return }
        for item in items where item.lane == lane && item.z < 0 && item.z > -9 {
            if item.kind == .coyote && !isHighEnough && !jumping {
                jump()
            } else if item.kind == .tree && !onPlatform && !jumping && item.z > -6 {
                jump()
            }
        }
    }

    // MARK: - States

    private func startRun() {
        hud.hidePanel()
        state = .running
        untilWave = 30
    }

    private func resetRun() {
        items.forEach { recycle($0) }
        items.removeAll()
        hud.clearLines()
        catNode.removeAction(forKey: "tip")
        lane = 1
        jumping = false
        height = 0
        hangLeft = 0
        wasAirborne = false
        onPlatform = false
        tilt = 0
        cameraLift = 0
        landSquash = 0
        timeAlive = 0
        meters = 0
        food = 0
        placePlayer()
        resetTrack()
        hud.setMeters(0)
        hud.setFood(0)
    }
}

// MARK: - Per-world names

extension WorldKind {
    var roadName: String {
        switch self {
        case .city: return "roadCity"
        case .jungle: return "roadJungle"
        case .house: return "roadHouse"
        case .farm: return "roadFarm"
        }
    }

    /// Plain color if the road texture is missing, so the game still runs.
    var roadFallback: UIColor {
        switch self {
        case .city: return UIColor(red: 0.45, green: 0.44, blue: 0.46, alpha: 1)
        case .jungle: return UIColor(red: 0.60, green: 0.38, blue: 0.26, alpha: 1)
        case .house: return UIColor(red: 0.78, green: 0.56, blue: 0.34, alpha: 1)
        case .farm: return UIColor(red: 0.80, green: 0.68, blue: 0.48, alpha: 1)
        }
    }
}

private extension UIColor {
    convenience init(_ v: SIMD3<Float>) {
        self.init(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }
}

private extension GameScene {
    static func drawBlob() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let colors = [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                             endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    static func drawPuff() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                             endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }
}
