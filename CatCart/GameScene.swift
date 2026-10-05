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
// - The cat, coyotes, food cans, and cat trees are real 3D models. The trees
//   have a flat roof that the cart can ride.
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
        /// Something low across the lane (scaffold, log, table, clothesline).
        /// She has to duck into the box to pass under it.
        case low
    }

    private enum Intent {
        case tap, left, right, up, down
        /// A finger lifted without swiping. On the death panel, this is what restarts.
        case lift
        /// Test-only: a stumble from CATCART_SWIPES, to see the bottle without aiming for a bump.
        case stumble
    }

    /// One thing on the track. `z` is its front edge (the end nearest the cat).
    /// A cat tree also has a length that stretches away from the cat, toward -z.
    ///
    /// A cat tree with a ramp is still one item: `z` is the foot of the ramp,
    /// `length` covers the ramp and the tree, and `rampLength` says how much of
    /// that is slope. The tree's mesh (`node`) sits `rampLength` further back, and
    /// the ramp mesh (`ramp`) rides on it as a child. `top(at:)` is the height of
    /// the surface she rolls on anywhere along it.
    private final class TrackItem {
        let kind: Kind
        let lane: Int
        let node: SCNNode
        var z: Float
        var length: Float = 0
        /// A cat tree's roof height: 2.0 m short, 3.5 m tall.
        var roof: Float = 0
        /// The carpeted slope in front of the tree, 0 for no ramp.
        var rampLength: Float = 0
        /// The ramp's mesh, borrowed from its pool while the tree is on the road.
        var ramp: SCNNode?
        var picture: SCNMaterial?
        var frame = 0
        var frameClock: Float = 0
        /// Food hanging in the air, only reached by jumping.
        var high = false
        /// Already clipped her once (a stumble), so it can't clip her again.
        var hit = false
        var back: Float { z - length }
        /// Where the mesh sits: a ramped tree's mesh starts where the slope ends.
        var nodeZ: Float { z - rampLength }

        /// Height of a cat tree's top `depth` meters in from its front: rising
        /// along the ramp, then flat on the roof.
        func top(at depth: Float) -> Float {
            guard rampLength > 0, depth < rampLength else { return roof }
            return roof * max(0, depth) / rampLength
        }

        /// Height of the top right where the cat is (z = 0).
        var topAtCat: Float { top(at: z) }

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
        /// Extra meters further ahead than the wave's front, written for 17 m/s.
        let ahead: Float
        /// Food that sits on a cat tree's roof.
        var onRoof = false
        /// Food hanging at jump height, over a coyote.
        var high = false
        /// A cat tree's length at 17 m/s. Nil picks 11, 14, or 17.
        var length: Float?
        /// A tall cat tree (3.5 m roof) instead of a short one (2.0 m).
        var tall = false
        /// A carpeted ramp in front of the tree. `ahead` is then the ramp's foot,
        /// and the tree's front is `rampWritten` meters further on.
        var ramp = false
    }

    /// One obstacle mix. Easy mixes (tier 0) show up from the start, medium (1)
    /// from 15 s, hard (2) from 40 s.
    private struct Wave {
        let tier: Int
        let spawns: [Spawn]
        /// How often it's picked, next to the other mixes in its tier.
        var weight: Float = 1
        /// Can it slide to any lane? Mixes where neighbors matter (hopping from
        /// tree to tree) can only be mirrored left to right.
        var rotates = true
    }

    /// Best score, saved on the phone. Older builds saved a best distance under
    /// "bestMeters" (2D) and "bestMeters3D"; the score doesn't carry those over.
    private static let bestKey = "bestScore"
    /// Score: a point per meter, plus this much for each can of wet food.
    private static let foodPoints = 25
    /// Set once she has ducked under a low thing, so the duck hint stops showing.
    private static let duckedKey = "duckedUnderOnce"

    // MARK: - Tuning (meters and seconds)

    private let laneSpacing: Float = 1.9
    private let segmentLength: Float = 24
    /// Coyotes, food, and trees appear this far ahead, inside the fog.
    private let spawnAhead: Float = 118
    /// When a run starts, the road is filled with mixes from here out to spawnAhead,
    /// so the first coyote arrives about two seconds after the tap, not eight.
    private let firstWaveAhead: Float = 40
    /// The road is built out to here so the horizon never shows a gap.
    private let trackDepth: Float = 190
    /// Anything this far behind the cat is off camera and gets recycled.
    private let trackBehind: Float = 10
    /// Road is kept this far behind her so the home screen, which looks back
    /// at her face, sees a street running off into the fog.
    private let roadBehind: Float = 70
    /// Roof heights of the two cat trees. A jump from the ground (peak 2.6 m) lands
    /// on a short tree. A tall tree is out of its reach, so its front is a wall:
    /// you get up there by a ramp, or by jumping from a short roof (peak 4.6 m).
    private let shortRoof: Float = 2.0
    private let tallRoof: Float = 3.5
    /// A ramp is this long at 17 m/s and stretches with speed like a tree, so the
    /// climb always takes about half a second.
    private static let rampWritten: Float = 8
    /// How high a step she can roll up onto with her wheels on something: the low
    /// end of a ramp from the side, about where the carpet still reads as a curb.
    /// Higher than this from the side is a bump and a stumble.
    private let stepUp: Float = 0.5
    /// In a jump, how far below a tall roof (or the high part of a ramp) she can
    /// be and still get on: her arc carries her up, or she hops up if she catches
    /// it low. Only a jump from a short roof gets within this of a tall one. For
    /// short-tree heights the old, more generous rule holds (see `canReach`).
    private let highReach: Float = 0.5
    private let jumpPeak: Float = 2.6
    /// A jump is a real arc: up at jumpSpeed, pulled down by gravity. It always peaks
    /// at 2.6 m (Rex, 2026-10-05, was 1.9: "I just want the animation higher").
    /// Takeoff to landing is 0.8 s at the start and quickens to about 0.62 s at full
    /// ramp (75 s), so a jump doesn't sail over half the road when it's fast. It
    /// stays there while speed keeps creeping up after that. Raising the
    /// peak with the airtime unchanged only makes takeoff faster and gravity
    /// stronger, so every timing stays the same.
    private var jumpAirtime: Float { 0.8 - 0.18 * ramp }
    private var gravity: Float { 8 * jumpPeak / (jumpAirtime * jumpAirtime) }
    private var jumpSpeed: Float { 4 * jumpPeak / jumpAirtime }
    /// A swipe up this soon before landing is remembered and fires on touchdown.
    private let jumpBufferTime: Float = 0.18
    /// Above this height a coyote passes under you and a short tree's front is a
    /// landing, not a crash. 1.1 m at the start, 1.37 m at full ramp (was 0.8 and
    /// 1.0 with the 1.9 m jump; scaled by 2.6 / 1.9 so it plays the same): the part
    /// of a jump that clears a coyote shrinks from about three quarters of the
    /// airtime to about two thirds.
    private var clearHeight: Float { 1.1 + 0.27 * ramp }
    /// Food hanging in the air sits here, where a jump's arc carries her, and she
    /// reaches it above `airFoodReach` (2.0 and 1.23 m, scaled with the jump).
    private let airFoodY: Float = 2.0
    private let airFoodReach: Float = 1.23
    /// A coyote's body, nose to haunches, for contact. The model is 1.9 m with its
    /// tail; the tail doesn't count.
    private let coyoteLength: Float = 1.5
    /// The stretch of road her cart covers, either side of z = 0. A coyote or low
    /// thing touching this stretch in her lane is touching her.
    private let catReach: Float = 0.4
    /// A swipe down on the ground sinks her into the box this long. Another swipe
    /// down while ducked starts the count again.
    private let duckTime: Float = 0.45
    /// The underside of every low thing. Sitting up, her head reaches about 1.68 m;
    /// ducked, only her eyes and ears show over the rim and she's about 1.25 m.
    private let lowClearance: Float = 1.38
    private let worldSeconds: Float = 10
    /// After a stumble the spray bottle chases her this long. A second stumble
    /// before it gives up and she's caught.
    private let chaseTime: Float = 4
    /// Where the bottle hops while it chases: just behind the cart, peeking up from
    /// the bottom of the screen. Further back than `bottleGone` it's hidden.
    private let bottleChaseZ: Float = 1.7
    private let bottleGone: Float = 7
    /// After a crash, taps are ignored this long, so mashing the screen or a swipe
    /// that was already under way can't start a new run by accident. The "Dash
    /// again" button pops in when it ends, so you can see when tapping works again.
    private let deathPause: Float = 1.0

    private let cameraBase = SIMD3<Float>(0, 2.9, 4.4)
    private let cameraPitch: Float = -0.055
    private let baseFOV: CGFloat = 56
    /// Home screen camera: in front of her and a little to the side, looking back at her face.
    private let homeEye = SIMD3<Float>(0.9, 1.6, -2.75)
    private let homeTarget = SIMD3<Float>(0, 0.9, 0.25)

    /// Seconds into a run when the difficulty ramp is full.
    private let rampSeconds: Float = 75

    /// How far into the run's difficulty we are, 0 at the start to 1 after 75 s.
    /// It climbs fast early and settles, like Subway Surfers: 0.20 at 8 s, 0.46 at
    /// 20 s, 0.64 at 30 s, 0.84 at 45 s. Speed, gaps, the jump, and how much the
    /// obstacle mixes favor hard ones all read this one number.
    private var ramp: Float {
        let x = min(1, timeAlive / rampSeconds)
        return 1 - (1 - x) * (1 - x)
    }

    /// Running speed in meters per second. 17 at the start, 34 at full ramp
    /// (about 20 at 8 s, 28 at 30 s, 31 at 45 s). Past 75 s it keeps creeping up
    /// 1 m/s every 30 s, to 38 at about 3:15, so a long run still gets harder.
    /// Only speed creeps: the jump, clear height, and gaps read `ramp` and stay at
    /// their full-ramp values.
    private func runSpeed() -> Float {
        let overtime = min(4, max(0, timeAlive - rampSeconds) / 30)
        return 17 + 17 * ramp + overtime
    }

    /// Distances inside an obstacle mix are written for 17 m/s. They stretch with
    /// speed, but less than speed does (the square root), so the faster she goes,
    /// the less time there is between things: 19 m between two coyotes is 1.1 s at
    /// the start, about 0.8 s at 34 m/s, and 0.75 s at 38. That squeeze is most of
    /// what makes a long run hard.
    private var spacingScale: Float { (runSpeed() / 17).squareRoot() }
    /// Cat trees stretch fully with speed, so a ride lasts about the same time.
    private var treeScale: Float { runSpeed() / 17 }

    // MARK: - Shaders

    // Curved world. Every vertex drops by k * d^2, where d is how far ahead of the cat
    // it is, so the road rolls over a hill. A slow sideways sway makes it feel like the
    // street bends left and right. Runs on the GPU for every 3D thing we draw.
    private static let playerLightBit = 2

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
    private var cart: KittenCart!
    private let fillNode = SCNNode()
    private var catShadow: SCNNode!
    private var dust: SCNParticleSystem!
    /// Where the wheel dust comes from. It rides up with her onto a roof.
    private let dustNode = SCNNode()
    /// The green spray bottle that chases her after a stumble.
    private let bottle = SCNNode()

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

    /// The saved Blender coyote, exported with scripts/build_art.sh.
    /// Its gallop is baked into the file and plays on every clone by itself.
    private lazy var coyoteModel: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "coyote_run", withExtension: "scn"),
              let file = try? SCNScene(url: url, options: nil) else { return nil }
        return file.rootNode.childNode(withName: "coyote", recursively: true)
    }()

    /// Turquoise wet-food can. Its label is embedded in the SceneKit archive.
    private lazy var foodModel: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "wet_food", withExtension: "scn"),
              let file = try? SCNScene(url: url, options: nil) else { return nil }
        return file.rootNode.childNode(withName: "wet_food", recursively: true)
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

    /// One sky picture per world, loaded up front so driving into a new world
    /// swaps a ready material instead of decoding a picture mid-run.
    private lazy var skyMaterials: [WorldKind: SCNMaterial] = {
        var out: [WorldKind: SCNMaterial] = [:]
        for world in WorldKind.allCases {
            let m = SCNMaterial()
            m.diffuse.contents = UIImage(named: look(world).sky) ?? UIColor(look(world).fog)
            m.lightingModel = .constant
            m.readsFromDepthBuffer = false
            m.writesToDepthBuffer = false
            out[world] = m
        }
        return out
    }()

    /// A landing or food puff emitter, reused in turn instead of built per puff.
    private final class Puff {
        let node: SCNNode
        let system: SCNParticleSystem
        /// Seconds of emission left. 0 means silent.
        var left: Float = 0

        init(node: SCNNode, system: SCNParticleSystem) {
            self.node = node
            self.system = system
        }
    }

    private var puffs: [Puff] = []
    private var nextPuff = 0

    // MARK: - Game state

    private var state: State = .ready
    private var lane = 1
    private var visualX: Float = 0
    private var tilt: Float = 0
    private var jumping = false
    private var height: Float = 0
    private var vy: Float = 0
    private var wasAirborne = false
    /// The cat tree she's riding (its roof, or its ramp), or nil on the road.
    private var platform: TrackItem?
    private var onPlatform: Bool { platform != nil }
    /// Nose-up lean while she rolls up a ramp, in radians.
    private var pitch: Float = 0
    private var cameraLift: Float = 0
    private var landSquash: Float = 0
    private var jumpBuffer: Float = 0
    /// Seconds of duck left. Above 0 she's down in the box.
    private var duckTimer: Float = 0
    /// True until she has ducked under her first low thing, ever. Until then a
    /// one-line hint shows as low things come.
    private var duckHintNeeded = !UserDefaults.standard.bool(forKey: GameScene.duckedKey)
    private var duckHintShown = false
    /// Seconds the spray bottle has left to chase her. 0 means it's gone.
    private var chaseTimer: Float = 0
    /// A beat after a stumble when nothing can trip her again, so one bump that
    /// lasts a few frames doesn't count twice.
    private var stumbleGrace: Float = 0
    /// True once the bottle has caught her: it hangs over her, spraying.
    private var sprayed = false
    private var bottleZ: Float = 9
    private var bottleX: Float = 0
    private var bottleClock: Float = 0
    /// 1 on the home screen, easing to 0 as the camera swoops behind her for the run.
    private var homeBlend: Float = 1
    private var homeClock: Float = 0
    private var runCameraX: Float = 0
    private var homeRotation = simd_quatf(angle: 0, axis: [0, 1, 0])

    private var timeAlive: Float = 0
    /// Seconds since she crashed, counted on the render thread while the panel is up.
    private var deadClock: Float = 0
    /// True once a touch began after the death pause. Lifting it without a swipe restarts.
    private var restartArmed = false
    private var meters: Float = 0
    private var food = 0
    private var bestScore = 0
    private var score: Int { Int(meters) + food * Self.foodPoints }
    private var untilWave: Float = 0
    private var lastWave = -1
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
    /// Test-only: CATCART_TIME=120 starts each run that many seconds into the difficulty ramp.
    private let e2eStartTime = Float(ProcessInfo.processInfo.environment["CATCART_TIME"] ?? "") ?? 0
    /// Test-only: CATCART_WAVE=29 plays only that obstacle mix (its index in `waves`).
    private let e2eWave = Int(ProcessInfo.processInfo.environment["CATCART_WAVE"] ?? "")
    /// Test-only: with CATCART_SWIPES set, every move and stumble prints a line with
    /// the run time, her lane and height, and the top of what she's riding, so a
    /// scripted run can be read without guessing from screenshots.
    private let e2eSwipes = ProcessInfo.processInfo.environment["CATCART_SWIPES"] != nil

    private func testLog(_ what: String) {
        guard e2eSwipes else { return }
        print(String(format: "CATCART %@ at run %.2f s lane %d height %.2f floor %.2f", what, timeAlive, lane, height, floorY))
        fflush(stdout)
    }
    /// Test-only: CATCART_PERF=1 prints frame times and every hitch.
    private var frameLog = FrameLog(enabled: ProcessInfo.processInfo.environment["CATCART_PERF"] == "1")

    /// High enough that a coyote passes under her. A tree roof is always high
    /// enough; the low end of a ramp isn't, but coyotes never stand on one.
    private var isHighEnough: Bool { height > clearHeight }
    /// Low enough to pass under a low thing: down in the box, near the ground.
    private var isDucked: Bool { duckTimer > 0 && height - floorY < 0.3 }
    /// What she rolls on right now: the road, a tree's roof, or a ramp's slope
    /// where she is on it.
    private var floorY: Float { platform?.topAtCat ?? 0 }

    // MARK: - Setup

    init(view: GameSCNView) {
        self.view = view
        self.hud = Hud(size: CGSize(width: 390, height: 844))
        self.scenery = SceneryLibrary()
        super.init()
        bestScore = UserDefaults.standard.integer(forKey: Self.bestKey)
        switch ProcessInfo.processInfo.environment["CATCART_WORLD"]?.lowercased() {
        case "jungle": startWorld = 1
        case "house": startWorld = 2
        case "farm": startWorld = 3
        default: startWorld = 0
        }

        buildCamera()
        buildLights()
        buildPlayer()
        buildPuffs()
        buildBottle()
        prewarmSegments()
        prewarmItems()
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
        prepareForRun(in: view)

        hud.showHome(best: bestScore)
        if e2eAutoRun {
            startRun()
            homeBlend = 0
        }
        if ProcessInfo.processInfo.environment["CATCART_STATS"] == "1" {
            view.showsStatistics = true
        }
        scheduleTestSwipes()
    }

    /// Test-only: CATCART_SWIPES="2:left,3.5:up,5:right" plays swipes at those
    /// seconds after launch through the same touch code a finger uses.
    /// "4:stumble" trips her as if she clipped something. "6:tap" is a finger down
    /// and up without moving. "5:press" puts a finger down and "7:release" lifts it,
    /// for a touch that's still down when she crashes.
    private func scheduleTestSwipes() {
        guard let script = ProcessInfo.processInfo.environment["CATCART_SWIPES"] else { return }
        for step in script.split(separator: ",") {
            let parts = step.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[0]) else { continue }
            let touches: [String: (GameScene) -> Void] = [
                "stumble": { game in game.enqueue(.stumble) },
                "tap": { game in game.touchBegan(at: CGPoint(x: 200, y: 500)); game.touchEnded() },
                "press": { game in game.touchBegan(at: CGPoint(x: 200, y: 500)) },
                "release": { game in game.touchEnded() }
            ]
            if let touch = touches[String(parts[1])] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    if let self { touch(self) }
                }
                continue
            }
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
            plane.materials = [skyMaterials[worldAt(startWorld)]!]
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
        // Shadows are the priciest thing on screen, so they're kept lean: only the
        // cat, coyotes, food, and cat trees cast them (scenery doesn't, see
        // takeSegment), they're worked out while each surface is lit instead of in
        // an extra full-screen pass, and one shadow map covers the near road.
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowColor = UIColor(white: 0, alpha: 0.32)
        sun.shadowRadius = 2
        sun.shadowSampleCount = 4
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.maximumShadowDistance = 45
        sun.shadowCascadeCount = 1
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.95, 0.55, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // The sun shines the way she drives, so her face would sit in shade on the
        // home screen. A soft front light lights only her and the cart (bit 2).
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 380
        fill.color = UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1)
        fill.categoryBitMask = Self.playerLightBit
        fillNode.light = fill
        fillNode.simdLook(at: [0.35, -0.55, 1])
        scene.rootNode.addChildNode(fillNode)
    }

    private func buildPlayer() {
        scene.rootNode.addChildNode(playerRoot)

        catShadow = SCNNode(geometry: groundPlane(width: 2.1, length: 1.6, material: shadowMaterial))
        catShadow.position = SCNVector3(0, 0.03, 0)
        catShadow.renderingOrder = 5
        playerRoot.addChildNode(catShadow)

        // The kitten in her La Croix cart.
        cart = KittenCart()
        catNode = cart.node
        catNode.enumerateHierarchy { node, _ in
            node.categoryBitMask |= Self.playerLightBit
            node.castsShadow = true
        }
        applyLook(to: catNode)
        playerRoot.addChildNode(catNode)

        let aim = SCNNode()
        aim.simdPosition = homeEye
        aim.simdLook(at: homeTarget, up: [0, 1, 0], localFront: [0, 0, -1])
        homeRotation = aim.simdOrientation

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
        worldAt(z: 0)
    }

    /// The world the road is in at this z.
    private func worldAt(z: Float) -> WorldKind {
        segments.first { $0.near >= z && $0.near - segmentLength < z }?.world ?? worldAt(startWorld)
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
            skyA.geometry?.materials = [skyMaterials[here]!]
        }
        if skyBWorld != next {
            skyBWorld = next
            frameLog.note("sky \(next)")
            skyB.geometry?.materials = [skyMaterials[next]!]
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
        genSegmentsLeft = segmentsPerWorld() + Int(((roadBehind + segmentLength) / segmentLength).rounded(.up))
        var near = roadBehind + segmentLength
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
        frameLog.note("built \(world) slice")
        let node = SCNNode()
        let road = SCNNode(geometry: groundPlane(width: 6, length: CGFloat(segmentLength), material: roadMaterials[world]!))
        road.position = SCNVector3(0, 0.01, -segmentLength / 2)
        node.addChildNode(road)
        node.addChildNode(scenery.dressing(for: world, length: segmentLength, seed: genSeed))
        // The road and roadside still receive shadows but never cast them. Casting
        // means drawing all of a slice's buildings again into the shadow map.
        node.enumerateHierarchy { child, _ in child.castsShadow = false }
        applyLook(to: node)
        let seg = Segment(node: node, world: world)
        seg.inUse = true
        segmentPool[world, default: []].append(seg)
        return seg
    }

    /// Builds each world's slices up front so no slice is built mid-run. At top
    /// speed one world is 13 slices long, which can fill the whole road at once,
    /// so each world gets as many slices as the road holds, plus spares.
    private func prewarmSegments() {
        let perWorld = Int(((roadBehind + segmentLength + trackDepth) / segmentLength).rounded(.up)) + 2
        for world in WorldKind.allCases {
            let built = (0..<perWorld).map { _ in takeSegment(world) }
            built.forEach { $0.inUse = false }
        }
    }

    /// Fills the coyote, food, and cat tree pools before the first tap. Building
    /// one mid-run, or drawing a kind of thing for the first time, stalls a frame
    /// (CATCART_PERF=1 shows 33 to 50 ms hitches right after "built tree24").
    /// The counts cover two of the busiest waves on the road at once.
    private func prewarmItems() {
        func stock(_ key: String, _ count: Int, _ make: () -> SCNNode) {
            for _ in 0..<count {
                let node = make()
                node.name = key
                itemPool[key, default: []].append(node)
            }
        }
        // Packed, chained mixes can put well over a dozen coyotes on the road.
        stock("coyote", 22) { makeCoyote() }
        stock("food", 28) { makeFood() }
        for size in Self.treeSizes {
            // Four: the staircase mix uses three of one size, and the mix before
            // it can still have one on the road (a 333 ms stall at 60 s with three).
            stock(treeKey(length: size, roof: shortRoof), 4) { makeCatTree(length: size, roof: shortRoof) }
        }
        // Tall trees: four per size too, for a wall of tall trees across the road
        // with the mix before still in view.
        for size in Self.tallSizes {
            stock(treeKey(length: size, roof: tallRoof), 4) { makeCatTree(length: size, roof: tallRoof) }
        }
        // Ramps hang off the front of a tree and come back to their own pool, so
        // three of each length and height covers two ramps in a mix plus one
        // still on the road from the mix before.
        for size in Self.rampSizes {
            for roof in [shortRoof, tallRoof] {
                stock(rampKey(length: size, roof: roof), 3) { makeRamp(length: size, roof: roof) }
            }
        }
        // The zigzag mix alone has four low things, all in one world, and from
        // 40 s mixes chain with almost no gap.
        for world in WorldKind.allCases {
            stock("low-\(world)", 14) { makeLowThing(world) }
        }
    }

    /// Has SceneKit upload every pooled model and compile its shaders now, in the
    /// background, while the home screen shows.
    private func prepareForRun(in view: SCNView) {
        var objects: [Any] = Array(itemPool.values.joined())
        objects += segmentPool.values.joined().map(\.node)
        objects += Array(skyMaterials.values)
        objects.append(bottle)
        let logging = frameLog.enabled
        let started = Date()
        view.prepare(objects) { done in
            // Runs on a background thread, so it only prints.
            guard logging else { return }
            print(String(format: "CATCART prepare %@ in %.0f ms", done ? "finished" : "failed",
                         -started.timeIntervalSinceNow * 1000))
            fflush(stdout)
        }
    }

    private func moveTrack(dz: Float) {
        for seg in segments {
            seg.node.position.z += dz
        }
        while let first = segments.first, first.near - segmentLength > roadBehind {
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
        frameLog.frame(at: time, runTime: timeAlive)
        handleInput()
        updatePuffs(dt: dt)

        switch state {
        case .running:
            step(dt: dt)
        case .ready:
            // The title screen drives slowly so the world is alive behind the panel.
            homeClock += dt
            moveTrack(dz: runSpeed() * 0.45 * dt)
            updateWorldBlend()
            cart.update(dt: dt, speed: runSpeed() * 0.45, rolling: true, tilt: 0)
            updateCamera(dt: dt)
        case .dead:
            let wasPaused = deadClock < deathPause
            deadClock += dt
            if wasPaused && deadClock >= deathPause {
                hud.showRetry()
            }
            updateChase(dt: dt)
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
            untilWave = spawnWave(at: spawnAhead)
        }

        updateJump(dt: dt)
        if jumpBuffer > 0 {
            jumpBuffer -= dt
            if jump() { jumpBuffer = 0 }
        }
        updateSteer(dt: dt)
        duckTimer = max(0, duckTimer - dt)
        cart.update(dt: dt, speed: speed, rolling: height - floorY < 0.05, tilt: tilt, ducking: duckTimer > 0)
        homeBlend = max(0, homeBlend - dt / 0.9)
        updateRide()
        updateChase(dt: dt)
        moveItems(dz: dz, dt: dt)
        resolveContacts(dz: dz)
        guard state == .running else { return }
        updateCamera(dt: dt)
        updateDuckHint()

        dust.birthRate = height - floorY < 0.05 ? 22 : 0
        dustNode.position.y = floorY + 0.08

        lineClock -= dt
        if lineClock <= 0 {
            lineClock = 0.12
            hud.speedLine(strength: CGFloat(min(1, (speed - 12) / 14)))
        }
        hud.setScore(score)
        hud.setFood(food)
    }

    private func updateCamera(dt: Float) {
        // The camera trails the cat a little: it follows her lane at 60%, and rises
        // when she rides a tree, but it lags so lane changes and landings feel weighty.
        // It follows a ramp's slope the same way, so the climb is smooth.
        cameraLift += (floorY - cameraLift) * min(1, 4 * dt)
        let goalX = visualX * 0.6
        runCameraX += (goalX - runCameraX) * min(1, 9 * dt)
        let x = runCameraX
        // It rises three quarters of the way up to a short roof, then all the way
        // with anything higher, so a tall roof is framed like a short one: the
        // camera stays 2.4 m over her and looks past her head down the road.
        // Rising less there put her head right over the road ahead. In a jump it
        // bobs up a little (0.09 per meter, was 0.12 with the 1.9 m jump, so the
        // camera moves as before and the higher arc shows on screen).
        let rise = min(cameraLift, shortRoof) * 0.75 + max(0, cameraLift - shortRoof)
        let y = cameraBase.y + rise + max(0, height - floorY) * 0.09
        cameraNode.position = SCNVector3(x, y, cameraBase.z)
        cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, -tilt * 0.08)
        // A slightly wider view as the run speeds up.
        let boost = CGFloat(max(0, runSpeed() - 17) * 0.35)
        cameraNode.camera?.fieldOfView = baseFOV + (state == .running ? boost : 0)

        // Home screen, or the swoop from it: mix toward the front view of her face.
        guard homeBlend > 0 else { return }
        let t = homeBlend * homeBlend * (3 - 2 * homeBlend)
        var eye = homeEye
        eye.x += visualX + sin(homeClock * 0.5) * 0.25
        eye.y += sin(homeClock * 0.37) * 0.06
        cameraNode.simdPosition = simd_mix(cameraNode.simdPosition, eye, SIMD3(repeating: t))
        cameraNode.simdOrientation = simd_slerp(cameraNode.simdOrientation, homeRotation, t)
    }

    private func updateJump(dt: Float) {
        vy -= gravity * dt
        height += vy * dt
        if height < floorY {
            // Rolling up a ramp, the slope rises under her by up to 0.25 m a frame
            // (a tall ramp climbs 3.5 m in half a second), so she's carried up
            // with it. Coming down from a jump, only a near miss snaps.
            let snap: Float = jumping ? 0.1 : 0.3
            if vy > 0 {
                // Still rising past the lip of a tree roof: keep the arc.
            } else if floorY - height < snap || !onPlatform {
                height = floorY
                vy = 0
                jumping = false
            } else {
                // Caught a tree roof low: hop up onto it instead of crashing.
                height += (floorY - height) * min(1, 18 * dt)
                vy = 0
                jumping = false
            }
        }

        let airborne = height - floorY > 0.15
        if wasAirborne && !airborne && vy <= 0 {
            landSquash = 1
            puff(at: SCNVector3(visualX, floorY + 0.1, 0.2), count: 10, color: UIColor(white: 1, alpha: 0.9))
            haptic(.medium)
        }
        wasAirborne = airborne

        // Squash on landing, stretch in the air. Small, so she still reads as sitting.
        landSquash = max(0, landSquash - dt * 5)
        let air = min(1, max(0, height - floorY) / jumpPeak)
        let squash = sin(landSquash * .pi) * 0.12
        catNode.scale = SCNVector3(1 + squash - air * 0.03, 1 - squash + air * 0.05, 1)

        // Road bumps while rolling.
        let bump = height - floorY < 0.02 ? sin(timeAlive * 38) * 0.018 : 0
        catNode.position.y = height + bump

        // Nose up while she rolls up a ramp, level again on the roof or in the air.
        var lean: Float = 0
        if let p = platform, p.rampLength > 0, p.z < p.rampLength, height - floorY < 0.05 {
            lean = atan(p.roof / p.rampLength)
        }
        pitch += (lean - pitch) * min(1, 14 * dt)
        catNode.eulerAngles.x = pitch

        // The shadow stays on whatever is under her, and shrinks as she rises.
        // Scaled for the 2.6 m jump, so at the top of a jump it looks as it did at 1.9.
        let lift = max(0, height - floorY)
        catShadow.position.y = floorY + 0.03
        catShadow.eulerAngles.x = pitch
        let s = max(0.45, 1 - lift * 0.16)
        catShadow.scale = SCNVector3(s, s, s)
        catShadow.opacity = CGFloat(max(0.35, 1 - lift * 0.18))
    }

    private func updateSteer(dt: Float) {
        let goal = laneX(lane)
        // Slides between lanes a little quicker as the run speeds up.
        visualX += (goal - visualX) * min(1, (18 + 8 * ramp) * dt)
        playerRoot.position.x = visualX
        tilt *= max(0, 1 - 9 * dt)
        if abs(tilt) < 0.005 { tilt = 0 }
        catNode.eulerAngles.z = tilt
    }

    /// Keeps her on the tree she's riding until its back passes, then hands her to
    /// the next tree in her lane if one is already beside her and she's level with
    /// or above it, or drops her to the road.
    private func updateRide() {
        guard let current = platform else { return }
        if current.lane == lane && overlapsCat(current) { return }
        platform = items
            .filter { $0.kind == .tree && $0.lane == lane && overlapsCat($0) && canReach($0) }
            .max { $0.topAtCat < $1.topAtCat }
    }

    /// Can she get onto this tree right where she is, from the front or the side?
    /// - Rolling (wheels on the road, a roof, or a ramp): only a step up of
    ///   `stepUp` (0.5 m), so the low end of a ramp from the side, never a roof.
    /// - In a jump, at short-tree heights (up to 2.0 m): above `clearHeight`, the
    ///   same height that clears a coyote. That's the old rule: the arc carries
    ///   her onto the roof, or she hops up if she catches it low.
    /// - In a jump, higher than that (a tall roof): within `highReach` (0.5 m) of
    ///   it, which only a jump from a short roof reaches.
    /// Level with it or above, she's always fine; stepping down is just a drop.
    private func canReach(_ tree: TrackItem) -> Bool {
        let top = tree.topAtCat
        let airborne = jumping || height - floorY > 0.15
        let reach: Float
        if !airborne {
            reach = stepUp
        } else if top <= shortRoof + 0.01 {
            reach = max(stepUp, top - clearHeight)
        } else {
            reach = highReach
        }
        return height > top - reach
    }

    private func overlapsCat(_ item: TrackItem) -> Bool {
        item.z >= -0.3 && item.back <= 0.3
    }

    private func moveItems(dz: Float, dt: Float) {
        for item in items {
            item.z += dz
            item.node.position.z = item.nodeZ
            // Transparent pictures draw far to near so they overlap correctly.
            if item.picture != nil || item.node.childNode(withName: "picture", recursively: false) != nil {
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

    // Every mix follows one fairness rule: there's always a way through, and time to
    // steer to it. Some lanes can't be survived by staying in them (a coyote under a
    // low thing), so steering matters, like Subway Surfers. Never all three lanes
    // blocked with no jump, duck, or ride out. Inside a mix, two things in the same
    // lane are at least 19 m apart (written at 17 m/s), so she can land and jump or
    // duck again. A low thing after a coyote gets 24 m, since ducking is its own swipe.
    // Low things (d) never sit beside the middle of a tree, where a rider stepping
    // off would drop right into one. spawnWave keeps the same gaps where one mix
    // meets the next. Check a new mix against this by hand before adding it.

    private static func c(_ lane: Int, _ ahead: Float) -> Spawn { Spawn(kind: .coyote, lane: lane, ahead: ahead) }
    private static func f(_ lane: Int, _ ahead: Float) -> Spawn { Spawn(kind: .food, lane: lane, ahead: ahead) }
    private static func roof(_ lane: Int, _ ahead: Float) -> Spawn { Spawn(kind: .food, lane: lane, ahead: ahead, onRoof: true) }
    /// Food in the air: you only get it by jumping.
    private static func air(_ lane: Int, _ ahead: Float) -> Spawn { Spawn(kind: .food, lane: lane, ahead: ahead, high: true) }
    // Cat trees. Every tree's `ahead` is its front: where she first meets it.
    //   t(1, 0, 14)           short tree, roof 2.0 m: jump on from the road.
    //   tall(1, 0, 14)        tall tree, roof 3.5 m: a wall from the road.
    //   ramp(tall(1, 0, 14))  an 8 m ramp, then the tree. `ahead` is the ramp's
    //                         foot, so the tree's front is at 8 and its back at 22.
    //   ramp(t(1, 0, 14))     the same onto a short tree.
    // Length is at 17 m/s; nil picks 11, 14, or 17. Trees and ramps stretch fully
    // with speed and everything written behind a tree's back moves back with it.
    // Things beside a tree only stretch with the square root, like the rest of a
    // mix, so at speed they slide toward the tree's front (and onto its ramp).
    // Roof food (`roof`) keeps its spot along the tree it was written on, ramp
    // included, and sits on the surface there.
    // Fairness: a tall tree with no ramp and no short tree right before it in its
    // lane is a blocked lane. Low things never stand beside the middle of a tree.
    private static func t(_ lane: Int, _ ahead: Float, _ length: Float? = nil) -> Spawn {
        Spawn(kind: .tree, lane: lane, ahead: ahead, length: length)
    }
    private static func tall(_ lane: Int, _ ahead: Float, _ length: Float? = nil) -> Spawn {
        Spawn(kind: .tree, lane: lane, ahead: ahead, length: length, tall: true)
    }
    /// A ramp in front of a tree: roll onto its foot in its lane and she rides up
    /// onto the roof with no jump. From the side she can only get on near the
    /// bottom (under 0.5 m); higher up the side is a bump.
    private static func ramp(_ tree: Spawn) -> Spawn {
        var out = tree
        out.ramp = true
        return out
    }
    private static func d(_ lane: Int, _ ahead: Float) -> Spawn { Spawn(kind: .low, lane: lane, ahead: ahead) }
    /// A blocked lane: a coyote prowling under a low thing. Jump and you hit the
    /// low thing, duck and you hit the coyote. The only way past is to steer.
    private static func b(_ lane: Int, _ ahead: Float) -> [Spawn] { [c(lane, ahead), d(lane, ahead)] }

    private static let waves: [Wave] = [
        // Easy (first 8 s): two or three things, one move at a time.
        Wave(tier: 0, spawns: [c(1, 0), c(0, 19), c(2, 19), f(1, 19), f(1, 22)]),
        Wave(tier: 0, spawns: [c(0, 0), c(2, 0), f(1, 0), f(1, 3), c(1, 19)]),
        // Food right after a coyote: the reward for jumping it.
        Wave(tier: 0, spawns: [c(1, 0), f(1, 6), f(1, 9), f(1, 12), c(0, 19), c(2, 19)]),
        Wave(tier: 0, spawns: [t(1, 0), c(0, 10), c(2, 20)]),
        Wave(tier: 0, spawns: [t(1, 0, 14), roof(1, 4), roof(1, 7), roof(1, 10), c(0, 8), c(2, 8)]),
        Wave(tier: 0, spawns: [f(0, 0), f(1, 4), f(2, 8), c(1, 16), c(2, 24)]),
        Wave(tier: 0, spawns: [c(0, 0), c(1, 19), c(2, 38), f(2, 0), f(2, 3)]),
        Wave(tier: 0, spawns: [c(1, 0), c(1, 19), f(0, 6), f(0, 9), f(2, 12), f(2, 15)]),
        // Food over a coyote: jump it to eat.
        Wave(tier: 0, spawns: [c(1, 3), air(1, 0), air(1, 3), air(1, 6), c(0, 22), c(2, 22)]),

        // Medium (from 8 s): two lanes busy, slaloms, ducking, the first blocked lanes.
        Wave(tier: 1, spawns: [c(0, 0), c(1, 0), f(2, 0), f(2, 3), c(1, 19), c(2, 19)]),
        Wave(tier: 1, spawns: [t(0, 0), c(2, 0), c(1, 20)]),
        Wave(tier: 1, spawns: [t(2, 0), c(0, 0), f(1, 0), c(1, 20)]),
        Wave(tier: 1, spawns: [t(0, 0), t(1, 0), f(2, 0), f(2, 3), f(2, 6), c(2, 19)]),
        Wave(tier: 1, spawns: [c(1, 0), t(0, 0), c(2, 0), c(1, 22)]),
        // A snake: the coyotes walk across the road and back.
        Wave(tier: 1, spawns: [c(0, 0), c(1, 10), c(2, 20), c(1, 30), c(0, 40)]),
        Wave(tier: 1, spawns: [c(0, 0), c(2, 0), c(1, 22), c(0, 22)]),
        Wave(tier: 1, spawns: [t(1, 0, 17), c(0, 8), c(2, 8), c(0, 28), c(2, 28)]),
        // Jump the coyote, land, then jump up onto the tree.
        Wave(tier: 1, spawns: [c(1, 0), c(0, 10), c(2, 10), t(1, 19, 14), roof(1, 25), roof(1, 28)]),
        Wave(tier: 1, spawns: [d(1, 0), c(0, 0), c(2, 19)], weight: 1.3),
        // Food just past a low thing: the reward for ducking.
        Wave(tier: 1, spawns: [d(1, 0), f(1, 6), f(1, 9), f(1, 12), c(0, 10), c(2, 10)]),
        Wave(tier: 1, spawns: [d(0, 0), d(1, 0), f(2, 0), f(2, 3), f(2, 6), c(2, 19)]),
        Wave(tier: 1, spawns: [d(0, 0), c(2, 0), f(1, 0), f(1, 3), c(1, 19)]),
        // Every lane asks for something: duck, jump, duck.
        Wave(tier: 1, spawns: [d(0, 0), c(1, 0), d(2, 0)]),
        // The first blocked lanes: steer around, with food on the open side.
        Wave(tier: 1, spawns: b(1, 0) + [f(0, 0), f(0, 3), f(0, 6), c(0, 19), c(2, 19)], weight: 1.3),
        Wave(tier: 1, spawns: b(0, 0) + [c(1, 0), f(2, 0), f(2, 3), c(2, 19)]),
        Wave(tier: 1, spawns: b(0, 0) + b(2, 0) + [f(1, 0), f(1, 3), f(1, 6)], rotates: false),
        // Two coyotes close together: a double hop, with food in the air between.
        Wave(tier: 1, spawns: [c(1, 0), c(1, 19), air(1, 9), air(1, 28), f(0, 6), f(2, 12)]),

        // Hard (from 20 s): back-to-back moves.
        // Three coyotes is a forced jump. Rare, per the PRD.
        Wave(tier: 2, spawns: [c(0, 0), c(1, 0), c(2, 0)], weight: 0.4),
        Wave(tier: 2, spawns: [t(0, 0), t(1, 0), c(2, 0), c(2, 19)]),
        Wave(tier: 2, spawns: [c(0, 0), c(1, 0), c(1, 19), c(2, 19), c(0, 38), c(2, 38)]),
        // Ride, then hop to the neighbor tree, or drop and jump the coyote.
        Wave(tier: 2, spawns: [t(0, 0, 14), t(1, 6, 17), c(0, 33), f(2, 0), f(2, 4), f(2, 8)], rotates: false),
        Wave(tier: 2, spawns: [t(1, 0, 14), c(0, 10), c(2, 10), c(1, 33)]),
        Wave(tier: 2, spawns: [c(0, 0), c(2, 10), c(1, 20), c(0, 30), c(2, 30)]),
        // A staircase of trees you can hop up the whole way.
        Wave(tier: 2, spawns: [t(0, 0, 14), t(1, 10, 14), t(2, 20, 14)], rotates: false),
        Wave(tier: 2, spawns: [c(1, 0), c(1, 19), c(1, 38), f(0, 8), f(0, 11), f(2, 27), f(2, 30)]),
        // Three low things is a forced duck, as rare as the three-coyote wall.
        Wave(tier: 2, spawns: [d(0, 0), d(1, 0), d(2, 0)], weight: 0.4),
        // Jump, duck, jump. A low thing after a coyote gets 24 m (1.4 s), not 19:
        // a late jump lands with little time left, and ducking needs its own swipe.
        Wave(tier: 2, spawns: [c(1, 0), d(1, 24), c(1, 43), f(0, 10), f(2, 33)]),
        // Every lane flips: jump or duck now, then the other one.
        Wave(tier: 2, spawns: [d(0, 0), c(1, 0), d(2, 0), c(0, 24), d(1, 24), c(2, 24)]),
        Wave(tier: 2, spawns: [t(0, 0, 17), d(1, 0), c(2, 0), d(2, 24)], rotates: false),
        // Both sides blocked: get to the middle and jump.
        Wave(tier: 2, spawns: b(0, 0) + [c(1, 0)] + b(2, 0) + [f(1, 6), f(1, 9)], rotates: false),
        // Every lane asks for something different: jump, steer, or duck.
        Wave(tier: 2, spawns: [c(0, 0)] + b(1, 0) + [d(2, 0)]),
        // A zigzag: the open lane jumps from one side to the other.
        Wave(tier: 2, spawns: b(0, 0) + b(1, 0) + [f(2, 0), f(2, 3), f(2, 6)]
                + b(1, 26) + b(2, 26) + [f(0, 26), f(0, 29), f(0, 32)], rotates: false),
        // A gate: both sides blocked, a tree in the middle to ride through.
        Wave(tier: 2, spawns: b(0, 0) + [t(1, 0, 14), roof(1, 5), roof(1, 8)] + b(2, 0), rotates: false),
        // Blocked in front, then a coyote in the lane you steered to.
        Wave(tier: 2, spawns: b(1, 0) + [c(0, 19), c(2, 19), air(0, 16), air(0, 19), air(0, 22)]),
        // Middle blocked with coyotes beside it: jump on the side. Then the sides
        // block and the middle has the coyote: jump, land, steer in, jump again.
        Wave(tier: 2, spawns: [c(0, 0)] + b(1, 0) + [c(2, 0)] + b(0, 26) + [c(1, 26)] + b(2, 26), rotates: false),
        // A blocked lane walks across the road with a coyote beside it.
        Wave(tier: 2, spawns: b(0, 0) + [c(1, 0)] + b(1, 22) + [c(2, 22)] + b(2, 44) + [c(0, 44)], rotates: false),

        // provisional, step 7 rewrites. Tall trees and ramps, kept in the middle
        // lane (rotates: false) so CATCART_WAVE runs are easy to script.
        // Ramp up: roll up onto a tall tree in the middle; coyotes on both sides.
        // The easy way through is up. Side lanes are two coyotes, 19 m apart.
        Wave(tier: 1, spawns: [ramp(tall(1, 0, 14)), c(0, 6), c(2, 6), c(0, 25), c(2, 25),
                               roof(1, 13), roof(1, 16), roof(1, 19)], rotates: false),
        // Staircase up: a short tree, then a tall one right behind it. Jump on,
        // then jump from the short roof up to the tall one (or crash into its
        // front). The sides are two coyotes each.
        Wave(tier: 2, spawns: [t(1, 0, 14), tall(1, 14, 14), c(0, 6), c(2, 6), c(0, 25), c(2, 25),
                               roof(1, 18), roof(1, 21), roof(1, 24)], rotates: false),
        // Step down: a ramp up a tall tree, a short tree beside it on the right.
        // Step right off the tall roof and drop onto the short one, where the food
        // is. Or jump onto the short tree from the road, or jump the left coyotes.
        Wave(tier: 2, spawns: [ramp(tall(1, 0, 14)), t(2, 8, 20), c(0, 6), c(0, 25),
                               roof(2, 24), roof(2, 27)], rotates: false)
    ]

    /// Cat tree lengths we build meshes for. Stretched lengths snap to one of these
    /// so the tree pool stays small. Tall trees and ramps get fewer sizes: they're
    /// rarer, and each size costs three or four meshes built before the run.
    /// They reach about 38 m: a 17 m tree at 38 m/s, the most speed creeps up to
    /// after full ramp. A ramp at 38 m/s wants 17.9 m and gets 17.
    private static let treeSizes: [Float] = [11, 14, 17, 20, 24, 28, 32, 36, 40]
    private static let tallSizes: [Float] = [12, 16, 21, 26, 32, 38]
    private static let rampSizes: [Float] = [8, 11, 14, 17]

    private static func snap(_ length: Float, to sizes: [Float]) -> Float {
        sizes.min { abs($0 - length) < abs($1 - length) } ?? length
    }

    /// Pool names: "tree14" for a short tree, "tall16", "ramp11-tall".
    private func treeKey(length: Float, roof: Float) -> String {
        (roof > shortRoof ? "tall" : "tree") + "\(Int(length))"
    }
    private func rampKey(length: Float, roof: Float) -> String {
        "ramp\(Int(length))-" + (roof > shortRoof ? "tall" : "short")
    }

    /// Seconds into a run when medium and hard mixes join. Fixed in seconds, so a
    /// change to the ramp doesn't move them.
    private let mediumFrom: Float = 8
    private let hardFrom: Float = 20

    /// Picks a mix for this point in the run: easy ones fade out, harder ones fade in.
    /// Easy mixes thin out and reach their floor of 15% weight at about 28 s, so they never vanish.
    private func pickWave() -> Int {
        if let forced = e2eWave, Self.waves.indices.contains(forced) { return forced }
        let tierWeight: [Float] = [
            max(0.15, 1 - 1.4 * ramp),
            timeAlive >= mediumFrom ? min(1, 0.4 + ramp) : 0,
            timeAlive >= hardFrom ? 0.4 + 1.3 * ramp : 0
        ]
        let choices = Self.waves.indices.filter { $0 != lastWave }
        let weights = choices.map { tierWeight[Self.waves[$0].tier] * Self.waves[$0].weight }
        var roll = Float.random(in: 0..<weights.reduce(0, +))
        for (index, weight) in zip(choices, weights) {
            roll -= weight
            if roll < 0 { return index }
        }
        return choices[0]
    }

    /// Drops one wave of coyotes, food, and trees `base` meters ahead (far ahead,
    /// in the fog, except when filling the road at the start of a run).
    /// Returns how many meters until the next wave.
    private func spawnWave(at base: Float) -> Float {
        lastWave = pickWave()
        let wave = Self.waves[lastWave]
        let mirror = Bool.random()
        let rot = wave.rotates ? Int.random(in: 0...2) : 0
        func place(_ lane: Int) -> Int {
            let turned = (lane + rot) % 3
            return mirror ? 2 - turned : turned
        }
        let scale = spacingScale
        // Trees (and their ramps) stretch with speed more than the rest of the mix
        // does. Anything written behind a tree's end moves back by that extra
        // length, so the road after a ride keeps its timing.
        struct TreePlan {
            let spawn: Spawn
            let lane: Int
            let roof: Float
            /// Tree and ramp lengths as written (17 m/s) and as built (stretched, snapped).
            let written: Float
            let length: Float
            let rampWritten: Float
            let rampLength: Float
            var writtenTotal: Float { rampWritten + written }
            var total: Float { rampLength + length }
        }
        let trees: [TreePlan] = wave.spawns.filter { $0.kind == .tree }.map { spawn in
            let written: Float = spawn.length ?? [11, 14, 17].randomElement() ?? 14
            let rampWritten: Float = spawn.ramp ? Self.rampWritten : 0
            return TreePlan(
                spawn: spawn, lane: place(spawn.lane), roof: spawn.tall ? tallRoof : shortRoof,
                written: written,
                length: Self.snap(written * treeScale, to: spawn.tall ? Self.tallSizes : Self.treeSizes),
                rampWritten: rampWritten,
                rampLength: spawn.ramp ? Self.snap(rampWritten * treeScale, to: Self.rampSizes) : 0)
        }
        func ahead(_ spawn: Spawn) -> Float {
            var out = spawn.ahead * scale
            for tree in trees where tree.spawn.ahead + tree.writtenTotal <= spawn.ahead + 0.01 {
                out += max(0, tree.total - tree.writtenTotal * scale)
            }
            return out
        }

        // Where this mix meets the one before, keep the same gaps as inside a mix:
        // 19 m from the end of the last thing in a lane to the next one, 24 m from a
        // coyote to a low thing. If a lane is too close, the whole mix moves back.
        var shift: Float = 0
        for spawn in wave.spawns where spawn.kind != .food {
            let lane = place(spawn.lane)
            let front = base + ahead(spawn)
            for item in items where item.lane == lane && item.kind != .food {
                let lastEnd = item.length - item.z
                let gap: Float = (item.kind == .coyote && spawn.kind == .low ? 24 : 19) * scale
                shift = max(shift, lastEnd + gap - front)
            }
        }

        var reach: Float = 0
        var placed: [(plan: TreePlan, start: Float, item: TrackItem)] = []
        for tree in trees {
            let start = ahead(tree.spawn) + shift
            let item = addItem(.tree, lane: tree.lane, z: -base - start, length: tree.total,
                               roof: tree.roof, rampLength: tree.rampLength)
            placed.append((tree, start, item))
            reach = max(reach, start + tree.total)
        }
        for spawn in wave.spawns where spawn.kind != .tree {
            let lane = place(spawn.lane)
            var at = ahead(spawn) + shift
            var y: Float = 0
            // Roof food rides on the tree it was written on: the last one in its lane
            // that starts at or before it. It keeps its spot along that tree (on the
            // ramp it stretches with the ramp) and sits on the surface there.
            let host = placed.filter { $0.plan.lane == lane && $0.plan.spawn.ahead <= spawn.ahead + 0.01 }
                .max { $0.plan.spawn.ahead < $1.plan.spawn.ahead }
            if spawn.onRoof, let host {
                let written = spawn.ahead - host.plan.spawn.ahead
                var depth = written < host.plan.rampWritten
                    ? written * host.plan.rampLength / host.plan.rampWritten
                    : host.plan.rampLength + (written - host.plan.rampWritten) * scale
                // Snapping the tree length can shorten it a little. Keep roof food on the roof.
                depth = min(depth, host.plan.total - 1.5)
                at = host.start + depth
                y = host.item.top(at: depth) + 0.05
            }
            addItem(spawn.kind, lane: lane, z: -base - at, high: spawn.high, y: y)
            reach = max(reach, at)
        }
        // A short beat after the mix, in seconds so it means the same at any speed:
        // 0.9 s at the start, 0.45 s at 30 s, down to 0.25 s at full ramp (75 s),
        // so mixes run into each other. The per-lane gaps above are what keep the joins fair.
        let gapSeconds: Float = max(0.25, 0.9 - 0.7 * ramp)
        return reach + runSpeed() * gapSeconds
    }

    /// Puts one thing on the road. For a cat tree, `length` includes its ramp.
    /// `y` lifts food onto a roof.
    @discardableResult
    private func addItem(_ kind: Kind, lane: Int, z: Float, length: Float = 0, roof: Float = 0,
                         rampLength: Float = 0, high: Bool = false, y: Float = 0) -> TrackItem {
        let node: SCNNode
        var picture: SCNMaterial?
        var rampNode: SCNNode?
        switch kind {
        case .coyote:
            node = takeNode("coyote") { self.makeCoyote() }
            picture = node.childNode(withName: "picture", recursively: true)?.geometry?.firstMaterial
            picture?.diffuse.contents = coyoteFrames.first

        case .food:
            node = takeNode("food") { self.makeFood() }
        case .tree:
            let treeLength = length - rampLength
            node = takeNode(treeKey(length: treeLength, roof: roof)) { self.makeCatTree(length: treeLength, roof: roof) }
            if rampLength > 0 {
                // The ramp hangs off the tree's front, so it moves with it.
                let r = takeNode(rampKey(length: rampLength, roof: roof)) { self.makeRamp(length: rampLength, roof: roof) }
                node.addChildNode(r)
                rampNode = r
            }
        case .low:
            // A scaffold in the city, a log in the jungle: whichever world the
            // road is in where it appears, far ahead.
            let world = worldAt(z: z)
            node = takeNode("low-\(world)") { self.makeLowThing(world) }
        }
        let item = TrackItem(kind: kind, lane: lane, node: node, z: z)
        switch kind {
        case .low: item.length = Self.lowDepth
        case .coyote: item.length = coyoteLength
        default: item.length = length
        }
        item.roof = roof
        item.rampLength = rampLength
        item.ramp = rampNode
        item.picture = picture
        item.frame = Int.random(in: 0..<4)
        item.high = high
        // Food in the air hangs where a jump's arc carries her, and drops its shadow.
        node.childNode(withName: "shadow", recursively: false)?.isHidden = high
        node.position = SCNVector3(laneX(lane), high ? airFoodY : y, item.nodeZ)
        scene.rootNode.addChildNode(node)
        items.append(item)
        return item
    }

    private func takeNode(_ key: String, make: () -> SCNNode) -> SCNNode {
        if var free = itemPool[key], let node = free.popLast() {
            itemPool[key] = free
            return node
        }
        frameLog.note("built \(key)")
        let node = make()
        node.name = key
        return node
    }

    private func recycle(_ item: TrackItem) {
        item.node.removeFromParentNode()
        if let key = item.node.name {
            itemPool[key, default: []].append(item.node)
        }
        // A ramp goes back to its own pool, ready for any tree of its height.
        if let ramp = item.ramp {
            ramp.removeFromParentNode()
            if let key = ramp.name {
                itemPool[key, default: []].append(ramp)
            }
            item.ramp = nil
        }
    }

    private func makeCoyote() -> SCNNode {
        if let model = coyoteModel {
            let node = SCNNode()
            let coyote = model.clone()
            // The saved model may change size. Keep its nose on the item's
            // front edge, where contact is measured, using its actual bounds.
            let bounds = coyote.boundingBox
            coyote.position = SCNVector3(0, 0, -bounds.max.z)
            node.addChildNode(coyote)
            applyLook(to: node)
            let shadow = shadowNode(width: 1.0, length: 2.2)
            shadow.position.z = -1.07
            node.addChildNode(shadow)
            return node
        }
        // No model in the bundle: fall back to the flat snarling picture.
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
        let node: SCNNode
        let pickup: SCNNode?
        if let model = foodModel {
            node = SCNNode()
            let can = model.clone()
            node.addChildNode(can)
            pickup = can
        } else {
            // Keep the existing sprite as a fallback if an asset is missing.
            node = billboard(image: UIImage(named: "wetFood"), width: 1.0)
            pickup = node.childNode(withName: "picture", recursively: true)
        }
        if let pickup {
            pickup.position.y += 0.3
            pickup.runAction(.repeatForever(.sequence([
                .group([.moveBy(x: 0, y: 0.14, z: 0, duration: 0.45), .rotateBy(x: 0, y: 0, z: 0.08, duration: 0.45)]),
                .group([.moveBy(x: 0, y: -0.14, z: 0, duration: 0.45), .rotateBy(x: 0, y: 0, z: -0.08, duration: 0.45)])
            ])))
        }
        // Real meshes need the same road bend and fog as every other object.
        applyLook(to: node)
        let shadow = shadowNode(width: 0.7, length: 0.55)
        shadow.name = "shadow"
        node.addChildNode(shadow)
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
    /// A short tree (roof 2.0 m) has one story of cubbies; a tall one (3.5 m) has
    /// a carpeted shelf halfway up and a second story of cubbies on it.
    private func makeCatTree(length: Float, roof roofTop: Float) -> SCNNode {
        let root = SCNNode()
        // The roof, base, posts, and cubbies are built as separate pieces, then
        // merged into one mesh below, so SceneKit draws the whole frame in about
        // five calls (one per material) instead of one per piece (about 40).
        let parts = SCNNode()
        let width: CGFloat = 1.75
        let L = CGFloat(length)
        let stories = roofTop > shortRoof + 0.01 ? 2 : 1

        let topTex = carpetTop.copy() as! SCNMaterial
        topTex.diffuse.contentsTransform = SCNMatrix4MakeScale(1, Float(L / width), 1)
        let sideLong = carpetSide.copy() as! SCNMaterial
        sideLong.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(L / width), 0.2, 1)

        // Roof: thick, fluffy, and a lighter color than the road, so it reads as a platform.
        let roof = SCNBox(width: width, height: 0.26, length: L, chamferRadius: 0.1)
        roof.materials = [carpetSide, sideLong, carpetSide, sideLong, topTex, carpetSide]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, roofTop - 0.13, -length / 2)
        parts.addChildNode(roofNode)

        // Base plate on the ground.
        let base = SCNBox(width: width, height: 0.16, length: L, chamferRadius: 0.05)
        base.materials = [carpetSide, sideLong, carpetSide, sideLong, carpetSide, carpetSide]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.08, -length / 2)
        parts.addChildNode(baseNode)

        // Each story is the space from one floor (the base, or the shelf) up to the
        // next. A tall tree's shelf is a thinner carpet deck the length of the tree.
        let storyHeight = (roofTop - 0.26 - 0.16) / Float(stories)
        if stories == 2 {
            let shelf = SCNBox(width: width - 0.08, height: 0.14, length: L - 0.2, chamferRadius: 0.05)
            shelf.materials = [carpetSide, sideLong, carpetSide, sideLong, carpetSide, carpetSide]
            let shelfNode = SCNNode(geometry: shelf)
            shelfNode.position = SCNVector3(0, 0.16 + storyHeight - 0.07, -length / 2)
            parts.addChildNode(shelfNode)
        }

        // Sisal posts down both sides, floor to roof.
        let postHeight = CGFloat(roofTop - 0.3)
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
                parts.addChildNode(p)
            }
        }

        // Cubbies in every other bay, each with a dark round doorway facing the cat.
        // On a tall tree the upper story's cubbies sit in the bays between the
        // lower ones, so the front shows one low and one high doorway.
        let cubbyHeight = storyHeight * 0.7
        let cubby = SCNBox(width: 1.25, height: CGFloat(cubbyHeight), length: 1.3, chamferRadius: 0.12)
        cubby.materials = [carpetSide]
        let hole = SCNCylinder(radius: CGFloat(min(0.36, cubbyHeight * 0.33)), height: 0.02)
        let holeMat = SCNMaterial()
        holeMat.diffuse.contents = UIColor(red: 0.20, green: 0.13, blue: 0.10, alpha: 1)
        holeMat.lightingModel = .constant
        hole.materials = [holeMat]
        for story in 0..<stories {
            let floor = 0.16 + Float(story) * storyHeight
            for i in stride(from: story, to: bays, by: 2) {
                let z = -0.35 - (Float(i) + 0.5) * (length - 0.7) / Float(bays)
                let c = SCNNode(geometry: cubby)
                c.position = SCNVector3(0, floor + cubbyHeight / 2, z)
                parts.addChildNode(c)
                // The doorway goes straight on `parts`, not inside the cubby: the
                // merge kept only its own offset, so as a grandchild it ended up
                // half sunk in the road in front of the tree.
                let h = SCNNode(geometry: hole)
                h.eulerAngles.x = .pi / 2
                h.position = SCNVector3(0, floor + cubbyHeight / 2 - 0.05, z + 0.66)
                parts.addChildNode(h)
            }
        }
        // The look goes on before merging. A merged mesh starts with no materials
        // and picks up the pieces' ones later, so applyLook on the merged node
        // finds nothing, and the tree would float unbent over the far road.
        applyLook(to: parts)
        root.addChildNode(parts.flattenedClone())

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
        hanger.position = SCNVector3(0.7, roofTop - 0.26, -0.3)
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

    // MARK: - Ramp

    /// A carpeted ramp up to a tree's roof: a solid wedge from the road at its foot
    /// (z = +length) to the roof's height at its top (z = 0), where it meets the
    /// tree's front. It's added as a child of the tree's node, so it moves with it.
    /// Sisal rope runs along both top edges so it reads as cat furniture, not a
    /// road. The wedge is cut into short slices along its length so the
    /// curved-world bend bends it with the road. Merged into one mesh like a tree.
    private func makeRamp(length: Float, roof: Float) -> SCNNode {
        let root = SCNNode()
        let parts = SCNNode()
        let w: Float = 1.75
        let slices = max(4, Int((length / 1.5).rounded()))
        let slope = (length * length + roof * roof).squareRoot()

        // Points along the slope, top (i = 0) to foot (i = slices).
        func station(_ i: Int) -> (z: Float, y: Float, along: Float) {
            let f = Float(i) / Float(slices)
            return (length * f, roof * (1 - f), slope * f)
        }
        var verts: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var top: [UInt16] = []
        var sides: [UInt16] = []
        func add(_ p: SCNVector3, _ n: SCNVector3, _ uv: CGPoint) -> UInt16 {
            verts.append(p)
            normals.append(n)
            uvs.append(uv)
            return UInt16(verts.count - 1)
        }
        // The slope: carpet top, tiled one square per lane width like the roof.
        let up = simd_normalize(SIMD3<Float>(0, length, roof))
        let upN = SCNVector3(up.x, up.y, up.z)
        for i in 0..<slices {
            let a = station(i), b = station(i + 1)
            let p0 = add(SCNVector3(-w / 2, a.y, a.z), upN, CGPoint(x: 0, y: CGFloat(a.along / w)))
            let p1 = add(SCNVector3(w / 2, a.y, a.z), upN, CGPoint(x: 1, y: CGFloat(a.along / w)))
            let p2 = add(SCNVector3(w / 2, b.y, b.z), upN, CGPoint(x: 1, y: CGFloat(b.along / w)))
            let p3 = add(SCNVector3(-w / 2, b.y, b.z), upN, CGPoint(x: 0, y: CGFloat(b.along / w)))
            top += [p0, p3, p2, p0, p2, p1]
        }
        // The two sides: carpet, tiled like the sides of a tree's roof.
        for side: Float in [-1, 1] {
            let x = side * w / 2
            let n = SCNVector3(side, 0, 0)
            for i in 0..<slices {
                let a = station(i), b = station(i + 1)
                let lo0 = add(SCNVector3(x, 0, a.z), n, CGPoint(x: CGFloat(a.z / w), y: 0))
                let hi0 = add(SCNVector3(x, a.y, a.z), n, CGPoint(x: CGFloat(a.z / w), y: CGFloat(a.y / 1.3)))
                let hi1 = add(SCNVector3(x, b.y, b.z), n, CGPoint(x: CGFloat(b.z / w), y: CGFloat(b.y / 1.3)))
                let lo1 = add(SCNVector3(x, 0, b.z), n, CGPoint(x: CGFloat(b.z / w), y: 0))
                // Counter-clockwise seen from outside, so each side faces out.
                sides += side < 0 ? [lo0, lo1, hi0, hi0, lo1, hi1] : [lo0, hi0, lo1, hi0, hi1, lo1]
            }
        }
        // The back, against the tree's front, for when you see it through the posts.
        let back = SCNVector3(0, 0, -1)
        let q0 = add(SCNVector3(-w / 2, 0, 0), back, CGPoint(x: 0, y: 0))
        let q1 = add(SCNVector3(w / 2, 0, 0), back, CGPoint(x: 1, y: 0))
        let q2 = add(SCNVector3(w / 2, roof, 0), back, CGPoint(x: 1, y: CGFloat(roof / 1.3)))
        let q3 = add(SCNVector3(-w / 2, roof, 0), back, CGPoint(x: 0, y: CGFloat(roof / 1.3)))
        sides += [q0, q3, q1, q1, q3, q2]

        let wedge = SCNGeometry(
            sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals),
                      SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: top, primitiveType: .triangles),
                       SCNGeometryElement(indices: sides, primitiveType: .triangles)])
        // The plain carpet materials repeat, and the coordinates above already say
        // how many times, so every ramp shares the same two materials.
        wedge.materials = [carpetTop, carpetSide]
        parts.addChildNode(SCNNode(geometry: wedge))

        // Sisal rope along both top edges, from the foot up to the roof.
        let ropeMat = sisal.copy() as! SCNMaterial
        ropeMat.diffuse.contentsTransform = SCNMatrix4MakeScale(1, slope * 1.5, 1)
        let edge = SCNCylinder(radius: 0.08, height: CGFloat(slope))
        edge.heightSegmentCount = slices
        edge.materials = [ropeMat, carpetSide, carpetSide]
        for x in [-w / 2 + 0.05, w / 2 - 0.05] {
            let e = SCNNode(geometry: edge)
            // A cylinder stands along y. Tip it forward to lie along the slope.
            e.eulerAngles.x = atan(roof / length) - .pi / 2
            e.position = SCNVector3(x, roof / 2 + 0.04, length / 2)
            parts.addChildNode(e)
        }
        applyLook(to: parts)
        root.addChildNode(parts.flattenedClone())

        // A soft shadow on the road under it.
        let shade = SCNNode(geometry: groundPlane(width: CGFloat(w) + 0.5, length: CGFloat(length) + 0.4, material: shadowMaterial))
        shade.position = SCNVector3(0, 0.025, length / 2)
        shade.castsShadow = false
        root.addChildNode(shade)

        applyLook(to: root)
        return root
    }

    // MARK: - Low things

    /// How deep a low thing is, front to back. The table is the deepest.
    private static let lowDepth: Float = 1.1
    /// Posts stand just inside the lane edges, so the cart fits between them.
    private let lowPostX: Float = 0.9

    /// Low-thing materials, made once and shared by every copy, so building a
    /// spare one never uploads a texture or compiles a shader.
    private var lowMaterials: [String: SCNMaterial] = [:]

    private func flatMaterial(_ key: String, _ color: UIColor, image: @autoclosure () -> UIImage? = nil,
                              tweak: (SCNMaterial) -> Void = { _ in }) -> SCNMaterial {
        if let m = lowMaterials[key] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = image() ?? color
        Self.smoothSampling(m.diffuse)
        m.lightingModel = .lambert
        m.isDoubleSided = true
        tweak(m)
        lowMaterials[key] = m
        return m
    }

    private func box(_ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, at p: SCNVector3, round: CGFloat = 0.02) -> SCNNode {
        let b = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: round)
        b.materials = [m]
        let n = SCNNode(geometry: b)
        n.position = p
        return n
    }

    /// Something low across one lane, front edge at z = 0. Its underside is at
    /// lowClearance with nothing under it down to the road, so the gap reads as
    /// "go under". Pieces are merged into one mesh, like the cat tree.
    private func makeLowThing(_ world: WorldKind) -> SCNNode {
        let root = SCNNode()
        let parts = SCNNode()
        let u = lowClearance
        let px = lowPostX
        switch world {
        case .city:
            // Construction scaffold: steel poles on feet, a striped plank across.
            let steel = flatMaterial("steel", UIColor(white: 0.62, alpha: 1))
            let stripes = flatMaterial("stripes", .orange, image: Self.drawStripes()) {
                $0.diffuse.contentsTransform = SCNMatrix4MakeScale(2.5, 1, 1)
                $0.diffuse.wrapS = .repeat
            }
            let top: Float = u + 0.32
            for x in [-px, px] {
                parts.addChildNode(box(0.1, top + 0.08, 0.1, steel, at: SCNVector3(x, (top + 0.08) / 2, -0.3)))
                parts.addChildNode(box(0.34, 0.06, 0.5, steel, at: SCNVector3(x, 0.03, -0.3)))
            }
            parts.addChildNode(box(2 * px + 0.2, 0.3, 0.16, stripes, at: SCNVector3(0, u + 0.15, -0.15)))
            // A second rail behind, so it looks built, not balanced.
            parts.addChildNode(box(2 * px, 0.08, 0.08, steel, at: SCNVector3(0, top, -0.5)))
            let amber = flatMaterial("amber", UIColor(red: 1.0, green: 0.62, blue: 0.1, alpha: 1)) {
                $0.emission.contents = UIColor(red: 0.9, green: 0.45, blue: 0.0, alpha: 1)
            }
            let lamp = SCNSphere(radius: 0.08)
            lamp.materials = [amber]
            let lampNode = SCNNode(geometry: lamp)
            lampNode.position = SCNVector3(px, top + 0.16, -0.3)
            parts.addChildNode(lampNode)

        case .jungle:
            // A mossy log lying across two tall stumps.
            let bark = flatMaterial("bark", UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1))
            let ring = flatMaterial("ring", UIColor(red: 0.85, green: 0.68, blue: 0.45, alpha: 1))
            let moss = flatMaterial("moss", UIColor(red: 0.38, green: 0.62, blue: 0.22, alpha: 1))
            for x in [-px, px] {
                let stump = SCNCone(topRadius: 0.16, bottomRadius: 0.24, height: CGFloat(u))
                stump.materials = [bark, ring, bark]
                let n = SCNNode(geometry: stump)
                n.position = SCNVector3(x, u / 2, -0.4)
                parts.addChildNode(n)
            }
            let r: Float = 0.22
            let log = SCNCylinder(radius: CGFloat(r), height: CGFloat(2 * px + 0.5))
            log.materials = [bark, ring, ring]
            let logNode = SCNNode(geometry: log)
            logNode.eulerAngles.z = .pi / 2
            logNode.position = SCNVector3(0, u + r, -0.4)
            parts.addChildNode(logNode)
            for (x, sx) in [(-0.6, 0.32), (0.05, 0.42), (0.7, 0.3)] as [(Float, Float)] {
                let blob = SCNSphere(radius: 1)
                blob.segmentCount = 10
                blob.materials = [moss]
                let n = SCNNode(geometry: blob)
                n.scale = SCNVector3(sx, 0.09, 0.2)
                n.position = SCNVector3(x, u + 2 * r - 0.02, -0.4)
                parts.addChildNode(n)
            }

        case .house:
            // A wooden table with a gingham cloth. The cloth's hem is the low edge.
            let wood = flatMaterial("wood", UIColor(red: 0.62, green: 0.40, blue: 0.22, alpha: 1))
            let cloth = flatMaterial("gingham", .red, image: Self.drawGingham()) {
                $0.diffuse.wrapS = .repeat
                $0.diffuse.wrapT = .repeat
                $0.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
            }
            let depth = Self.lowDepth
            let hem: Float = 0.2
            let top = u + hem
            for x in [-px + 0.08, px - 0.08] {
                for z in [-0.12, -depth + 0.12] {
                    parts.addChildNode(box(0.1, top, 0.1, wood, at: SCNVector3(x, top / 2, z)))
                }
            }
            parts.addChildNode(box(2 * px, 0.08, depth, wood, at: SCNVector3(0, top + 0.04, -depth / 2)))
            parts.addChildNode(box(2 * px + 0.08, 0.025, depth + 0.08, cloth, at: SCNVector3(0, top + 0.09, -depth / 2), round: 0))
            // Hems drape over the front and back edges.
            for z in [0.03, -depth - 0.03] {
                parts.addChildNode(box(2 * px + 0.08, hem, 0.02, cloth, at: SCNVector3(0, top + 0.1 - hem / 2, z), round: 0))
            }
            // A mug and a little vase so it reads as a table at a glance.
            let mug = SCNCylinder(radius: 0.09, height: 0.18)
            mug.materials = [flatMaterial("mug", UIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))]
            let mugNode = SCNNode(geometry: mug)
            mugNode.position = SCNVector3(-0.45, top + 0.19, -0.5)
            parts.addChildNode(mugNode)
            let vase = SCNSphere(radius: 0.12)
            vase.materials = [flatMaterial("vase", UIColor(red: 0.45, green: 0.72, blue: 0.85, alpha: 1))]
            let vaseNode = SCNNode(geometry: vase)
            vaseNode.position = SCNVector3(0.4, top + 0.21, -0.6)
            parts.addChildNode(vaseNode)
            let bloom = SCNSphere(radius: 0.09)
            bloom.materials = [flatMaterial("bloom", UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1))]
            let bloomNode = SCNNode(geometry: bloom)
            bloomNode.position = SCNVector3(0.4, top + 0.45, -0.6)
            parts.addChildNode(bloomNode)

        case .farm:
            // A clothesline on two T posts with a sheet hanging down to the low edge.
            let post = flatMaterial("post", UIColor(red: 0.55, green: 0.40, blue: 0.26, alpha: 1))
            let line = flatMaterial("line", UIColor(white: 0.95, alpha: 1))
            let sheet = flatMaterial("sheet", .blue, image: Self.drawSheet())
            let lineY = u + 0.72
            for x in [-px, px] {
                parts.addChildNode(box(0.12, lineY + 0.14, 0.12, post, at: SCNVector3(x, (lineY + 0.14) / 2, -0.2)))
                parts.addChildNode(box(0.08, 0.08, 0.5, post, at: SCNVector3(x, lineY + 0.06, -0.2)))
            }
            let rope = SCNCylinder(radius: 0.015, height: CGFloat(2 * px))
            rope.materials = [line]
            let ropeNode = SCNNode(geometry: rope)
            ropeNode.eulerAngles.z = .pi / 2
            ropeNode.position = SCNVector3(0, lineY, -0.2)
            parts.addChildNode(ropeNode)
            let cloth = SCNPlane(width: CGFloat(2 * px - 0.25), height: CGFloat(lineY - u))
            cloth.materials = [sheet]
            let clothNode = SCNNode(geometry: cloth)
            clothNode.position = SCNVector3(0, (lineY + u) / 2, -0.2)
            parts.addChildNode(clothNode)
            let pin = flatMaterial("pin", UIColor(red: 0.95, green: 0.85, blue: 0.6, alpha: 1))
            for x in [-0.55, 0.0, 0.55] as [Float] {
                parts.addChildNode(box(0.04, 0.12, 0.05, pin, at: SCNVector3(x, lineY - 0.02, -0.19), round: 0.01))
            }
        }
        // Before merging, like the cat tree, so the merged mesh keeps the bend.
        applyLook(to: parts)
        root.addChildNode(parts.flattenedClone())

        // A soft dark strip on the road under it, like the tree's shadow.
        let shade = SCNNode(geometry: groundPlane(width: CGFloat(2 * px + 0.3), length: CGFloat(Self.lowDepth + 0.6), material: shadowMaterial))
        shade.position = SCNVector3(0, 0.025, -Self.lowDepth / 2)
        shade.castsShadow = false
        root.addChildNode(shade)

        applyLook(to: root)
        return root
    }

    // MARK: - Spray bottle

    /// A green plastic spray bottle, the thing every cat dreads. Built from simple
    /// shapes: a tall bottle, a white neck, a trigger head with the nozzle pointed
    /// at her. It stands about 1 m tall, so it peeks up behind the cart, and it's
    /// turned side-on so the camera sees the trigger, not the back of the head.
    private func buildBottle() {
        let plastic = SCNMaterial()
        plastic.diffuse.contents = UIColor(red: 0.20, green: 0.74, blue: 0.36, alpha: 1)
        plastic.specular.contents = UIColor(white: 1, alpha: 0.9)
        plastic.shininess = 40
        plastic.lightingModel = .blinn
        let label = SCNMaterial()
        label.diffuse.contents = UIColor(red: 0.86, green: 0.97, blue: 0.88, alpha: 1)
        label.lightingModel = .lambert
        let white = SCNMaterial()
        white.diffuse.contents = UIColor(white: 0.97, alpha: 1)
        white.specular.contents = UIColor(white: 1, alpha: 0.6)
        white.shininess = 25
        white.lightingModel = .blinn
        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(red: 0.10, green: 0.42, blue: 0.20, alpha: 1)
        dark.lightingModel = .lambert

        let model = SCNNode()
        // Flat-bottomed body, a sloped shoulder, then the neck.
        let body = SCNNode(geometry: SCNCylinder(radius: 0.22, height: 0.6))
        body.geometry?.materials = [plastic]
        body.position = SCNVector3(0, 0.3, 0)
        model.addChildNode(body)
        let shoulder = SCNNode(geometry: SCNCone(topRadius: 0.09, bottomRadius: 0.22, height: 0.18))
        shoulder.geometry?.materials = [plastic]
        shoulder.position = SCNVector3(0, 0.69, 0)
        model.addChildNode(shoulder)
        // A pale band for the label, so it reads as a bottle, not a pickle.
        let band = SCNNode(geometry: SCNCylinder(radius: 0.225, height: 0.24))
        band.geometry?.materials = [label]
        band.position = SCNVector3(0, 0.3, 0)
        model.addChildNode(band)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.1, height: 0.12))
        neck.geometry?.materials = [white]
        neck.position = SCNVector3(0, 0.84, 0)
        model.addChildNode(neck)
        // The trigger head, nozzle forward (toward -z, at her).
        let head = SCNNode(geometry: SCNBox(width: 0.16, height: 0.18, length: 0.44, chamferRadius: 0.06))
        head.geometry?.materials = [white]
        head.position = SCNVector3(0, 0.98, -0.1)
        model.addChildNode(head)
        let nozzle = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.1))
        nozzle.geometry?.materials = [dark]
        nozzle.eulerAngles.x = .pi / 2
        nozzle.position = SCNVector3(0, 0.99, -0.35)
        model.addChildNode(nozzle)
        let trigger = SCNNode(geometry: SCNBox(width: 0.07, height: 0.24, length: 0.07, chamferRadius: 0.03))
        trigger.geometry?.materials = [dark]
        trigger.eulerAngles.x = -0.35
        trigger.position = SCNVector3(0, 0.82, -0.24)
        model.addChildNode(trigger)
        model.scale = SCNVector3(0.95, 0.95, 0.95)
        model.name = "model"
        applyLook(to: model)
        bottle.addChildNode(model)

        let shadow = shadowNode(width: 0.8, length: 0.8)
        shadow.position.z = 0
        bottle.addChildNode(shadow)
        bottle.isHidden = true
        bottle.position = SCNVector3(0, 0, bottleZ)
        scene.rootNode.addChildNode(bottle)
    }

    /// A glancing hit. The cart wobbles and the bottle comes after her. A second
    /// one while it's still chasing and she's caught.
    private func stumble(bounceBack: Bool) {
        guard stumbleGrace <= 0 else { return }
        testLog("stumble")
        stumbleGrace = 0.4
        if bounceBack {
            lane = bodyLane
        }
        if chaseTimer > 0 {
            caught()
            return
        }
        chaseTimer = chaseTime
        tilt = Bool.random() ? 0.32 : -0.32
        landSquash = 1
        haptic(.heavy)
        puff(at: SCNVector3(visualX, height + 0.2, 0.2), count: 14, color: UIColor(white: 0.95, alpha: 0.9))
        shakeCamera()
    }

    /// Second stumble: the bottle catches up and sprays her. It's a crash.
    private func caught() {
        if e2eGod {
            chaseTimer = chaseTime
            return
        }
        sprayed = true
        crash()
        // A burst of mist over her head.
        puff(at: SCNVector3(visualX, height + 1.5, 0.3), count: 40,
             color: UIColor(red: 0.78, green: 0.92, blue: 1.0, alpha: 0.95))
    }

    /// Hops the bottle along behind her while it chases, drops it back when it
    /// gives up, and leans it over her if it caught her.
    private func updateChase(dt: Float) {
        chaseTimer = max(0, chaseTimer - dt)
        stumbleGrace = max(0, stumbleGrace - dt)
        bottleClock += dt
        let chasing = chaseTimer > 0 || sprayed
        // In from behind the camera fast, back out a little slower.
        let goal: Float = sprayed ? 1.0 : chasing ? bottleChaseZ : 9
        bottleZ += (goal - bottleZ) * min(1, (chasing ? 6 : 2.5) * dt)
        // A little off to one side, so the La Croix logo still shows.
        let goalX = visualX + (sprayed ? 0.9 : 0.75)
        bottleX += (goalX - bottleX) * min(1, 7 * dt)
        bottle.isHidden = bottleZ > bottleGone
        guard !bottle.isHidden else { return }
        let hop = sprayed ? 0.25 : abs(sin(bottleClock * 9)) * 0.32
        bottle.position = SCNVector3(bottleX, hop, bottleZ)
        // Leans over her when it catches her, nozzle down at her head.
        bottle.eulerAngles.z = sprayed ? 0.45 : 0
        let model = bottle.childNode(withName: "model", recursively: false)
        // Turned side-on, nozzle aimed in at her from her right, rocking as it hops.
        model?.eulerAngles = SCNVector3(sprayed ? 0 : -0.12 + sin(bottleClock * 9) * 0.08, 1.0,
                                        sprayed ? 0 : sin(bottleClock * 4.5) * 0.1)
    }

    // MARK: - Contacts

    /// The lane her body is really in. A swipe changes `lane` at once, but the cart
    /// takes a moment to slide over, and until it crosses the line between lanes
    /// she's still in the old one.
    private var bodyLane: Int {
        max(0, min(2, Int((visualX / laneSpacing).rounded()) + 1))
    }

    /// Is this coyote or low thing on the same stretch of road as her cart?
    private func touchesCat(_ item: TrackItem) -> Bool {
        item.z >= -catReach && item.back <= catReach
    }

    // Crash or stumble: running into something in the lane she's in and heading for
    // is a crash. Clipping something mid-slide, in the lane she's leaving or the one
    // she hasn't reached yet, is a glancing hit: a stumble. Clipping the lane ahead
    // bounces her back to where she came from.
    private func resolveContacts(dz: Float) {
        for item in items {
            let prevZ = item.z - dz
            if item.kind == .tree {
                handleTree(item, prevZ: prevZ)
                if state != .running { return }
                continue
            }
            if item.kind == .food {
                guard item.lane == lane, prevZ < 0, item.z >= 0 else { continue }
                // Food in the air is only reached high in a jump (or from a tree roof).
                if item.high && height < airFoodReach { continue }
                collect(item)
                continue
            }
            let heading = item.lane == lane
            let inside = item.lane == bodyLane
            guard heading || inside, !item.hit, touchesCat(item) else { continue }
            // A coyote is cleared by being high enough, a low thing by ducking.
            // The whole time it's beside her, not just the moment it arrives.
            if item.kind == .coyote && isHighEnough { continue }
            if item.kind == .low && isDucked {
                if heading { passedUnder() }
                continue
            }
            if heading && inside {
                if !e2eGod {
                    crash()
                    return
                }
                item.hit = true
            } else {
                item.hit = true
                stumble(bounceBack: heading)
                if state != .running { return }
            }
        }
    }

    private func handleTree(_ item: TrackItem, prevZ: Float) {
        let heading = item.lane == lane
        let inside = item.lane == bodyLane
        guard heading || inside else { return }
        let entered = prevZ < 0 && item.z >= 0
        guard entered || overlapsCat(item) else { return }
        if item === platform { return }
        // High enough for this tree (its own roof, or its ramp where she meets
        // it): get on. Rolling into a ramp's foot counts, so she just drives up.
        if canReach(item) {
            if heading { mountTree(item) }
            return
        }
        // Too low for it: a short tree's front from the road, or a tall tree's
        // front from the road or a short roof, is a wall.
        guard entered, !item.hit else { return }
        if heading && inside {
            if !e2eGod { crash() }
        } else {
            // The front of a tree caught the corner of the cart mid-slide.
            item.hit = true
            stumble(bounceBack: heading)
        }
    }

    private func mountTree(_ tree: TrackItem) {
        guard platform !== tree else { return }
        // She keeps her jump arc and comes down on the roof. The landing puff
        // and haptic come from updateJump when she touches it. From a higher
        // roof she just drops onto this one.
        platform = tree
    }

    private func collect(_ item: TrackItem) {
        food += 1
        let spot = SCNVector3(laneX(item.lane), item.node.position.y + 0.6, 0.2)
        recycle(item)
        items.removeAll { $0 === item }
        haptic(.light)
        puff(at: spot, count: 12, color: UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1))
    }

    private func crash() {
        if e2ePilot {
            print("CATCART crash t=\(timeAlive) speed=\(runSpeed()) wave=\(lastWave) meters=\(Int(meters))")
            fflush(stdout)
        }
        state = .dead
        deadClock = 0
        restartArmed = false
        // Drop any swipe or tap still waiting for a frame: it was meant for the run.
        inputLock.lock()
        pending.removeAll()
        inputLock.unlock()
        jumping = false
        platform = nil
        duckTimer = 0
        chaseTimer = 0
        hideDuckHint()
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
        let newBest = score > bestScore
        if newBest {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: Self.bestKey)
        }
        // Real time survived, without the CATCART_TIME test head start.
        let seconds = Int(timeAlive - e2eStartTime)
        hud.showDead(score: score, food: food, seconds: seconds, best: bestScore, newBest: newBest)
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

    /// Builds the puff emitters once. Each one runs all the time at a birth rate
    /// of 0, and a puff turns it up for a twentieth of a second.
    private func buildPuffs() {
        for _ in 0..<4 {
            let ps = SCNParticleSystem()
            ps.particleImage = puffImage
            ps.birthRate = 0
            ps.particleLifeSpan = 0.4
            ps.particleSize = 0.2
            ps.particleSizeVariation = 0.08
            ps.particleVelocity = 2.6
            ps.particleVelocityVariation = 1
            ps.emittingDirection = SCNVector3(0, 1, 0.3)
            ps.spreadingAngle = 75
            ps.acceleration = SCNVector3(0, -3, 3)
            ps.blendMode = .alpha
            ps.propertyControllers = [.opacity: Self.fadeOutController()]
            let holder = SCNNode()
            holder.addParticleSystem(ps)
            scene.rootNode.addChildNode(holder)
            puffs.append(Puff(node: holder, system: ps))
        }
    }

    /// Fires the next puff emitter in turn. Four is plenty: a puff lasts under half
    /// a second, and at most a landing and a can or two happen that close together.
    private func puff(at point: SCNVector3, count: Int, color: UIColor) {
        guard !puffs.isEmpty else { return }
        let p = puffs[nextPuff]
        nextPuff = (nextPuff + 1) % puffs.count
        p.node.position = point
        p.system.particleColor = color
        p.system.birthRate = CGFloat(count) * 20
        p.left = 0.05
    }

    /// Turns each puff back off once its twentieth of a second is up.
    private func updatePuffs(dt: Float) {
        for p in puffs where p.left > 0 {
            p.left -= dt
            if p.left <= 0 { p.system.birthRate = 0 }
        }
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
        if swipeStart != nil && !swipeConsumed {
            enqueue(.lift)
        }
        swipeStart = nil
    }

    /// The system took the touch away (a call, a system gesture). Not a lift.
    func touchCancelled() {
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
            if state == .running { testLog("\(intent)") }
            switch (state, intent) {
            case (.ready, .tap):
                startRun()
            case (.dead, .tap):
                // Only a touch that starts after the pause can restart, and only
                // once it lifts without swiping.
                restartArmed = deadClock >= deathPause
            case (.dead, .lift):
                if restartArmed {
                    resetRun()
                    startRun()
                }
            case (.dead, .left), (.dead, .right), (.dead, .up), (.dead, .down):
                // A swipe on the panel never restarts.
                restartArmed = false
            case (.running, .left):
                moveLane(-1)
            case (.running, .right):
                moveLane(1)
            case (.running, .up):
                if !jump() { jumpBuffer = jumpBufferTime }
            case (.running, .stumble):
                stumble(bounceBack: false)
            case (.running, .down):
                jumpBuffer = 0
                // On the ground it's a duck. In the air it only brings her down.
                if !jumping && height - floorY < 0.05 {
                    startDuck()
                } else {
                    slamDown()
                }
            default:
                break
            }
        }
    }

    private func moveLane(_ delta: Int) {
        let next = max(0, min(2, lane + delta))
        guard next != lane else { return }
        // The tree beside her in that lane, if any. Its top where she is: a roof,
        // or partway up a ramp.
        let beside = items.filter { $0.kind == .tree && $0.lane == next && overlapsCat($0) }
            .max { $0.topAtCat < $1.topAtCat }
        if let tree = beside, !canReach(tree) {
            // Bumped the side of a cat tree that's higher than she can get onto
            // from here (from the road, a short roof next to a tall one, or a ramp
            // above its low end): bounce back, stay in lane, and stumble.
            tilt = delta > 0 ? 0.12 : -0.12
            visualX += Float(delta) * 0.35
            haptic(.rigid)
            stumble(bounceBack: false)
            return
        }
        // Onto the tree next door (dropping down to it if it's lower), or off
        // into an empty lane, where she falls to the road.
        platform = beside
        lane = next
        tilt = delta > 0 ? -0.2 : 0.2
        DispatchQueue.main.async {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Returns false if she can't jump yet (still in the air).
    @discardableResult
    private func jump() -> Bool {
        guard !jumping, height - floorY < 0.1 else { return false }
        // Jumping pops her straight out of a duck.
        duckTimer = 0
        jumping = true
        vy = jumpSpeed
        haptic(.light)
        return true
    }

    private func slamDown() {
        guard jumping || height - floorY > 0.05 else { return }
        // About 1.7 times takeoff speed (was 16 with the 1.9 m jump, scaled to
        // 22 for the 2.6 m one), so a slam from the top takes as long as before.
        vy = min(vy, -22)
    }

    private func startDuck() {
        if duckTimer <= 0 { haptic(.soft) }
        duckTimer = duckTime
    }

    /// Ducked under a low thing. The first time ever, the hint retires.
    private func passedUnder() {
        guard duckHintNeeded else { return }
        duckHintNeeded = false
        UserDefaults.standard.set(true, forKey: Self.duckedKey)
        hideDuckHint()
    }

    /// Until she has ducked under one, a low thing coming up shows a one-line hint.
    private func updateDuckHint() {
        guard duckHintNeeded else { return }
        // About two seconds out: long enough to read, short enough to tie to the thing.
        // Not for a blocked lane (a coyote under it): ducking there is a crash.
        let coming = items.contains { low in
            low.kind == .low && low.z > -runSpeed() * 2.2 && low.z < 0.5
                && !items.contains { $0.kind == .coyote && $0.lane == low.lane && abs($0.z - low.z) < 0.5 }
        }
        if coming && !duckHintShown {
            duckHintShown = true
            hud.showHint("Swipe down to duck!")
        } else if !coming && duckHintShown {
            hideDuckHint()
        }
    }

    private func hideDuckHint() {
        guard duckHintShown else { return }
        duckHintShown = false
        hud.hideHint()
    }

    /// Test-only autopilot (CATCART_PILOT=1): jumps coyotes and hops onto trees,
    /// so screenshot runs show the real moves.
    private func pilot() {
        guard e2ePilot, state == .running else { return }
        for item in items where item.lane == lane && item.z < 0 && item.z > -9 {
            if item.kind == .coyote && !isHighEnough && !jumping {
                jump()
            } else if item.kind == .tree && item.rampLength == 0 && !jumping && item.z > -6
                        && item.roof > floorY + 0.1 && item.roof - floorY < jumpPeak {
                // Jump up onto a tree that's higher than where she is and within
                // a jump of it. A ramp she just rolls up. A tall tree from the
                // road is out of reach, so there's no point jumping at it.
                jump()
            } else if item.kind == .low && !isDucked && item.z > -6 {
                // The same swipe down a finger makes. In the air it drops her,
                // and the next frame on the ground it ducks.
                enqueue(.down)
            }
        }
    }

    // MARK: - States

    private func startRun() {
        hud.hidePanel()
        hud.hideHome()
        state = .running
        timeAlive = e2eStartTime
        lastWave = -1
        // Fill the road ahead now, so there's something to do right away.
        var next = firstWaveAhead
        while next < spawnAhead {
            next += spawnWave(at: next)
        }
        untilWave = next - spawnAhead
    }

    private func resetRun() {
        items.forEach { recycle($0) }
        items.removeAll()
        hud.clearLines()
        catNode.removeAction(forKey: "tip")
        lane = 1
        jumping = false
        height = 0
        vy = 0
        wasAirborne = false
        platform = nil
        pitch = 0
        tilt = 0
        cameraLift = 0
        landSquash = 0
        jumpBuffer = 0
        duckTimer = 0
        chaseTimer = 0
        stumbleGrace = 0
        sprayed = false
        bottleZ = 9
        bottle.isHidden = true
        timeAlive = 0
        meters = 0
        food = 0
        placePlayer()
        resetTrack()
        hud.setScore(0)
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

/// Test-only frame timer. Every 5 seconds it prints the average and worst frame.
/// Any frame over 25 ms (a visible stutter at 60 fps) is printed on its own, with
/// whatever was built or spawned during the frame before it, since that frame's
/// work is what made it late.
private struct FrameLog {
    let enabled: Bool
    private var last: TimeInterval = 0
    private var windowStart: TimeInterval = 0
    private var frames = 0
    private var total: Double = 0
    private var worst: Double = 0
    private var hitches = 0
    private var events: [String] = []

    init(enabled: Bool) {
        self.enabled = enabled
    }

    mutating func note(_ event: String) {
        guard enabled else { return }
        events.append(event)
    }

    mutating func frame(at time: TimeInterval, runTime: Float) {
        guard enabled else { return }
        defer {
            last = time
            events.removeAll()
        }
        guard last > 0 else {
            windowStart = time
            return
        }
        let ms = (time - last) * 1000
        frames += 1
        total += ms
        worst = max(worst, ms)
        if ms > 25 {
            hitches += 1
            let cause = events.isEmpty ? "" : " after " + events.joined(separator: ", ")
            emit(String(format: "CATCART hitch %.0f ms at run %.1f s", ms, runTime) + cause)
        }
        if time - windowStart >= 5 {
            emit(String(format: "CATCART frames avg %.1f ms worst %.0f ms hitches %d at run %.1f s",
                        total / Double(max(frames, 1)), worst, hitches, runTime))
            windowStart = time
            frames = 0
            total = 0
            worst = 0
            hitches = 0
        }
    }

    /// Flushed right away, so lines survive the app being killed at the end of a test.
    private func emit(_ line: String) {
        print(line)
        fflush(stdout)
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

    /// Orange and white construction stripes, slanted.
    static func drawStripes() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
            UIColor(red: 1.0, green: 0.42, blue: 0.1, alpha: 1).setFill()
            for i in stride(from: -64, to: 192, by: 64) {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: i, y: 64))
                path.addLine(to: CGPoint(x: i + 32, y: 64))
                path.addLine(to: CGPoint(x: i + 64, y: 0))
                path.addLine(to: CGPoint(x: i + 32, y: 0))
                path.close()
                path.fill()
            }
        }
    }

    /// Red and white tablecloth checks.
    static func drawGingham() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor(red: 0.88, green: 0.22, blue: 0.25, alpha: 0.55).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
    }

    /// A pale blue sheet with soft stripes, darker toward its hem.
    static func drawSheet() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            UIColor(red: 0.78, green: 0.89, blue: 0.98, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            UIColor(red: 0.55, green: 0.74, blue: 0.93, alpha: 1).setFill()
            for x in stride(from: 8, to: 128, by: 32) {
                ctx.fill(CGRect(x: x, y: 0, width: 10, height: 128))
            }
            UIColor(red: 0.30, green: 0.50, blue: 0.80, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 112, width: 128, height: 16))
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
