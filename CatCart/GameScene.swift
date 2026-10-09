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

/// The cat power-ups. Each one is a pickup on the road, like a can of food:
/// roll into it and it works for a while. The rules are in docs/prd.md under
/// "Power-ups"; docs/plans/power-ups.md says why they work this way.
enum PowerUp: CaseIterable {
    /// Fizz Rocket: the La Croix cans in her box fizz like rockets and she
    /// flies over everything, steering through a trail of food in the sky.
    case rocket
    /// Can Magnet: food from every lane flies to her.
    case magnet
    /// Pounce Springs: springs under the wheels and much higher jumps, high
    /// enough to land on a tall cat tree from the road.
    case pounce
    /// Nine Lives: a halo that saves her from one crash.
    case lives

    var title: String {
        switch self {
        case .rocket: return "Fizz Rocket!"
        case .magnet: return "Can Magnet!"
        case .pounce: return "Pounce Springs!"
        case .lives: return "Nine Lives!"
        }
    }

    /// The picture on its HUD timer.
    var icon: String {
        switch self {
        case .rocket: return "🚀"
        case .magnet: return "🧲"
        case .pounce: return "🐾"
        case .lives: return "😇"
        }
    }

    /// How long it lasts. Nine Lives also ends when it saves her, and the
    /// rocket waits for a clear road before it lands her.
    var seconds: Float {
        switch self {
        case .rocket: return 5
        case .magnet: return 10
        case .pounce: return 10
        case .lives: return 20
        }
    }

    /// Test-only: names for CATCART_SWIPES ("4:rocket") and CATCART_POWER.
    init?(testName: String) {
        switch testName {
        case "rocket": self = .rocket
        case "magnet": self = .magnet
        case "pounce": self = .pounce
        case "lives": self = .lives
        default: return nil
        }
    }
}

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
        /// A power-up pickup. Placed and collected like food.
        case power
    }

    private enum Intent {
        case tap, left, right, up, down
        /// A finger lifted without swiping, where it lifted (view points). On the
        /// home screen this starts a run or works the picker; on the death panel
        /// it restarts.
        case lift(CGPoint)
        /// Test-only: a stumble from CATCART_SWIPES, to see the bottle without aiming for a bump.
        case stumble
        /// Test-only: a power-up from CATCART_SWIPES ("4:rocket"), as if she rolled into one.
        case power(PowerUp)
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
        /// Which power-up a `.power` pickup is.
        var power: PowerUp?
        /// Food in the Fizz Rocket's trail, up at flying height.
        var sky = false
        /// Food the Can Magnet has caught: it flies to her instead of riding its lane.
        var pulled = false
        /// Height the pickup was placed at, for the magnet to pull it from.
        var baseY: Float = 0
        /// A coyote's head turn toward her. It fades out as the coyote reaches
        /// her, so the head doesn't swing round when she jumps right over it.
        var gaze: SCNLookAtConstraint?
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
    /// from 8 s, hard (2) from 20 s.
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
    /// Two seconds at the 24 m/s start speed (it was 40 m at 17).
    private let firstWaveAhead: Float = 48
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
    private let normalPeak: Float = 2.6
    /// Pounce Springs jump this high, over a tall tree's roof (3.5 m), and stay
    /// in the air a little longer.
    private let pouncePeak: Float = 4.4
    private let pounceAirtime: Float = 1.18
    private var pouncing: Bool { powerLeft[.pounce] != nil }
    private var jumpPeak: Float { pouncing ? pouncePeak : normalPeak }
    /// A jump is a real arc: up at jumpSpeed, pulled down by gravity. It always peaks
    /// at 2.6 m (Rex, 2026-10-05, was 1.9: "I just want the animation higher").
    /// Takeoff to landing is 0.68 s at the start and quickens to about 0.59 s at full
    /// ramp (75 s) (Rex, 2026-10-05: "increase the gravity, drop faster, start
    /// faster"; was 0.9 to 0.78 s, so gravity is about 1.75x and takeoff 1.3x).
    /// It stays there while speed keeps creeping up after that.
    private var jumpAirtime: Float { (0.68 - 0.09 * ramp) * (pouncing ? pounceAirtime : 1) }
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
    /// The top of the tallest low thing. A jump that carries her above this goes
    /// over it (Rex, 2026-10-05); the pieces are built to stay under it.
    private let lowTop: Float = 2.0
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

    // Power-ups (see PowerUp at the top of the file).
    /// The first power-up shows up in a mix this far into a run, then one every
    /// 14 to 20 s, like Subway Surfers: often enough to look forward to.
    private let firstPower: Float = 9
    /// Fizz Rocket flying height: over a tall tree's roof (3.5 m) with room to
    /// spare, low enough that the camera stays under the ceiling beams.
    private let flightHeight: Float = 4.8
    /// The rocket's trail of food: one can every this many meters, out to this
    /// far (about 28 cans, so the trail never needs more than the food pool holds).
    private let skyFoodGap: Float = 4.5
    private let skyTrailLength: Float = 140
    /// It lands her only once nothing stands on the road this close ahead.
    private let landingClear: Float = 30
    /// After landing from the rocket, or being saved by Nine Lives, nothing can
    /// crash her for this long.
    private let graceTime: Float = 1.2
    /// The Can Magnet pulls food this far ahead, from every lane.
    private let magnetRange: Float = 26

    // Run camera, framed like Subway Surfers: high and looking down, so she sits
    // low on screen and the road runs up past her to the crest. It sits this high
    // over the floor she rides (road or roof) and this far behind her, tilted down
    // at the road `cameraAim` meters ahead of her. See docs/plans/camera.md.
    // On the road she sits where the old flat camera had her, about two thirds
    // down, but the crest is higher on screen and stays above her in a jump.
    private var cameraHeight: Float = 4.0
    private var cameraBack: Float = 4.4
    private var cameraAim: Float = 12
    /// The share of a jump the camera rises with. Enough that she stays under the
    /// crest at the top of a jump, not so much that the world bobs.
    private var cameraJumpFollow: Float = 0.6
    private var cameraPitch: Float { -atan(cameraHeight / (cameraBack + cameraAim)) }
    /// The sky pictures stay at the angle the old flat camera held them, so their
    /// painted horizon still meets the fog.
    private let skyPitch: Float = -0.055
    private let skyPivot = SCNNode()
    private var baseFOV: CGFloat = 50
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

    /// Running speed at the start of a run and once the ramp is full (75 s), in
    /// meters per second. Rex, 2026-10-09: "start a lot faster" (it was 17).
    private let startSpeed: Float = 24
    private let fullSpeed: Float = 34

    /// Running speed in meters per second. 24 at the start, 34 at full ramp
    /// (about 26 at 8 s, 30 at 30 s, 32 at 45 s). Past 75 s it keeps creeping up
    /// 1 m/s every 30 s, to 38 at about 3:15, so a long run still gets harder.
    /// Only speed creeps: the jump, clear height, and gaps read `ramp` and stay at
    /// their full-ramp values.
    private func runSpeed() -> Float {
        let overtime = min(4, max(0, timeAlive - rampSeconds) / 30)
        return startSpeed + (fullSpeed - startSpeed) * ramp + overtime
    }

    /// Distances inside an obstacle mix are written for 17 m/s (the old start
    /// speed). They stretch with speed, but less than speed does (the square
    /// root), so the faster she goes, the less time there is between things: 19 m
    /// between two coyotes is 0.94 s at the start (24 m/s), about 0.8 s at 34 m/s,
    /// and 0.75 s at 38. That squeeze is most of what makes a long run hard.
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

    // The power-up bubble's skin. `rim` is 0 where the surface faces the camera
    // and 1 at its edge; the edge gets brighter and takes on a slow rainbow.
    private static let bubbleModifier = """
    #pragma body
    float rim = 1.0 - saturate(dot(normalize(_surface.view), normalize(_surface.normal)));
    float f = pow(rim, 2.5);
    float3 rainbow = 0.5 + 0.5 * cos(6.2831 * (rim * 1.2 + scn_frame.time * 0.15) + float3(0.0, 2.1, 4.2));
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, mix(float3(1.0), rainbow, 0.55), f);
    _surface.transparent.a = saturate(_surface.transparent.a + f * 0.7);
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

    /// A flat ring that spreads on the floor where she lands and slides back
    /// with the road. Three are built up front and reused in turn.
    private final class Ring {
        let node: SCNNode
        var left: Float = 0
        var strength: Float = 1

        init(node: SCNNode) {
            self.node = node
        }
    }

    private var rings: [Ring] = []
    private var nextRing = 0
    private let ringTime: Float = 0.38

    /// A power-up she just grabbed. It hops, spins, and shrinks into her
    /// lap for a moment before its node goes back to the pool (see flyAway).
    private final class Collected {
        let node: SCNNode
        var left: Float

        init(node: SCNNode, left: Float) {
            self.node = node
            self.left = left
        }
    }

    private var collected: [Collected] = []
    private let collectTime: Float = 0.26

    /// Cartoon stars that circle over her head after a crash. Built with the
    /// player, hidden until then.
    private let starsNode = SCNNode()
    private var starsAngle: Float = 0
    private var starsClock: Float = 0

    /// Camera feel: a short field-of-view kick on a jump or landing, and a
    /// shake that dies out (a crash, a stumble, a hard landing).
    private var fovKick: Float = 0
    private var shakeLeft: Float = 0
    private var shakeTotal: Float = 1
    private var shakeAmp: Float = 0
    private var shakeClock: Float = 0
    /// How fast she was falling when she touched down, for the landing's weight.
    private var landVy: Float = 0
    private var landSquashAmp: Float = 0.12

    /// Mist from the spray bottle's nozzle: little "psst"s as it hops, a long
    /// one when it catches her.
    private var mist: SCNParticleSystem?
    private var mistLeft: Float = 0
    private var lastHop: Float = 0
    /// Which world the wheel dust is tinted for.
    private var dustWorld: WorldKind?

    // MARK: - Game state

    private var state: State = .ready
    private var lane = 1
    private var visualX: Float = 0
    private var tilt: Float = 0
    private var jumping = false
    private var height: Float = 0
    private var vy: Float = 0
    private var wasAirborne = false
    /// How fast she was falling just before this frame's gravity step, so a
    /// landing knows how hard it hit (fall() zeroes vy when she touches down).
    private var impactSpeed: Float = 0
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

    /// Seconds left on each power-up she has, and how long each one started
    /// with (the rocket's depends on the road), for its timer badge.
    private var powerLeft: [PowerUp: Float] = [:]
    private var powerTotal: [PowerUp: Float] = [:]
    /// Seconds of run until a mix may carry the next power-up.
    private var untilPower: Float = 0
    private var lastPower: PowerUp?
    /// True while the Fizz Rocket holds her up at flying height.
    private var flying = false
    /// Seconds nothing can crash her (after a rocket landing or a saved life).
    private var graceLeft: Float = 0
    /// How long the rocket has flown on past its time, waiting for a clear road.
    private var rocketOvertime: Float = 0
    /// Last power-up state sent to the HUD, so it's only sent when it changes.
    private var powerShown = ""

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
    /// Where the finger is now, so a lift knows where it happened.
    private var swipeLast: CGPoint?
    private var swipeConsumed = false

    private let e2eAutoRun = ProcessInfo.processInfo.environment["CATCART_AUTO_RUN"] == "1"
    private let e2eGod = ProcessInfo.processInfo.environment["CATCART_GOD"] == "1"
    private let e2ePilot = ProcessInfo.processInfo.environment["CATCART_PILOT"] == "1"
    /// Test-only: CATCART_TIME=120 starts each run that many seconds into the difficulty ramp.
    private let e2eStartTime = Float(ProcessInfo.processInfo.environment["CATCART_TIME"] ?? "") ?? 0
    /// Test-only: CATCART_WAVE=29 plays only that obstacle mix (its index in `waves`).
    private let e2eWave = Int(ProcessInfo.processInfo.environment["CATCART_WAVE"] ?? "")
    /// Test-only: CATCART_MIRROR=0 or 1 and CATCART_ROT=0...2 fix how a mix is
    /// flipped and turned, so a CATCART_SWIPES line knows which lane is which.
    private let e2eMirror = ProcessInfo.processInfo.environment["CATCART_MIRROR"].map { $0 == "1" }
    private let e2eRot = Int(ProcessInfo.processInfo.environment["CATCART_ROT"] ?? "")
    /// Test-only: with CATCART_SWIPES set, every move and stumble prints a line with
    /// the run time, meters run, her lane and height, and the top of what she's
    /// riding, so a scripted run can be read without guessing from screenshots.
    /// It also prints each mix as it's placed (where each thing reaches her, in
    /// meters run), each time she gets on a tree or back on the road, and a crash.
    private let e2eSwipes = ProcessInfo.processInfo.environment["CATCART_SWIPES"] != nil
    private var loggedPlatform: ObjectIdentifier?
    /// Test-only: set by a CATCART_SWIPES "freeze". The game stops updating but keeps drawing.
    private var testFrozen = false

    private func testLog(_ what: String) {
        guard e2eSwipes else { return }
        print(String(format: "CATCART %@ at run %.2f s meters %.1f lane %d height %.2f floor %.2f",
                     what, timeAlive, meters, lane, height, floorY))
        fflush(stdout)
    }
    /// Test-only: CATCART_POWER=rocket makes every power-up that one, and
    /// CATCART_POWEREVERY=5 puts one in a mix every 5 s (the first at 5 s).
    private let e2ePower = PowerUp(testName: ProcessInfo.processInfo.environment["CATCART_POWER"] ?? "")
    private let e2ePowerEvery = Float(ProcessInfo.processInfo.environment["CATCART_POWEREVERY"] ?? "")
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

        // Test-only: CATCART_CAM="4,4.4,12,0.6,50" sets the run camera's height,
        // distance back, aim, jump follow, and field of view, to compare framings
        // without a rebuild.
        if let cam = ProcessInfo.processInfo.environment["CATCART_CAM"]?
            .split(separator: ",").compactMap({ Float($0) }), cam.count == 5 {
            (cameraHeight, cameraBack, cameraAim, cameraJumpFollow) = (cam[0], cam[1], cam[2], cam[3])
            baseFOV = CGFloat(cam[4])
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
        let pills = PillBar()
        view.addSubview(pills)
        hud.pills = pills
        let powers = PowerBar()
        view.addSubview(powers)
        hud.powerBar = powers
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor(look(currentPlayerWorld()).fog)
        view.isMultipleTouchEnabled = false
        prepareForRun(in: view)

        hud.showHome(best: bestScore, cat: cart.cat, cart: cart.cart)
        // Test-only: CATCART_MENU=1 opens the home menu, for a screenshot.
        if ProcessInfo.processInfo.environment["CATCART_MENU"] == "1" {
            hud.setMenuOpen(true)
        }
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
    /// for a touch that's still down when she crashes. "3:freeze" stops the game on
    /// that frame for 3 s, so a screenshot catches an exact moment. "4:rocket",
    /// "4:magnet", "4:pounce", and "4:lives" give her that power-up.
    private func scheduleTestSwipes() {
        guard let script = ProcessInfo.processInfo.environment["CATCART_SWIPES"] else { return }
        for step in script.split(separator: ",") {
            let parts = step.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[0]) else { continue }
            let touches: [String: (GameScene) -> Void] = [
                "freeze": { game in
                    game.testFrozen = true
                    game.testLog("freeze")
                    // CATCART_FREEZE=8 holds it longer, for a slow simulator.
                    let hold = Double(ProcessInfo.processInfo.environment["CATCART_FREEZE"] ?? "") ?? 3
                    DispatchQueue.main.asyncAfter(deadline: .now() + hold) { game.testFrozen = false }
                },
                "stumble": { game in game.enqueue(.stumble) },
                "tap": { game in game.touchBegan(at: CGPoint(x: 200, y: 500)); game.touchEnded() },
                "press": { game in game.touchBegan(at: CGPoint(x: 200, y: 500)) },
                "release": { game in game.touchEnded() }
            ]
            if let power = PowerUp(testName: String(parts[1])) {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    self?.enqueue(.power(power))
                }
                continue
            }
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
        // A little post-processing for the punchy Subway Surfers look: a soft bloom
        // on the brightest spots, slightly richer color, and a faint vignette.
        // HDR rendering adds a pass or two on the phone. Set `effects` false if a
        // run makes the phone warm or CATCART_PERF=1 shows longer frames.
        // CATCART_FLAT=1 turns them off, to measure what they cost on the phone.
        let effects = ProcessInfo.processInfo.environment["CATCART_FLAT"] == nil
        if effects {
            camera.wantsHDR = true
            // No auto-exposure: the picture must not brighten and dim as scenery passes.
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = 0
            camera.bloomIntensity = 0.3
            camera.bloomThreshold = 0.85
            camera.bloomBlurRadius = 8
            camera.saturation = 1.1
            camera.contrast = 0.04
            camera.vignettingIntensity = 0.28
            camera.vignettingPower = 1.2
        }
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, cameraHeight, cameraBack)
        cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // The sky is two big pictures hung far in front of the camera. B fades in
        // over A as you drive toward the next world.
        cameraNode.addChildNode(skyPivot)
        for (node, order) in [(skyA, -100), (skyB, -99)] {
            let plane = SCNPlane(width: 1, height: 1)
            plane.materials = [skyMaterials[worldAt(startWorld)]!]
            node.geometry = plane
            node.renderingOrder = order
            node.position = SCNVector3(0, 0, -200)
            skyPivot.addChildNode(node)
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

        // The kitten in her La Croix cart, or the pair picked on the home screen.
        // Test-only: CATCART_CAT=bean and CATCART_CART=wagon pick them for a
        // screenshot without saving.
        let env = ProcessInfo.processInfo.environment
        cart = KittenCart(cat: env["CATCART_CAT"].flatMap(CatChoice.init) ?? Choices.cat,
                          cart: env["CATCART_CART"].flatMap(CartChoice.init) ?? Choices.cart)
        catNode = cart.node
        lookAfterPlayer()
        playerRoot.addChildNode(catNode)

        let aim = SCNNode()
        aim.simdPosition = homeEye
        aim.simdLook(at: homeTarget, up: [0, 1, 0], localFront: [0, 0, -1])
        homeRotation = aim.simdOrientation

        // Dust kicked up by the wheels. Particles live in the world, not on the cart,
        // and drift toward the camera, so they trail behind her.
        // Soft and a touch bigger than before, tinted to the ground of each world
        // (see dustColor): gray grit in the city, warm straw dust on the farm.
        dust = SCNParticleSystem()
        dust.particleImage = puffImage
        dust.birthRate = 22
        dust.particleLifeSpan = 0.5
        dust.particleLifeSpanVariation = 0.15
        dust.particleSize = 0.15
        dust.particleSizeVariation = 0.06
        dust.particleColor = dustColor(.city)
        dust.emittingDirection = SCNVector3(0, 0.4, 1)
        dust.spreadingAngle = 28
        dust.particleVelocity = 4.2
        dust.particleVelocityVariation = 1.5
        dust.particleAngularVelocity = 60
        dust.particleAngularVelocityVariation = 60
        dust.emitterShape = SCNBox(width: 1.1, height: 0.02, length: 0.1, chamferRadius: 0)
        dust.blendMode = .alpha
        dust.isLocal = false
        dust.propertyControllers = [.opacity: Self.fadeOutController()]
        dustNode.position = SCNVector3(0, 0.08, 0.35)
        dustNode.addParticleSystem(dust)
        playerRoot.addChildNode(dustNode)

        buildStars()
        placePlayer()
    }

    /// Lights, shadows, and the world's look (bend and fog) on everything in the
    /// cart. Run again after the picker swaps the cat or the cart.
    private func lookAfterPlayer() {
        catNode.enumerateHierarchy { node, _ in
            node.categoryBitMask |= Self.playerLightBit
            // Her fur shells stay out of the shadow map: the skin under them
            // already casts her shadow, and eight more copies would only cost.
            node.castsShadow = node.name != "fur"
        }
        applyLook(to: catNode)
    }

    /// The home screen's picker: swap the cat or the cart, save it, and show it.
    private func pick(_ choice: Hud.HomeTap) {
        switch choice {
        case .cat(let step):
            let next = cart.cat.cycled(step)
            cart.setCat(next)
            Choices.cat = next
        case .cart(let step):
            let next = cart.cart.cycled(step)
            cart.setCart(next)
            Choices.cart = next
        default:
            return
        }
        lookAfterPlayer()
        hud.setPicks(cat: cart.cat, cart: cart.cart)
        tick()
    }

    /// A light tick for picker and switch taps.
    private func tick() {
        guard Choices.haptics else { return }
        DispatchQueue.main.async { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// The color of the dust her wheels kick up in each world.
    private func dustColor(_ world: WorldKind) -> UIColor {
        switch world {
        case .city: return UIColor(red: 0.84, green: 0.82, blue: 0.80, alpha: 0.42)
        case .jungle: return UIColor(red: 0.76, green: 0.82, blue: 0.60, alpha: 0.40)
        case .house: return UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 0.34)
        case .farm: return UIColor(red: 0.90, green: 0.80, blue: 0.62, alpha: 0.44)
        }
    }

    /// Four cartoon stars that circle over her head after a crash: silly, not
    /// punishing. Flat pictures facing the camera; updateStars spins the ring and
    /// turns each star back so it keeps facing us.
    private func buildStars() {
        let m = SCNMaterial()
        m.diffuse.contents = Self.drawStar(points: 5, color: UIColor(red: 1.0, green: 0.86, blue: 0.25, alpha: 1),
                                           outline: UIColor(red: 0.85, green: 0.50, blue: 0.10, alpha: 1))
        m.lightingModel = .constant
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        Self.smoothSampling(m.diffuse)
        for i in 0..<4 {
            let plane = SCNPlane(width: 0.34, height: 0.34)
            plane.materials = [m]
            let star = SCNNode(geometry: plane)
            let a = Float(i) * .pi / 2
            star.position = SCNVector3(sin(a) * 0.5, 0, cos(a) * 0.5)
            star.castsShadow = false
            star.renderingOrder = 30
            starsNode.addChildNode(star)
        }
        starsNode.isHidden = true
        applyLook(to: starsNode)
        playerRoot.addChildNode(starsNode)
    }

    /// Spins the crash stars and pops them in. Only runs while they show.
    private func updateStars(dt: Float) {
        guard !starsNode.isHidden else { return }
        starsClock += dt
        starsAngle += dt * 5
        let pop = min(1, starsClock / 0.3)
        let s = max(0.001, pop * (1 + 0.35 * sin(pop * .pi)))
        starsNode.scale = SCNVector3(s, s, s)
        starsNode.eulerAngles.y = starsAngle
        starsNode.position = SCNVector3(0, height + 1.55 + 0.05 * sin(starsClock * 3), 0.1)
        for (i, star) in starsNode.childNodes.enumerated() {
            star.eulerAngles.y = -starsAngle
            let twinkle = 0.85 + 0.15 * sin(starsClock * 9 + Float(i) * 1.7)
            star.scale = SCNVector3(twinkle, twinkle, twinkle)
        }
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
    /// A material's own surface shader (the kitten's fur) is kept.
    private func applyLook(to root: SCNNode) {
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for m in geometry.materials where !lookSeen.contains(ObjectIdentifier(m)) {
                lookSeen.insert(ObjectIdentifier(m))
                var shaders = m.shaderModifiers ?? [:]
                shaders[.geometry] = Self.bendModifier
                shaders[.fragment] = Self.fogModifier
                m.shaderModifiers = shaders
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

    /// Each world's light. The fog color is also the bottom of its sky picture
    /// (HORIZON in scripts/make_3d_textures.py), so keep the two the same. The sun
    /// is warm and the ambient takes the color of what's around (blue shade in
    /// the city, green bounce in the jungle, cream walls indoors, open sky on the
    /// farm), which is what makes a sunlit cartoon look rich instead of flat.
    private func look(_ world: WorldKind) -> WorldLook {
        switch world {
        case .city:
            return WorldLook(sky: "skyCity", fog: Self.rgb(0xF2C9A5), sun: SIMD3(1.0, 0.91, 0.78), ambient: SIMD3(0.58, 0.58, 0.70))
        case .jungle:
            return WorldLook(sky: "skyJungle", fog: Self.rgb(0xCFD89E), sun: SIMD3(1.0, 0.98, 0.84), ambient: SIMD3(0.50, 0.66, 0.52))
        case .house:
            return WorldLook(sky: "skyHouse", fog: Self.rgb(0xF3E2C6), sun: SIMD3(1.0, 0.93, 0.82), ambient: SIMD3(0.74, 0.66, 0.58))
        case .farm:
            return WorldLook(sky: "skyFarm", fog: Self.rgb(0xCDE7F6), sun: SIMD3(1.0, 0.97, 0.86), ambient: SIMD3(0.60, 0.68, 0.76))
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
        frameLog.note("slice \(seg.world)")
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
        // Road food, plus the Fizz Rocket's trail in the sky (up to 28 cans).
        stock("food", 60) { makeFood() }
        for power in PowerUp.allCases {
            stock(powerKey(power), 2) { makePowerUp(power) }
        }
        // Short trees: at least four of each size (the staircase uses three of one
        // size, and the mix before can still have one on the road; a 333 ms stall
        // at 60 s with three). The sizes a fast run lands on get more: from about
        // 28 m/s every tree written 11 to 17 m snaps to 24 to 36 m, and with trees
        // in half the mixes, two-tree mixes back to back, there can be six or
        // seven of one size on the road. These counts come from simulating the
        // spawner over 900 two-minute runs: under 1% of runs would need one more.
        let shortStock: [Float: Int] = [14: 5, 20: 5, 24: 6, 28: 7, 32: 7, 36: 6]
        for size in Self.treeSizes {
            stock(treeKey(length: size, roof: shortRoof), shortStock[size] ?? 4) {
                makeCatTree(length: size, roof: shortRoof)
            }
        }
        // Tall trees: four per size, five of the size a 12 to 14 m tall tree
        // snaps to around 30 m/s. The mixes with three tall trees (the wall and
        // pick your way up) give them three different lengths, so they draw on
        // three pools, not one.
        for size in Self.tallSizes {
            stock(treeKey(length: size, roof: tallRoof), size == 26 ? 5 : 4) { makeCatTree(length: size, roof: tallRoof) }
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
        guard !testFrozen else { return }
        frameLog.frame(at: time, runTime: timeAlive)
        let updateStart = CACurrentMediaTime()
        defer { frameLog.updateDone(since: updateStart) }
        handleInput()
        updatePuffs(dt: dt)
        updateCollected(dt: dt)

        switch state {
        case .running:
            step(dt: dt)
        case .ready:
            // The title screen drives slowly so the world is alive behind the panel.
            homeClock += dt
            moveTrack(dz: runSpeed() * 0.45 * dt)
            updateWorldBlend()
            var motion = CartMotion()
            motion.speed = runSpeed() * 0.45
            motion.idle = true
            cart.update(dt: dt, motion: motion)
            updateCamera(dt: dt)
        case .dead:
            let wasPaused = deadClock < deathPause
            deadClock += dt
            if wasPaused && deadClock >= deathPause {
                hud.showRetry()
            }
            // Tipped over: ears back, eyes shut, tail down, wheels still.
            var motion = CartMotion()
            motion.rolling = false
            motion.crashed = true
            motion.tilt = tilt
            cart.update(dt: dt, motion: motion)
            updateChase(dt: dt)
            updateRings(dt: dt, dz: 0)
            updateStars(dt: dt)
            updateCamera(dt: dt)
        }
    }

    /// Test-only: how long SceneKit took to encode the frame after our update.
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        frameLog.renderDone()
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
        // While the Fizz Rocket flies, no new mixes come, so the road is clear
        // when she lands. They start again in time to arrive just after.
        let holdWaves = flying && (powerLeft[.rocket] ?? 0) > (spawnAhead - 40) / speed
        if untilWave <= 0 && !holdWaves {
            frameLog.note("wave")
            untilWave = spawnWave(at: spawnAhead)
        }
        untilPower -= dt
        updatePowers(dt: dt)

        updateJump(dt: dt)
        if jumpBuffer > 0 {
            jumpBuffer -= dt
            if jump() { jumpBuffer = 0 }
        }
        updateSteer(dt: dt)
        duckTimer = max(0, duckTimer - dt)
        // Tell the cart what she's doing, so her ears, head, tail, and the box
        // can answer it (see KittenCart). Events (jump, land, lane change) are
        // sent where they happen.
        var motion = CartMotion()
        motion.speed = speed
        motion.rolling = height - floorY < 0.05
        motion.tilt = tilt
        motion.steer = laneX(lane) - visualX
        motion.ducking = duckTimer > 0
        motion.airborne = jumping || height - floorY > 0.15
        motion.verticalSpeed = vy
        motion.flying = flying
        cart.update(dt: dt, motion: motion)
        homeBlend = max(0, homeBlend - dt / 0.9)
        updateRide()
        updateChase(dt: dt)
        moveItems(dz: dz, dt: dt)
        updateRings(dt: dt, dz: dz)
        resolveContacts(dz: dz)
        guard state == .running else { return }
        if e2eSwipes, platform.map(ObjectIdentifier.init) != loggedPlatform {
            // Test-only: a line each time she gets on a tree or back to the road.
            loggedPlatform = platform.map(ObjectIdentifier.init)
            testLog(platform.map { String(format: "on tree lane %d roof %.1f", $0.lane, $0.roof) } ?? "on road")
        }
        updateCamera(dt: dt)
        updateDuckHint()

        dust.birthRate = height - floorY < 0.05 ? 22 : 0
        dustNode.position.y = floorY + 0.08
        // The dust takes the color of the ground she's on, set only when it changes.
        let world = currentPlayerWorld()
        if world != dustWorld {
            dustWorld = world
            dust.particleColor = dustColor(world)
        }

        lineClock -= dt
        if lineClock <= 0 {
            lineClock = 0.12
            hud.speedLine(strength: CGFloat(min(1, (speed - 12) / 14)))
        }
        hud.setScore(score)
        hud.setFood(food)
    }

    private func updateCamera(dt: Float) {
        // The camera trails the cat a little: it follows her lane at 60%, and rides
        // up with the floor she's on (road, roof, or ramp slope) plus some of a jump.
        // It goes up quickly, so she never sits over the crest after landing on a
        // tall roof, and comes down slower, so landings feel weighty.
        // Flying, it rises with most of her height: she sits a little higher on
        // screen, about where the top of a jump off a tall tree puts her.
        let goalY = floorY + max(0, height - floorY) * (flying ? 0.8 : cameraJumpFollow)
        let rate: Float = goalY > cameraLift ? 12 : 5
        cameraLift += (goalY - cameraLift) * min(1, rate * dt)
        let goalX = visualX * 0.6
        runCameraX += (goalX - runCameraX) * min(1, 9 * dt)
        cameraNode.position = SCNVector3(runCameraX, cameraLift + cameraHeight, cameraBack)
        cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, -tilt * 0.08)
        // A shake that dies out: a crash, a stumble, or a hard landing. It's an
        // offset on top of the position above, so it never drifts the camera.
        shakeClock += dt
        if shakeLeft > 0 {
            shakeLeft = max(0, shakeLeft - dt)
            let k = shakeAmp * (shakeLeft / max(0.01, shakeTotal))
            cameraNode.position.x += sin(shakeClock * 72) * k
            cameraNode.position.y += sin(shakeClock * 51 + 1) * k * 0.7
            cameraNode.eulerAngles.z += sin(shakeClock * 60) * k * 0.15
        }
        // A slightly wider view as the run speeds up, plus a short kick on a jump
        // or a landing that fades in about a quarter second.
        fovKick *= max(0, 1 - 7 * dt)
        if fovKick < 0.02 { fovKick = 0 }
        let boost = CGFloat(max(0, runSpeed() - startSpeed) * 0.35)
        cameraNode.camera?.fieldOfView = baseFOV + (state == .running ? boost : 0) + CGFloat(fovKick)

        // Home screen, or the swoop from it: mix toward the front view of her face.
        // The home view already holds the sky where it looks right, so the sky's
        // tilt back up fades out on the way there.
        let t = homeBlend * homeBlend * (3 - 2 * homeBlend)
        skyPivot.eulerAngles.x = (skyPitch - cameraPitch) * (1 - t)
        guard homeBlend > 0 else { return }
        var eye = homeEye
        eye.x += visualX + sin(homeClock * 0.5) * 0.25
        eye.y += sin(homeClock * 0.37) * 0.06
        cameraNode.simdPosition = simd_mix(cameraNode.simdPosition, eye, SIMD3(repeating: t))
        cameraNode.simdOrientation = simd_slerp(cameraNode.simdOrientation, homeRotation, t)
    }

    private func updateJump(dt: Float) {
        if flying {
            // Fizz Rocket: rise to flying height and hold it there. No gravity.
            height += (flightHeight - height) * min(1, 3.5 * dt)
            vy = 0
        } else {
            impactSpeed = max(0, -vy)
            fall(dt: dt)
        }
        settle(dt: dt)
    }

    /// Gravity, and landing on the road or a roof.
    private func fall(dt: Float) {
        vy -= gravity * dt
        height += vy * dt
        if height < floorY {
            // Remembered for the landing's weight (squash, ring, camera kick).
            if vy <= 0 { landVy = vy }
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
    }

    /// Landing puff, squash and stretch, road bumps, ramp lean, and the shadow.
    private func settle(dt: Float) {
        let airborne = height - floorY > 0.15
        if wasAirborne && !airborne && vy <= 0 {
            // How hard she came down: about 0.3 for a plain jump, 0.75 for a slam
            // or a Pounce Springs jump, 1 for the rocket. Everything scales with it.
            let impact = min(1, max(0, (-landVy - 10) / 16))
            landSquash = 1
            landSquashAmp = 0.09 + 0.09 * impact
            puff(at: SCNVector3(visualX, floorY + 0.1, 0.2), count: 8 + Int(impact * 8), color: UIColor(white: 1, alpha: 0.9))
            landingRing(at: SCNVector3(visualX, floorY + 0.05, 0.3), strength: impact)
            fovKick = 1.5 + 2.5 * impact
            if impact > 0.5 {
                shakeCamera(amp: 0.04 + 0.08 * impact, time: 0.18)
            }
            haptic(impact > 0.6 ? .heavy : .medium)
            landVy = 0
            // A slam from the top (22 m/s) is a full hit; a step down is a soft one.
            cart.didLand(impact: min(1, impactSpeed / 22))
        }
        wasAirborne = airborne

        // Squash on landing, stretch in the air. Small, so she still reads as sitting.
        landSquash = max(0, landSquash - dt * 5)
        if landSquash == 0 { landSquashAmp = 0.12 }
        let air = min(1, max(0, height - floorY) / jumpPeak)
        let squash = sin(landSquash * .pi) * landSquashAmp
        catNode.scale = SCNVector3(1 + squash - air * 0.03, 1 - squash + air * 0.05, 1)

        // Road bumps while rolling.
        let bump = height - floorY < 0.02 ? sin(timeAlive * 38) * 0.018 : 0
        catNode.position.y = height + bump

        // Nose up while she rolls up a ramp, level again on the roof or in the air.
        var lean: Float = 0
        if let p = platform, p.rampLength > 0, p.z < p.rampLength, height - floorY < 0.05 {
            lean = atan(p.roof / p.rampLength)
        }
        // Flying, the box rides nose up and rocks a little on the fizz.
        if flying { lean = 0.09 + 0.03 * sin(timeAlive * 6) }
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
        let magnet = powerLeft[.magnet] != nil
        for item in items {
            item.z += dz
            if let gaze = item.gaze {
                // Full turn 6 m or more out, none from 2 m in.
                gaze.influenceFactor = CGFloat(0.3 * max(0, min(1, (-item.z - 2) / 4)))
            }
            if magnet && item.kind == .food && !item.pulled && item.z > -magnetRange && item.z < 0 {
                item.pulled = true
            }
            if item.pulled {
                // The Can Magnet reels it in: across to her lane and up to her,
                // faster than the road, faster still as it nears.
                item.z += dz * 0.8
                let t = max(0, min(1, 1 + item.z / magnetRange))
                let e = t * t
                item.node.position.x = laneX(item.lane) + (visualX - laneX(item.lane)) * e
                item.node.position.y = item.baseY + (height + 0.6 - item.baseY) * e
            }
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

    // The mixes, by tier. Easy ones play from the start, medium from 8 s, hard
    // from 20 s (`mediumFrom`, `hardFrom`). Cat trees are about half of every
    // tier by weight, so about half of all mixes picked have a tree at any point
    // in a run (Rex, 2026-10-05: more trees, side by side is fun). The tree
    // mixes for each tier are listed after the others, from "Cat tree mixes" on.
    private static let waves: [Wave] = [
        // Easy (first 8 s): two or three things, one move at a time.
        Wave(tier: 0, spawns: [c(1, 0), c(0, 19), c(2, 19), f(1, 19), f(1, 22)]),
        Wave(tier: 0, spawns: [c(0, 0), c(2, 0), f(1, 0), f(1, 3), c(1, 19)]),
        // Food right after a coyote: the reward for jumping it.
        Wave(tier: 0, spawns: [c(1, 0), f(1, 6), f(1, 9), f(1, 12), c(0, 19), c(2, 19)]),
        Wave(tier: 0, spawns: [t(1, 0), c(0, 10), c(2, 20)], weight: 1.4),
        Wave(tier: 0, spawns: [t(1, 0, 14), roof(1, 4), roof(1, 7), roof(1, 10), c(0, 8), c(2, 8)], weight: 1.4),
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

        // Cat tree mixes (Rex, 2026-10-05). Each lists its line through. Things
        // beside a tree spread with the square root of speed while the tree
        // stretches fully, so at speed they slide toward the tree's front: write
        // what should come after a tree past its end, never beside its tail.
        // Low things stay out of these, so none stands beside a tree or a ramp.
        // Most keep their lanes (rotates: false) because neighbors matter, and
        // CATCART_WAVE runs keep the middle lane, where the pilot rides.

        // Easy tree mixes.
        // Side by side: two short trees, roof food on both, a coyote in the open
        // lane. Jump onto either roof, or jump the coyote.
        Wave(tier: 0, spawns: [t(0, 0, 14), t(1, 0, 14), roof(0, 5), roof(0, 9), roof(1, 5), roof(1, 9),
                               c(2, 8)], weight: 1.4),
        // A ramp onto a short tree: roll straight up, no jump. Coyotes beside it.
        // From a side lane, jump the coyote or steer in before the ramp's foot.
        Wave(tier: 0, spawns: [ramp(t(1, 0, 14)), roof(1, 4), roof(1, 10), roof(1, 14), roof(1, 18),
                               c(0, 10), c(2, 10)], weight: 1.4),
        // A gate of two short trees with a coyote between them and food behind it.
        Wave(tier: 0, spawns: [t(0, 0, 11), c(1, 0), t(2, 0, 11), f(1, 6), f(1, 9),
                               roof(0, 4), roof(0, 7), roof(2, 4), roof(2, 7)], weight: 1.4, rotates: false),

        // Medium tree mixes: tall trees and ramps join here.
        // Ramp up: roll up onto a tall tree in the middle; coyotes on both sides.
        // The easy way through is up. Side lanes are two coyotes, 19 m apart.
        Wave(tier: 1, spawns: [ramp(tall(1, 0, 14)), c(0, 6), c(2, 6), c(0, 25), c(2, 25),
                               roof(1, 4), roof(1, 13), roof(1, 16), roof(1, 19)], rotates: false),
        // Staircase up: a short tree, then a tall one right behind it. Jump on,
        // then jump from the short roof up to the tall one before its front comes
        // (rolling into it is a crash). The sides are two coyotes each.
        Wave(tier: 1, spawns: [t(1, 0, 14), tall(1, 14, 14), c(0, 6), c(2, 6), c(0, 25), c(2, 25),
                               roof(1, 5), roof(1, 9), roof(1, 18), roof(1, 21), roof(1, 24)], rotates: false),
        // Step down: a ramp up a tall tree, a longer short tree beside it. Step
        // right off the tall roof onto the short one for its food. Or jump onto the
        // short tree from the road, or jump the coyotes on the left.
        Wave(tier: 1, spawns: [ramp(tall(1, 0, 14)), t(2, 8, 20), c(0, 6), c(0, 25),
                               roof(1, 12), roof(1, 16), roof(2, 20), roof(2, 24), roof(2, 27)], rotates: false),
        // Twin trees: side by side, the left one shorter. Ride it and step across
        // before it ends, or drop off and jump the coyote waiting behind it.
        Wave(tier: 1, spawns: [t(0, 0, 11), t(1, 0, 17), roof(0, 4), roof(0, 7), roof(1, 12), roof(1, 15),
                               c(0, 30), c(2, 4), c(2, 23)], rotates: false),
        // A long pair with the food zigzagging between the two roofs: step back
        // and forth to get it all. Coyotes in the open lane.
        Wave(tier: 1, spawns: [t(0, 0, 17), t(1, 0, 17), roof(0, 3), roof(1, 7), roof(0, 11), roof(1, 15),
                               c(2, 4), c(2, 23)], rotates: false),
        // A pair that walks across the road: left and middle, then middle and
        // right. The middle hands her straight on to the next tree; from the left,
        // step right before it ends. Food on the open right lane, then up.
        Wave(tier: 1, spawns: [t(0, 0, 14), t(1, 0, 14), t(1, 14, 11), t(2, 14, 17),
                               roof(0, 5), roof(1, 9), roof(1, 18), roof(2, 22), roof(2, 27),
                               f(2, 3), f(2, 6), c(0, 33)], rotates: false),
        // A ramp beside a tall tree: the tall lane is a wall, so steer onto the
        // ramp (or into the coyote lane). Its food is for a jump off the short
        // roof, high enough to step across onto the tall one.
        Wave(tier: 1, spawns: [ramp(t(1, 0, 14)), tall(0, 8, 14), c(2, 6), c(2, 25),
                               roof(1, 4), roof(1, 12), roof(1, 16), roof(1, 20), roof(0, 14), roof(0, 18)]),

        // Hard tree mixes.
        // Tree yard: three staggered trees, one per lane. Hop roof to roof as each
        // one ends, left to right, for all the food. Every lane meets a tree, so
        // it's a forced jump onto a roof, kept a little rarer.
        Wave(tier: 2, spawns: [t(0, 0, 14), t(1, 7, 17), t(2, 14, 14),
                               roof(0, 4), roof(0, 9), roof(1, 12), roof(1, 17), roof(2, 21), roof(2, 25),
                               c(0, 33), c(1, 43), c(2, 47)], weight: 0.8, rotates: false),
        // Wall with a ramp: tall trees across the road, a ramp up the middle one.
        // Up is the only way through: steer to the middle before the ramp's foot.
        // Level roofs, so from the top she can step across for the side food.
        // Three lengths, so the three tall trees don't all come from one pool.
        Wave(tier: 2, spawns: [tall(0, 8, 12), ramp(tall(1, 0, 14)), tall(2, 8, 17),
                               roof(1, 4), roof(1, 12), roof(1, 16), roof(1, 20), roof(0, 18), roof(2, 18)],
             weight: 1.25, rotates: false),
        // Gap jump: two short trees in the middle with an 8 m gap and a coyote in
        // it. Jump from the end of the first roof over the coyote onto the second
        // (food in the air on the way). Falling in is a crash, so this lane is a
        // jump-or-steer lane, and the one exception to 19 m between things in a
        // lane: the coyote is cleared in the same jump. Or step left onto the
        // tree there, ride past the gap, and step back. Coyotes on the right.
        Wave(tier: 2, spawns: [t(1, 0, 14), c(1, 17), t(1, 22, 14), air(1, 15), air(1, 18),
                               roof(1, 26), roof(1, 30), t(0, 10, 17), roof(0, 16), roof(0, 20),
                               c(2, 6), c(2, 25)], weight: 1.25, rotates: false),
        // Pick your way up: a staircase on the left (short tree, then tall), a
        // tall wall in the middle, a ramp on the right. From the middle, steer
        // left before the short tree or right before the ramp's foot.
        Wave(tier: 2, spawns: [t(0, 0, 11), tall(0, 11, 12), tall(1, 11, 14), ramp(tall(2, 3, 17)),
                               roof(0, 4), roof(0, 15), roof(0, 20), roof(1, 18), roof(2, 15), roof(2, 20)],
             weight: 1.25, rotates: false),
        // Two long trees with the coyotes between them: ride either side, or
        // stay in the middle and jump twice, with food in the air.
        Wave(tier: 2, spawns: [t(0, 0, 17), t(2, 0, 17), c(1, 0), c(1, 19), air(1, 19), air(1, 22),
                               roof(0, 5), roof(0, 11), roof(2, 5), roof(2, 11)], weight: 1.25, rotates: false)
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
        let firstNew = items.count
        defer { if e2eSwipes { logWave(from: firstNew) } }
        let wave = Self.waves[lastWave]
        let mirror = e2eMirror ?? Bool.random()
        let rot = wave.rotates ? (e2eRot ?? Int.random(in: 0...2)) : 0
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
        // Something written after a tree's end keeps its written distance from
        // where that tree really ends. With several trees ended before it, the
        // one that ends latest counts, not their sum: two trees side by side
        // push what follows once, so a tree written right behind one of them is
        // still right behind it (a hand-off), not a gap.
        func ahead(_ spawn: Spawn) -> Float {
            var push: Float = 0
            for tree in trees where tree.spawn.ahead + tree.writtenTotal <= spawn.ahead + 0.01 {
                let end = ahead(tree.spawn) + tree.total
                push = max(push, end - (tree.spawn.ahead + tree.writtenTotal) * scale)
            }
            return spawn.ahead * scale + push
        }

        // Where this mix meets the one before, keep the same gaps as inside a mix:
        // 19 m from the end of the last thing in a lane to the next one, 24 m from a
        // coyote to a low thing. If a lane is too close, the whole mix moves back.
        var shift: Float = 0
        for spawn in wave.spawns where spawn.kind != .food {
            let lane = place(spawn.lane)
            let front = base + ahead(spawn)
            for item in items where item.lane == lane && item.kind != .food && item.kind != .power {
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
        // Now and then one can of food in the mix is a power-up instead. Food is
        // always somewhere she can reach (on the open side, over a coyote, on a
        // roof), so the power-up is too.
        var powerSpawn: Int?
        var powerKind: PowerUp?
        let foodSpawns = wave.spawns.indices.filter { wave.spawns[$0].kind == .food }
        if untilPower <= 0, !flying, let pick = foodSpawns.randomElement() {
            powerSpawn = pick
            powerKind = nextPower()
            untilPower = e2ePowerEvery ?? Float.random(in: 14...20)
        }
        for (index, spawn) in wave.spawns.enumerated() where spawn.kind != .tree {
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
            if index == powerSpawn {
                addItem(.power, lane: lane, z: -base - at, high: spawn.high, y: y, power: powerKind)
            } else {
                addItem(spawn.kind, lane: lane, z: -base - at, high: spawn.high, y: y)
            }
            reach = max(reach, at)
        }
        // A short beat after the mix, in seconds so it means the same at any speed:
        // 0.9 s at the start, 0.45 s at 30 s, down to 0.25 s at full ramp (75 s),
        // so mixes run into each other. The per-lane gaps above are what keep the joins fair.
        let gapSeconds: Float = max(0.25, 0.9 - 0.7 * ramp)
        return reach + runSpeed() * gapSeconds
    }

    /// Test-only: with CATCART_SWIPES set, prints where each thing of the mix
    /// just placed reaches her, in meters run, so a scripted line can be timed
    /// against the `meters` in the swipe lines.
    private func logWave(from first: Int) {
        let parts = items[first...].map { item -> String in
            let front = meters - item.z
            switch item.kind {
            case .tree:
                return String(format: "tree lane %d %.1f-%.1f roof %.1f ramp %.1f",
                              item.lane, front, front + item.length, item.roof, item.rampLength)
            case .food:
                return String(format: "food lane %d %.1f%@", item.lane, front, item.high ? " air" : "")
            case .coyote:
                return String(format: "coyote lane %d %.1f", item.lane, front)
            case .low:
                return String(format: "low lane %d %.1f", item.lane, front)
            case .power:
                return String(format: "power %@ lane %d %.1f", "\(item.power ?? .magnet)", item.lane, front)
            }
        }
        print(String(format: "CATCART mix %d at run %.2f s: ", lastWave, timeAlive) + parts.joined(separator: "; "))
        fflush(stdout)
    }

    /// Puts one thing on the road. For a cat tree, `length` includes its ramp.
    /// `y` lifts food onto a roof.
    @discardableResult
    private func addItem(_ kind: Kind, lane: Int, z: Float, length: Float = 0, roof: Float = 0,
                         rampLength: Float = 0, high: Bool = false, y: Float = 0,
                         power: PowerUp? = nil) -> TrackItem {
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
        case .power:
            let p = power ?? .magnet
            node = takeNode(powerKey(p)) { self.makePowerUp(p) }
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
        item.power = power
        if kind == .coyote {
            item.gaze = node.childNode(withName: "head", recursively: true)?.constraints?.first as? SCNLookAtConstraint
        }
        // Food in the air hangs where a jump's arc carries her, and drops its shadow.
        node.childNode(withName: "shadow", recursively: false)?.isHidden = high
        node.position = SCNVector3(laneX(lane), high ? airFoodY : y, item.nodeZ)
        item.baseY = node.position.y
        // A pooled node may have been knocked away (hidden) or caught popping in.
        node.isHidden = false
        node.removeAction(forKey: "pop")
        node.scale = SCNVector3(1, 1, 1)
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
        if frameLog.enabled {
            // Every build mid-run is a pool that ran dry, hitch or not.
            print(String(format: "CATCART built %@ at run %.1f s", key, timeAlive))
            fflush(stdout)
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
            // Every coyote is its own animal: a touch bigger or smaller, its own
            // stride rate, its gallop started partway through, so a pack never
            // runs in step. 1.14 m tall at 1.0; the low thing is at 1.38 m, so
            // 5% either way still fits under it.
            let size = Float.random(in: 0.95...1.05)
            coyote.scale = SCNVector3(size, size, size)
            // The saved model may change size. Keep its nose on the item's
            // front edge, where contact is measured, using its actual bounds.
            let bounds = coyote.boundingBox
            coyote.position = SCNVector3(0, 0, -bounds.max.z * size)
            desyncGallop(coyote)
            addBodyBob(coyote)
            aimHeadAtCat(coyote)
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

    /// Restarts every "run" animation on one coyote from a random point in the
    /// stride, at its own pace, so clones stop galloping in lockstep. The gallop
    /// is saved in coyote_run.scn as one looping player per moving part (see
    /// scripts/build_game_pickup.swift), and all the parts of one coyote get the
    /// same offset and speed so it stays one animal. The pace spread also keeps
    /// two coyotes from drifting back into step later in a run.
    private func desyncGallop(_ coyote: SCNNode) {
        let offset = TimeInterval.random(in: 0..<0.45)
        let pace = CGFloat.random(in: 0.9...1.1)
        coyote.enumerateHierarchy { part, _ in
            guard let player = part.animationPlayer(forKey: "run"),
                  let animation = player.animation.copy() as? SCNAnimation else { return }
            animation.timeOffset = offset
            let own = SCNAnimationPlayer(animation: animation)
            own.speed = pace
            part.removeAnimation(forKey: "run")
            part.addAnimationPlayer(own, forKey: "run")
        }
    }

    /// A faint extra rise and fall at a period that doesn't divide the 0.45 s
    /// stride, so no two coyotes settle into the same rhythm. It runs on the
    /// clone itself, under the pool node, so the pool can keep it forever.
    private func addBodyBob(_ coyote: SCNNode) {
        let lift: CGFloat = 0.025
        let half = TimeInterval.random(in: 0.29...0.37)
        let up = SCNAction.moveBy(x: 0, y: lift, z: 0, duration: half)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.moveBy(x: 0, y: -lift, z: 0, duration: half)
        down.timingMode = .easeInEaseOut
        coyote.runAction(.repeatForever(.sequence([up, down])), forKey: "bob")
    }

    /// The head leans a little toward the cat, so a coyote in the next lane
    /// looks across at her instead of straight down the road. The gallop's head
    /// bob stays: the constraint only pulls the animated pose part way to her.
    private func aimHeadAtCat(_ coyote: SCNNode) {
        guard let head = coyote.childNode(withName: "head", recursively: true), let target = catNode else { return }
        let look = SCNLookAtConstraint(target: target)
        look.localFront = SCNVector3(0, 0, 1) // the model faces +z, toward the camera
        look.isGimbalLockEnabled = true // turn and nod, never roll the head
        look.influenceFactor = 0.3
        head.constraints = [look]
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
            // A soft bob, each can on its own beat so a line of them ripples.
            let rise = SCNAction.moveBy(x: 0, y: 0.14, z: 0, duration: 0.5)
            rise.timingMode = .easeInEaseOut
            let sink = SCNAction.moveBy(x: 0, y: -0.14, z: 0, duration: 0.5)
            sink.timingMode = .easeInEaseOut
            pickup.runAction(.sequence([
                .wait(duration: 0, withRange: 1.0),
                .repeatForever(.sequence([rise, sink]))
            ]))
            if foodModel != nil {
                // The real can turns slowly so the label and the salmon both show.
                pickup.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 3.2)))
            }
            // A glint that winks on the can's shoulder now and then. It hangs off
            // the still node, not the turning can, so it always faces the camera.
            let glint = SCNNode(geometry: SCNPlane(width: 0.26, height: 0.26))
            glint.geometry?.materials = [glintMaterial]
            glint.position = SCNVector3(-0.2, 0.68, 0.3)
            glint.scale = SCNVector3(0.01, 0.01, 0.01)
            glint.castsShadow = false
            glint.renderingOrder = 25
            node.addChildNode(glint)
            glint.runAction(.repeatForever(.sequence([
                .wait(duration: 1.4, withRange: 1.6),
                .group([.scale(to: 1, duration: 0.16), .rotateBy(x: 0, y: 0, z: 0.5, duration: 0.4)]),
                .scale(to: 0.01, duration: 0.24)
            ])))
        }
        // Real meshes need the same road bend and fog as every other object.
        applyLook(to: node)
        let shadow = shadowNode(width: 0.7, length: 0.55)
        shadow.name = "shadow"
        node.addChildNode(shadow)
        return node
    }

    /// The white four-point star that glints on cans, shared by every can.
    private lazy var glintMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.diffuse.contents = Self.drawStar(points: 4, color: UIColor(white: 1, alpha: 1), outline: nil)
        m.lightingModel = .constant
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        Self.smoothSampling(m.diffuse)
        return m
    }()

    private func shadowNode(width: CGFloat, length: CGFloat) -> SCNNode {
        let node = SCNNode(geometry: groundPlane(width: width, length: length, material: shadowMaterial))
        node.position = SCNVector3(0, 0.03, 0)
        node.renderingOrder = 5
        node.castsShadow = false
        return node
    }

    // MARK: - Cat tree

    // The roof carpet is warm cream with paw prints pressed into the pile. The
    // side carpet is a neutral light gray that each tree tints its own way (see
    // treeAccents). Sisal is the wrapped rope on the posts and scratch boards.
    private lazy var carpetTop: SCNMaterial = carpetMaterial("carpetTop", fallback: UIColor(red: 0.95, green: 0.90, blue: 0.81, alpha: 1))
    private lazy var carpetSide: SCNMaterial = carpetMaterial("carpetSide", fallback: UIColor(red: 0.85, green: 0.83, blue: 0.80, alpha: 1))
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

    /// Accent carpets, one per tree: cream, soft gray, mint, blush pink,
    /// lavender, and the classic sand. The gray side-carpet picture is tinted by
    /// a material's multiply color, so one picture gives every accent.
    private static let treeAccents: [(CGFloat, CGFloat, CGFloat)] = [
        (0.97, 0.91, 0.78), (0.74, 0.74, 0.77), (0.70, 0.90, 0.80),
        (0.98, 0.78, 0.82), (0.82, 0.78, 0.95), (0.88, 0.74, 0.55)
    ]
    /// Toy colors for the pom-pom, hammock, and tunnel: raspberry, teal, orange, violet, green.
    private static let treeToyColors: [(CGFloat, CGFloat, CGFloat)] = [
        (0.98, 0.30, 0.55), (0.20, 0.70, 0.80), (1.0, 0.62, 0.15), (0.55, 0.40, 0.85), (0.25, 0.75, 0.45)
    ]
    /// Cream for door rims, ears, and steps; sand for a ramp's sides.
    private static let creamTint: (CGFloat, CGFloat, CGFloat) = (0.99, 0.96, 0.90)
    private static let sandTint: (CGFloat, CGFloat, CGFloat) = (0.88, 0.74, 0.55)
    /// Counts the trees built, so each copy in a pool picks a different accent.
    private var treesBuilt = 0

    /// A copy of a carpet material, tinted and tiled. `tile` is how many times
    /// the picture repeats across and along a face; one repeat is one lane width
    /// of carpet. Every copy is its own draw call after the merge, so a tree
    /// keeps to a handful of them.
    private func carpet(_ base: SCNMaterial, tint: (CGFloat, CGFloat, CGFloat)? = nil, shade: CGFloat = 1,
                        tile: (Float, Float) = (1, 1)) -> SCNMaterial {
        let m = base.copy() as! SCNMaterial
        if let t = tint {
            m.multiply.contents = UIColor(red: t.0 * shade, green: t.1 * shade, blue: t.2 * shade, alpha: 1)
        } else if shade != 1 {
            m.multiply.contents = UIColor(white: shade, alpha: 1)
        }
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(tile.0, tile.1, 1)
        return m
    }

    /// A plain matte color for toys, hammocks, and tunnels.
    private func plainMaterial(_ c: (CGFloat, CGFloat, CGFloat), shade: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: c.0 * shade, green: c.1 * shade, blue: c.2 * shade, alpha: 1)
        m.lightingModel = .lambert
        m.isDoubleSided = true
        return m
    }

    /// Adds one piece as a direct child of `parent`, with its whole placement on
    /// itself. The merge below bakes in a child's own transform only, so pieces
    /// are never nested (see the doorway note in the first tree build).
    private func put(_ g: SCNGeometry, _ m: SCNMaterial? = nil, at p: SCNVector3,
                     tilt: SCNVector3 = SCNVector3(0, 0, 0), into parent: SCNNode) {
        if let m = m { g.materials = [m] }
        let n = SCNNode(geometry: g)
        n.position = p
        n.eulerAngles = tilt
        parent.addChildNode(n)
    }

    /// A carpeted slab with soft rounded edges. Three chamfer segments keep a
    /// slab near 360 triangles instead of 1,500 with SceneKit's default of ten.
    private func plushBox(_ w: Float, _ h: Float, _ l: Float, round: CGFloat) -> SCNBox {
        let b = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: round)
        b.chamferSegmentCount = 3
        return b
    }

    /// A cat ear: a triangle with a soft tip, standing up from y = 0, thin along z.
    private func earShape(_ size: CGFloat) -> SCNShape {
        let path = UIBezierPath()
        path.flatness = 0.01
        path.move(to: CGPoint(x: -size * 0.5, y: 0))
        path.addLine(to: CGPoint(x: size * 0.5, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: size), controlPoint: CGPoint(x: size * 0.42, y: size * 0.55))
        path.addQuadCurve(to: CGPoint(x: -size * 0.5, y: 0), controlPoint: CGPoint(x: -size * 0.42, y: size * 0.55))
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.14)
        shape.chamferRadius = 0.02
        return shape
    }

    /// A doorway with a round top, standing up from y = 0, as thin as a decal.
    private func archShape(width: CGFloat, height: CGFloat) -> SCNShape {
        let r = width / 2
        let path = UIBezierPath()
        path.flatness = 0.01
        path.move(to: CGPoint(x: -r, y: 0))
        path.addLine(to: CGPoint(x: -r, y: height - r))
        // From the left to the right over the top (the heart's lobes use the same sweep).
        path.addArc(withCenter: CGPoint(x: 0, y: height - r), radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: r, y: 0))
        path.close()
        return SCNShape(path: path, extrusionDepth: 0.02)
    }

    /// A hammock: a cloth band sagging between two points `span` apart, hung at
    /// y = 0 and `sag` deep in the middle, stretched `depth` along z.
    private func hammockShape(span: CGFloat, sag: CGFloat, depth: CGFloat) -> SCNShape {
        let path = UIBezierPath()
        path.flatness = 0.01
        path.move(to: CGPoint(x: -span / 2, y: 0))
        path.addQuadCurve(to: CGPoint(x: span / 2, y: 0), controlPoint: CGPoint(x: 0, y: -sag * 2))
        path.addLine(to: CGPoint(x: span / 2, y: -0.06))
        path.addQuadCurve(to: CGPoint(x: -span / 2, y: -0.06), controlPoint: CGPoint(x: 0, y: -sag * 2 - 0.1))
        path.close()
        return SCNShape(path: path, extrusionDepth: depth)
    }

    /// A long carpeted cat tree that fills one lane like a Subway Surfers train.
    /// Front edge at z = 0, stretching back to z = -length. The roof is the ride:
    /// a thick cream platform with rounded edges and a trail of paw prints, flat
    /// for its whole length, with nothing standing on it. Under it, thick sisal
    /// posts frame bays that hold carpeted condos with round or arched doors and
    /// cat ears, hammocks, tunnels, and scratch boards, in an accent carpet that
    /// differs from tree to tree. A short tree (roof 2.0 m) has one story; a tall
    /// one (3.5 m) has a carpet shelf halfway up and a second story of condos
    /// above it, a tower you smash into from the road.
    private func makeCatTree(length: Float, roof roofTop: Float) -> SCNNode {
        let root = SCNNode()
        // Everything that doesn't move is built as separate pieces, then merged
        // into one mesh below, so SceneKit draws the whole frame in one call per
        // material (eight or so) instead of one per piece (over a hundred).
        let parts = SCNNode()
        let width: Float = 1.75
        let stories = roofTop > shortRoof + 0.01 ? 2 : 1

        // Each copy picks its own accent carpet and toy color, so a pool of six
        // 24 m trees gives six different trees on the road.
        treesBuilt += 1
        let pick = treesBuilt &+ Int(length) &* 3 &+ (stories == 2 ? 1 : 0)
        let accent = Self.treeAccents[pick % Self.treeAccents.count]
        let toyColor = Self.treeToyColors[(pick / Self.treeAccents.count &+ treesBuilt) % Self.treeToyColors.count]

        // The materials. Each is one draw call once the pieces are merged.
        let along = length / width
        let roofCarpet = carpet(carpetTop, tile: (1, along))
        let trimLong = carpet(carpetSide, tint: accent, shade: 0.76, tile: (along, 0.25))
        let trim = carpet(carpetSide, tint: accent, shade: 0.76)
        let plush = carpet(carpetSide, tint: accent)
        let cream = carpet(carpetSide, tint: Self.creamTint)
        let postHeight = roofTop - 0.3
        let rope = carpet(sisal, tile: (2, postHeight * 1.5))
        let toy = plainMaterial(toyColor)
        let hole = SCNMaterial()
        hole.diffuse.contents = UIColor(red: 0.18, green: 0.12, blue: 0.10, alpha: 1)
        hole.lightingModel = .constant

        // Roof: thick and plush, cream on top with paw prints, the accent's
        // darker shade around the edge, so it reads as a platform from far off.
        // Box faces go front, right, back, left, top, bottom.
        let roofThick: Float = 0.26
        let roof = plushBox(width, roofThick, length, round: 0.11)
        roof.materials = [trim, trimLong, trim, trimLong, roofCarpet, trim]
        put(roof, at: SCNVector3(0, roofTop - roofThick / 2, -length / 2), into: parts)

        // Base plate on the ground, in the dark trim.
        let floor0: Float = 0.16
        let base = plushBox(width, floor0, length, round: 0.05)
        base.materials = [trim, trimLong, trim, trimLong, trim, trim]
        put(base, at: SCNVector3(0, floor0 / 2, -length / 2), into: parts)

        // Each story is the space from one floor (the base, or the shelf) up to
        // the next. A tall tree's shelf is a thinner carpet deck the length of the tree.
        let storyHeight = (roofTop - roofThick - floor0) / Float(stories)
        if stories == 2 {
            let shelf = plushBox(width - 0.08, 0.14, length - 0.2, round: 0.05)
            shelf.materials = [trim, trimLong, trim, trimLong, plush, trim]
            put(shelf, at: SCNVector3(0, floor0 + storyHeight - 0.07, -length / 2), into: parts)
        }

        // Thick sisal-wrapped posts down both sides, floor to roof, one pair at
        // each bay line. Twelve sides each: the rope picture does the rounding.
        let post = SCNCylinder(radius: 0.15, height: CGFloat(postHeight))
        post.radialSegmentCount = 12
        post.materials = [rope, trim, trim]
        let bays = max(2, Int((length / 3.2).rounded()))
        let bayLength = (length - 0.7) / Float(bays)
        func bayZ(_ i: Int) -> Float { -0.35 - (Float(i) + 0.5) * bayLength }
        for i in 0...bays {
            let z = -0.35 - Float(i) * bayLength
            for x: Float in [-0.72, 0.72] {
                put(post, at: SCNVector3(x, floor0 + postHeight / 2, z), into: parts)
            }
        }

        // Condos. A short tree has one in every other bay. A tall tree's front
        // bay is a condo on both stories, so its face is a solid wall; behind
        // that the stories alternate, so the side shows a checkerboard of
        // condos and open bays with hammocks and tunnels in them.
        func hasCubby(_ story: Int, _ i: Int) -> Bool {
            if story == 1 && i == 0 { return true }
            return i % 2 == story
        }
        let cubbyHeight = storyHeight * 0.7
        let cubby = plushBox(1.25, cubbyHeight, 1.5, round: 0.12)
        cubby.materials = [plush]
        let holeR = min(0.36, cubbyHeight * 0.33)
        // A round porthole with a rolled cream rim, or an arched doorway.
        let disc = SCNCylinder(radius: CGFloat(holeR), height: 0.02)
        disc.radialSegmentCount = 16
        disc.materials = [hole]
        let ring = SCNTorus(ringRadius: CGFloat(holeR), pipeRadius: 0.055)
        ring.ringSegmentCount = 18
        ring.pipeSegmentCount = 6
        ring.materials = [cream]
        let arch = archShape(width: CGFloat(holeR * 1.7), height: CGFloat(cubbyHeight * 0.72))
        arch.materials = [hole]
        // Cat ears on the porthole condos, in the gap under the next floor.
        let ear = earShape(0.28)
        ear.materials = [plush]
        let innerEar = earShape(0.15)
        innerEar.materials = [cream]
        let faceDown = SCNVector3(Float.pi / 2, 0, 0)
        var cubbyCount = 0
        for story in 0..<stories {
            let floor = floor0 + Float(story) * storyHeight
            for i in 0..<bays where hasCubby(story, i) {
                let z = bayZ(i)
                let mid = floor + cubbyHeight / 2
                let face = z + 0.75
                put(cubby, at: SCNVector3(0, mid, z), into: parts)
                if cubbyCount % 2 == 0 {
                    put(disc, at: SCNVector3(0, mid - 0.05, face + 0.01), tilt: faceDown, into: parts)
                    put(ring, at: SCNVector3(0, mid - 0.05, face), tilt: faceDown, into: parts)
                    for x: Float in [-0.4, 0.4] {
                        put(ear, at: SCNVector3(x, floor + cubbyHeight - 0.03, face - 0.3), into: parts)
                        put(innerEar, at: SCNVector3(x, floor + cubbyHeight, face - 0.29), into: parts)
                    }
                } else {
                    put(arch, at: SCNVector3(0, floor + cubbyHeight * 0.1, face + 0.01), into: parts)
                }
                cubbyCount += 1
            }
        }

        // Open bays take turns: a hammock slung between the posts, a carpet
        // tunnel on the floor (a lookout tube on a tall tree's upper story), or
        // a sisal scratch board leaning up the outer side with cream steps.
        // All of it stays under the roof and inside the lane.
        var openCount = 0
        for story in 0..<stories {
            let floor = floor0 + Float(story) * storyHeight
            for i in 0..<bays where !hasCubby(story, i) {
                let z = bayZ(i)
                switch openCount % 3 {
                case 0:
                    let hammock = hammockShape(span: 1.46, sag: 0.3, depth: 1.0)
                    hammock.materials = [toy]
                    put(hammock, at: SCNVector3(0, floor + storyHeight * 0.62, z), into: parts)
                case 1:
                    if story == 1 {
                        let tube = SCNTube(innerRadius: 0.30, outerRadius: 0.37, height: CGFloat(storyHeight * 0.7))
                        tube.radialSegmentCount = 14
                        tube.materials = [toy]
                        put(tube, at: SCNVector3(0, floor + storyHeight * 0.35, z), into: parts)
                        let window = SCNCylinder(radius: 0.17, height: 0.02)
                        window.radialSegmentCount = 12
                        window.materials = [hole]
                        put(window, at: SCNVector3(0, floor + storyHeight * 0.42, z + 0.37), tilt: faceDown, into: parts)
                    } else {
                        let tunnel = SCNTube(innerRadius: 0.34, outerRadius: 0.42, height: 1.4)
                        tunnel.radialSegmentCount = 14
                        tunnel.materials = [toy]
                        put(tunnel, at: SCNVector3(0, floor + 0.42, z), tilt: faceDown, into: parts)
                    }
                default:
                    let side: Float = openCount % 2 == 0 ? 1 : -1
                    let x = side * 0.86
                    let run = bayLength * 0.62
                    let rise = storyHeight * 0.82
                    // Tipping a standing box about x by theta leans its top toward +z (the front).
                    let theta = atan(run / rise)
                    let lean = SCNVector3(theta, 0, 0)
                    let board = SCNBox(width: 0.14, height: CGFloat((run * run + rise * rise).squareRoot()), length: 0.06, chamferRadius: 0.01)
                    board.materials = [rope]
                    put(board, at: SCNVector3(x, floor + rise / 2, z), tilt: lean, into: parts)
                    let step = SCNBox(width: 0.16, height: 0.05, length: 0.1, chamferRadius: 0.01)
                    step.materials = [cream]
                    for k in 1...4 {
                        // Along the board, then out along the face that looks up.
                        let t = Float(k) / 5 - 0.5
                        put(step, at: SCNVector3(x, floor + rise / 2 + t * rise + 0.04 * sin(theta), z + t * run - 0.04 * cos(theta)),
                            tilt: lean, into: parts)
                    }
                }
                openCount += 1
            }
        }
        // The look goes on before merging. A merged mesh starts with no materials
        // and picks up the pieces' ones later, so applyLook on the merged node
        // finds nothing, and the tree would float unbent over the far road.
        applyLook(to: parts)
        root.addChildNode(parts.flattenedClone())

        // Toys swinging under the roof's edge, beside the first and last bays and
        // outside the ride: a pom-pom at the front, a toy mouse or a feather at
        // the back. Two moving nodes per tree, each one merged mesh.
        root.addChildNode(hangingToy("pom", color: toy, at: SCNVector3(0.78, roofTop - roofThick, -0.9), swing: 0.65))
        root.addChildNode(hangingToy(pick % 2 == 0 ? "mouse" : "feather", color: toy,
                                     at: SCNVector3(-0.78, roofTop - roofThick, -length + 0.9), swing: 0.8))

        // A soft shadow the length of the tree.
        let shade = SCNNode(geometry: groundPlane(width: CGFloat(width) + 0.7, length: CGFloat(length) + 0.8, material: shadowMaterial))
        shade.position = SCNVector3(0, 0.025, -length / 2)
        shade.castsShadow = false
        root.addChildNode(shade)

        applyLook(to: root)
        return root
    }

    /// A toy on a string under a roof's edge. The string and the toy are merged
    /// into one mesh on a pivot that rocks; `swing` is the seconds for one side,
    /// so two toys on one tree don't move in step.
    private func hangingToy(_ kind: String, color: SCNMaterial, at pivot: SCNVector3, swing: Double) -> SCNNode {
        let hanger = SCNNode()
        hanger.position = pivot
        let bits = SCNNode()
        let drop: Float = 0.55
        let string = SCNCylinder(radius: 0.012, height: CGFloat(drop))
        string.radialSegmentCount = 6
        put(string, color, at: SCNVector3(0, -drop / 2, 0), into: bits)
        switch kind {
        case "mouse":
            // A gray felt mouse hanging by its tail, nose down, ears and nose in the toy color.
            let felt = plainMaterial((0.64, 0.62, 0.66))
            let body = SCNCapsule(capRadius: 0.09, height: 0.3)
            body.radialSegmentCount = 10
            body.capSegmentCount = 6
            put(body, felt, at: SCNVector3(0, -drop - 0.15, 0), into: bits)
            let earBall = SCNSphere(radius: 0.05)
            earBall.segmentCount = 8
            for x: Float in [-0.07, 0.07] {
                put(earBall, color, at: SCNVector3(x, -drop - 0.21, 0.05), into: bits)
            }
            let nose = SCNSphere(radius: 0.03)
            nose.segmentCount = 6
            put(nose, color, at: SCNVector3(0, -drop - 0.31, 0), into: bits)
        case "feather":
            // A white feather on a bell, tip down.
            let white = plainMaterial((0.98, 0.98, 0.96))
            let quill = SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.34)
            quill.radialSegmentCount = 8
            put(quill, white, at: SCNVector3(0, -drop - 0.2, 0), tilt: SCNVector3(Float.pi, 0, 0), into: bits)
            let bell = SCNSphere(radius: 0.05)
            bell.segmentCount = 8
            put(bell, color, at: SCNVector3(0, -drop, 0), into: bits)
        default:
            // The pom-pom from the 2D art, with a smaller fluff ball beside it.
            let pom = SCNSphere(radius: 0.15)
            pom.segmentCount = 10
            put(pom, color, at: SCNVector3(0, -drop - 0.1, 0), into: bits)
            let fluff = SCNSphere(radius: 0.08)
            fluff.segmentCount = 8
            put(fluff, color, at: SCNVector3(0.1, -drop - 0.22, 0.06), into: bits)
        }
        applyLook(to: bits)
        hanger.addChildNode(bits.flattenedClone())
        hanger.runAction(.repeatForever(.sequence([
            .rotateTo(x: 0, y: 0, z: 0.25, duration: swing, usesShortestUnitArc: true),
            .rotateTo(x: 0, y: 0, z: -0.25, duration: swing, usesShortestUnitArc: true)
        ])))
        return hanger
    }

    // MARK: - Ramp

    // Ramps share their materials: dark sand carpet on the sides, cream steps.
    // The slope itself is the roof carpet, so the paw prints lead up it.
    private lazy var rampSide: SCNMaterial = carpet(carpetSide, tint: Self.sandTint, shade: 0.8)
    private lazy var rampStep: SCNMaterial = carpet(carpetSide, tint: Self.creamTint)

    /// A carpeted ramp up to a tree's roof: a solid wedge from the road at its foot
    /// (z = +length) to the roof's height at its top (z = 0), where it meets the
    /// tree's front. It's added as a child of the tree's node, so it moves with it.
    /// A sisal scratch-pad runner goes up the middle with cream steps across it,
    /// and sisal rope runs along both top edges, so it reads as cat furniture,
    /// not a road. The wedge is cut into short slices along its length so the
    /// curved-world bend bends it with the road. Merged into one mesh like a tree.
    /// The slope is the gameplay (topAtCat reads it); the steps are 5 cm of trim.
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
        var runner: [UInt16] = []
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
        // The sisal runner: a strip up the middle, a hair above the carpet so it
        // never flickers through it, with the rope's wraps lying across it.
        let lift = SCNVector3(up.x * 0.012, up.y * 0.012, up.z * 0.012)
        let rw: Float = 0.26
        for i in 0..<slices {
            let a = station(i), b = station(i + 1)
            let r0 = add(SCNVector3(-rw + lift.x, a.y + lift.y, a.z + lift.z), upN, CGPoint(x: 0, y: CGFloat(a.along * 1.5)))
            let r1 = add(SCNVector3(rw + lift.x, a.y + lift.y, a.z + lift.z), upN, CGPoint(x: 1, y: CGFloat(a.along * 1.5)))
            let r2 = add(SCNVector3(rw + lift.x, b.y + lift.y, b.z + lift.z), upN, CGPoint(x: 1, y: CGFloat(b.along * 1.5)))
            let r3 = add(SCNVector3(-rw + lift.x, b.y + lift.y, b.z + lift.z), upN, CGPoint(x: 0, y: CGFloat(b.along * 1.5)))
            runner += [r0, r3, r2, r0, r2, r1]
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
                       SCNGeometryElement(indices: sides, primitiveType: .triangles),
                       SCNGeometryElement(indices: runner, primitiveType: .triangles)])
        // The shared materials repeat, and the coordinates above already say how
        // many times, so every ramp draws with the same three.
        wedge.materials = [carpetTop, rampSide, sisal]
        parts.addChildNode(SCNNode(geometry: wedge))

        // Cream steps across the runner at every slice, like the cleats on a cat
        // ramp. Each is tipped to lie on the slope.
        let tilt = atan(roof / length)
        let step = SCNBox(width: 1.1, height: 0.05, length: 0.12, chamferRadius: 0.015)
        step.materials = [rampStep]
        for i in 1..<slices {
            let s = station(i)
            put(step, at: SCNVector3(0, s.y + up.y * 0.03, s.z + up.z * 0.03), tilt: SCNVector3(tilt, 0, 0), into: parts)
        }

        // Sisal rope along both top edges, from the foot up to the roof.
        let ropeMat = sisal.copy() as! SCNMaterial
        ropeMat.diffuse.contentsTransform = SCNMatrix4MakeScale(1, slope * 1.5, 1)
        let edge = SCNCylinder(radius: 0.08, height: CGFloat(slope))
        edge.heightSegmentCount = slices
        edge.radialSegmentCount = 12
        edge.materials = [ropeMat, rampSide, rampSide]
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
    /// "go under". Pieces are merged into one mesh, like the cat tree; the few
    /// that move (blinking lamps, a swinging sheet) stay as their own nodes.
    /// Nothing but the posts at lowPostX reaches below lowClearance.
    private func makeLowThing(_ world: WorldKind) -> SCNNode {
        let root = SCNNode()
        let parts = SCNNode()
        let u = lowClearance
        let px = lowPostX
        /// A node that keeps its own shape (a sphere or cone) and goes into the merge.
        func piece(_ geometry: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
            geometry.materials = [m]
            let n = SCNNode(geometry: geometry)
            n.position = p
            n.scale = scale
            parts.addChildNode(n)
            return n
        }
        switch world {
        case .city:
            // Construction scaffold: two steel frames on feet with X braces, a
            // striped board across the front, a wooden walk board on top, a rail
            // behind, a paint bucket, and amber lamps that blink.
            let steel = flatMaterial("steel", UIColor(white: 0.62, alpha: 1))
            let stripes = flatMaterial("stripes", .orange, image: Self.drawStripes()) {
                $0.diffuse.contentsTransform = SCNMatrix4MakeScale(2.5, 1, 1)
                $0.diffuse.wrapS = .repeat
            }
            let plank = flatMaterial("plank", UIColor(red: 0.80, green: 0.64, blue: 0.40, alpha: 1))
            let bucket = flatMaterial("bucket", UIColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 1))
            let top: Float = u + 0.32
            for x in [-px, px] {
                // Front pole to the walk board, back pole up to the rail.
                parts.addChildNode(box(0.09, top + 0.08, 0.09, steel, at: SCNVector3(x, (top + 0.08) / 2, -0.12)))
                parts.addChildNode(box(0.09, top + 0.28, 0.09, steel, at: SCNVector3(x, (top + 0.28) / 2, -0.72)))
                parts.addChildNode(box(0.34, 0.06, 0.95, steel, at: SCNVector3(x, 0.03, -0.42)))
                parts.addChildNode(box(0.07, 0.07, 0.7, steel, at: SCNVector3(x, top + 0.06, -0.42)))
                for s in [1, -1] as [Float] {
                    let brace = box(0.05, 0.05, 0.85, steel, at: SCNVector3(x, u - 0.25, -0.42))
                    brace.eulerAngles.x = s * 0.6
                    parts.addChildNode(brace)
                }
            }
            parts.addChildNode(box(2 * px + 0.2, 0.3, 0.16, stripes, at: SCNVector3(0, u + 0.15, -0.12)))
            parts.addChildNode(box(2 * px + 0.1, 0.06, 0.62, plank, at: SCNVector3(0, top + 0.03, -0.42)))
            parts.addChildNode(box(2 * px, 0.06, 0.06, steel, at: SCNVector3(0, top + 0.22, -0.72)))
            _ = piece(SCNCylinder(radius: 0.1, height: 0.16), bucket, at: SCNVector3(0.5, top + 0.14, -0.5))
            _ = piece(SCNCylinder(radius: 0.085, height: 0.02), flatMaterial("paint", UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1)),
                      at: SCNVector3(0.5, top + 0.225, -0.5))
            // Lamps on the front poles, kept out of the merge so they can blink.
            let amber = flatMaterial("amber", UIColor(red: 1.0, green: 0.62, blue: 0.1, alpha: 1)) {
                $0.emission.contents = UIColor(red: 0.9, green: 0.45, blue: 0.0, alpha: 1)
            }
            let lamps = SCNNode()
            for x in [-px, px] {
                let lamp = SCNSphere(radius: 0.075)
                lamp.segmentCount = 12
                lamp.materials = [amber]
                let lampNode = SCNNode(geometry: lamp)
                lampNode.position = SCNVector3(x, top + 0.17, -0.12)
                lamps.addChildNode(lampNode)
            }
            applyLook(to: lamps)
            let blink = lamps.flattenedClone()
            blink.castsShadow = false
            let dimDown = SCNAction.fadeOpacity(to: 0.3, duration: 0.45)
            dimDown.timingMode = .easeInEaseOut
            let brighten = SCNAction.fadeOpacity(to: 1, duration: 0.45)
            brighten.timingMode = .easeInEaseOut
            blink.runAction(.repeatForever(.sequence([dimDown, brighten])))
            root.addChildNode(blink)

        case .jungle:
            // A mossy log lying across two stumps, with vines winding round the
            // stumps, roots at their feet, mushrooms and a little fern on top.
            let bark = flatMaterial("bark", UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1))
            let ring = flatMaterial("ring", UIColor(red: 0.85, green: 0.68, blue: 0.45, alpha: 1))
            let moss = flatMaterial("moss", UIColor(red: 0.38, green: 0.62, blue: 0.22, alpha: 1))
            let vine = flatMaterial("vine", UIColor(red: 0.26, green: 0.50, blue: 0.18, alpha: 1))
            let leaf = flatMaterial("leaf", UIColor(red: 0.32, green: 0.60, blue: 0.26, alpha: 1))
            let cap = flatMaterial("mushroomCap", UIColor(red: 0.86, green: 0.30, blue: 0.22, alpha: 1))
            let stem = flatMaterial("mushroomStem", UIColor(red: 0.96, green: 0.92, blue: 0.80, alpha: 1))
            for x in [-px, px] {
                let stump = SCNCone(topRadius: 0.16, bottomRadius: 0.24, height: CGFloat(u))
                stump.materials = [bark, ring, bark]
                let n = SCNNode(geometry: stump)
                n.position = SCNVector3(x, u / 2, -0.4)
                parts.addChildNode(n)
                // Roots spread out from the foot, away from the lane's middle.
                let out: Float = x > 0 ? 1 : -1
                _ = piece(SCNSphere(radius: 0.1), bark, at: SCNVector3(x + out * 0.2, 0.04, -0.4), scale: SCNVector3(1.6, 0.5, 0.8))
                _ = piece(SCNSphere(radius: 0.1), bark, at: SCNVector3(x, 0.04, -0.4 + 0.22), scale: SCNVector3(0.8, 0.5, 1.5))
                _ = piece(SCNSphere(radius: 0.1), bark, at: SCNVector3(x, 0.04, -0.4 - 0.22), scale: SCNVector3(0.8, 0.5, 1.5))
                // A vine winding up the stump: three slanted loops.
                for (i, y) in ([0.35, 0.7, 1.05] as [Float]).enumerated() {
                    let radius = 0.24 - 0.08 * y / u
                    let loop = piece(SCNTorus(ringRadius: CGFloat(radius + 0.01), pipeRadius: 0.02), vine, at: SCNVector3(x, y, -0.4))
                    loop.eulerAngles = SCNVector3(0.22, Float(i) * 1.3, 0)
                }
            }
            let r: Float = 0.22
            let log = SCNCylinder(radius: CGFloat(r), height: CGFloat(2 * px + 0.5))
            log.materials = [bark, ring, ring]
            let logNode = SCNNode(geometry: log)
            logNode.eulerAngles.z = .pi / 2
            logNode.position = SCNVector3(0, u + r, -0.4)
            parts.addChildNode(logNode)
            // Moss along the top and a few patches down the front.
            for (x, sx) in [(-0.6, 0.32), (0.05, 0.42), (0.7, 0.3)] as [(Float, Float)] {
                let blob = SCNSphere(radius: 1)
                blob.segmentCount = 10
                _ = piece(blob, moss, at: SCNVector3(x, u + 2 * r - 0.02, -0.4), scale: SCNVector3(sx, 0.09, 0.2))
            }
            for x in [-0.45, 0.35] as [Float] {
                let patch = SCNSphere(radius: 1)
                patch.segmentCount = 10
                _ = piece(patch, moss, at: SCNVector3(x, u + r + 0.08, -0.4 + r - 0.02), scale: SCNVector3(0.16, 0.1, 0.05))
            }
            // Mushrooms: a stem and a flattened cap, two small and one bigger.
            for (x, s) in [(-0.38, 0.8), (-0.27, 0.6), (0.48, 1.0)] as [(Float, Float)] {
                let y = u + 2 * r
                _ = piece(SCNCylinder(radius: CGFloat(0.025 * s), height: CGFloat(0.09 * s)), stem, at: SCNVector3(x, y + 0.045 * s, -0.36))
                _ = piece(SCNSphere(radius: CGFloat(0.065 * s)), cap, at: SCNVector3(x, y + 0.09 * s, -0.36), scale: SCNVector3(1, 0.55, 1))
            }
            // A fern: five leaves fanned out from one spot, each tilting up and out.
            for i in 0..<5 {
                let holder = SCNNode()
                holder.position = SCNVector3(0.15, u + 2 * r + 0.02, -0.4)
                holder.eulerAngles.y = Float(i) * 1.26
                let blade = SCNNode(geometry: SCNSphere(radius: 1))
                blade.geometry?.materials = [leaf]
                blade.scale = SCNVector3(0.045, 0.012, 0.15)
                blade.position = SCNVector3(0, 0.03, 0.12)
                blade.eulerAngles.x = -0.55
                holder.addChildNode(blade)
                parts.addChildNode(holder)
            }

        case .house:
            // A wooden table with turned legs and a gingham cloth that drapes all
            // round with folds. On it: two plates (one with a fish), a mug, and a
            // vase of flowers. The cloth's hem is the low edge.
            let wood = flatMaterial("wood", UIColor(red: 0.62, green: 0.40, blue: 0.22, alpha: 1))
            let cloth = flatMaterial("gingham", .red, image: Self.drawGingham()) {
                $0.diffuse.wrapS = .repeat
                $0.diffuse.wrapT = .repeat
                $0.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
            }
            // The folds are the same cloth a shade darker, so they read as creases.
            let fold = flatMaterial("ginghamFold", .red, image: Self.drawGingham()) {
                $0.diffuse.wrapS = .repeat
                $0.diffuse.wrapT = .repeat
                $0.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
                $0.multiply.contents = UIColor(white: 0.84, alpha: 1)
            }
            let china = flatMaterial("china", UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1))
            let rim = flatMaterial("chinaRim", UIColor(red: 0.35, green: 0.55, blue: 0.80, alpha: 1))
            let depth = Self.lowDepth
            let hem: Float = 0.2
            let top = u + hem
            for x in [-px + 0.08, px - 0.08] {
                for z in [-0.12, -depth + 0.12] {
                    _ = piece(SCNCone(topRadius: 0.045, bottomRadius: 0.035, height: CGFloat(top)), wood, at: SCNVector3(x, top / 2, z))
                }
            }
            // The apron under the top, the top, and the cloth over it.
            for z in [-0.1, -depth + 0.1] {
                parts.addChildNode(box(2 * px - 0.3, 0.07, 0.03, wood, at: SCNVector3(0, top - 0.045, z)))
            }
            parts.addChildNode(box(2 * px, 0.08, depth, wood, at: SCNVector3(0, top + 0.04, -depth / 2)))
            parts.addChildNode(box(2 * px + 0.08, 0.025, depth + 0.08, cloth, at: SCNVector3(0, top + 0.09, -depth / 2), round: 0))
            // Hems drape over all four edges, with folds down the front and back.
            for z in [0.03, -depth - 0.03] {
                parts.addChildNode(box(2 * px + 0.08, hem, 0.02, cloth, at: SCNVector3(0, top + 0.1 - hem / 2, z), round: 0))
                for x in [-0.62, -0.21, 0.21, 0.62] as [Float] {
                    parts.addChildNode(box(0.06, hem, 0.02, fold, at: SCNVector3(x, top + 0.1 - hem / 2, z + (z > 0 ? 0.012 : -0.012)), round: 0))
                }
            }
            for x in [-(px + 0.05), px + 0.05] {
                parts.addChildNode(box(0.02, hem, depth + 0.08, cloth, at: SCNVector3(x, top + 0.1 - hem / 2, -depth / 2), round: 0))
            }
            // Corners hang a little fuller.
            for x in [-(px + 0.04), px + 0.04] {
                for z in [0.02, -depth - 0.02] {
                    parts.addChildNode(box(0.1, hem, 0.1, fold, at: SCNVector3(x, top + 0.1 - hem / 2, z), round: 0.03))
                }
            }
            // Two plates with blue rims, a fish on one.
            for (x, z) in [(-0.45, -0.32), (0.42, -0.8)] as [(Float, Float)] {
                _ = piece(SCNCylinder(radius: 0.14, height: 0.012), china, at: SCNVector3(x, top + 0.106, z))
                _ = piece(SCNTorus(ringRadius: 0.125, pipeRadius: 0.007), rim, at: SCNVector3(x, top + 0.113, z))
            }
            let salmon = flatMaterial("salmon", UIColor(red: 0.98, green: 0.60, blue: 0.48, alpha: 1))
            _ = piece(SCNSphere(radius: 0.1), salmon, at: SCNVector3(-0.46, top + 0.135, -0.32), scale: SCNVector3(1, 0.25, 0.5))
            let tail = piece(SCNBox(width: 0.07, height: 0.03, length: 0.06, chamferRadius: 0.005), salmon, at: SCNVector3(-0.34, top + 0.13, -0.32))
            tail.eulerAngles.y = 0.6
            // A mug with a handle.
            let mugMat = flatMaterial("mug", UIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))
            _ = piece(SCNCylinder(radius: 0.08, height: 0.17), mugMat, at: SCNVector3(0.0, top + 0.185, -0.62))
            let handle = piece(SCNTorus(ringRadius: 0.05, pipeRadius: 0.014), mugMat, at: SCNVector3(0.11, top + 0.19, -0.62))
            handle.eulerAngles.x = .pi / 2
            // A vase with three flowers on short stems. Everything stays under
            // 2.0 m (lowTop), where a jump clears it.
            let vaseMat = flatMaterial("vase", UIColor(red: 0.45, green: 0.72, blue: 0.85, alpha: 1))
            _ = piece(SCNSphere(radius: 0.1), vaseMat, at: SCNVector3(0.45, top + 0.2, -0.62))
            _ = piece(SCNCylinder(radius: 0.04, height: 0.07), vaseMat, at: SCNVector3(0.45, top + 0.31, -0.62))
            let stalk = flatMaterial("stalk", UIColor(red: 0.35, green: 0.62, blue: 0.30, alpha: 1))
            let petals: [(Float, Float, UIColor)] = [
                (-0.07, 0.0, UIColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1)),
                (0.0, -0.06, UIColor(red: 1.0, green: 0.55, blue: 0.68, alpha: 1)),
                (0.07, 0.03, UIColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))
            ]
            for (i, flower) in petals.enumerated() {
                let stemNode = piece(SCNCylinder(radius: 0.008, height: 0.1), stalk,
                                     at: SCNVector3(0.45 + flower.0 * 0.5, top + 0.33, -0.62 + flower.1 * 0.5))
                stemNode.eulerAngles = SCNVector3(flower.1 * 4, 0, -flower.0 * 4)
                _ = piece(SCNSphere(radius: 0.045), flatMaterial("bloom\(i)", flower.2), at: SCNVector3(0.45 + flower.0, top + 0.37, -0.62 + flower.1))
            }

        case .farm:
            // A clothesline on two T posts: a blue sheet that sways, a yellow
            // towel, a red sock, wooden pegs, a bird on one post, grass at the feet.
            let post = flatMaterial("post", UIColor(red: 0.55, green: 0.40, blue: 0.26, alpha: 1))
            let line = flatMaterial("line", UIColor(white: 0.95, alpha: 1))
            let sheet = flatMaterial("sheet", .blue, image: Self.drawSheet())
            let towel = flatMaterial("towel", .yellow, image: Self.drawTowel())
            let sock = flatMaterial("sock", UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1))
            let sockToe = flatMaterial("sockToe", UIColor(white: 0.96, alpha: 1))
            let pin = flatMaterial("pin", UIColor(red: 0.95, green: 0.85, blue: 0.6, alpha: 1))
            let grass = flatMaterial("grass", UIColor(red: 0.42, green: 0.68, blue: 0.28, alpha: 1))
            let lineY = u + 0.55
            for x in [-px, px] {
                parts.addChildNode(box(0.12, lineY + 0.14, 0.12, post, at: SCNVector3(x, (lineY + 0.14) / 2, -0.2)))
                parts.addChildNode(box(0.08, 0.08, 0.5, post, at: SCNVector3(x, lineY + 0.06, -0.2)))
                // A strut under the crossbar, and grass round the foot.
                let strut = box(0.05, 0.05, 0.3, post, at: SCNVector3(x, lineY - 0.1, -0.33))
                strut.eulerAngles.x = -0.8
                parts.addChildNode(strut)
                for (dx, dz) in [(-0.1, 0.1), (0.12, -0.08), (0.0, 0.14)] as [(Float, Float)] {
                    _ = piece(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.14), grass, at: SCNVector3(x + dx, 0.07, -0.2 + dz))
                }
            }
            let rope = SCNCylinder(radius: 0.015, height: CGFloat(2 * px))
            rope.materials = [line]
            let ropeNode = SCNNode(geometry: rope)
            ropeNode.eulerAngles.z = .pi / 2
            ropeNode.position = SCNVector3(0, lineY, -0.2)
            parts.addChildNode(ropeNode)
            // The sheet and the towel hang from the line and sway on their own
            // beat, so they're their own nodes pivoting at the rope. Swinging only
            // lifts their hems, never lowers them below the low edge.
            func hanging(_ m: SCNMaterial, width: Float, height: Float, x: Float, period: TimeInterval, swing: CGFloat) {
                let holder = SCNNode()
                holder.position = SCNVector3(x, lineY, -0.2)
                let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
                plane.materials = [m]
                let clothNode = SCNNode(geometry: plane)
                clothNode.position = SCNVector3(0, -height / 2, 0)
                holder.addChildNode(clothNode)
                let back = SCNAction.rotateBy(x: -swing, y: 0, z: 0, duration: period)
                back.timingMode = .easeInEaseOut
                let forth = SCNAction.rotateBy(x: swing, y: 0, z: 0, duration: period)
                forth.timingMode = .easeInEaseOut
                holder.eulerAngles.x = Float(swing / 2)
                holder.runAction(.repeatForever(.sequence([back, forth])))
                applyLook(to: holder)
                root.addChildNode(holder)
            }
            hanging(sheet, width: 1.0, height: lineY - u, x: -0.3, period: 1.15, swing: 0.1)
            hanging(towel, width: 0.3, height: 0.45, x: 0.43, period: 0.9, swing: 0.14)
            // A sock: the leg hanging from the line, the foot turned out.
            parts.addChildNode(box(0.1, 0.24, 0.03, sock, at: SCNVector3(0.75, lineY - 0.13, -0.2), round: 0.01))
            parts.addChildNode(box(0.14, 0.08, 0.03, sock, at: SCNVector3(0.77, lineY - 0.27, -0.2), round: 0.02))
            parts.addChildNode(box(0.05, 0.08, 0.032, sockToe, at: SCNVector3(0.82, lineY - 0.27, -0.2), round: 0.02))
            // Pegs where each thing meets the line.
            for x in [-0.72, -0.3, 0.12, 0.33, 0.53, 0.75] as [Float] {
                parts.addChildNode(box(0.04, 0.12, 0.05, pin, at: SCNVector3(x, lineY - 0.02, -0.19), round: 0.01))
            }
            // A little yellow bird perched on the right post's crossbar, out at
            // the lane's edge like the post itself.
            let bird = flatMaterial("bird", UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
            _ = piece(SCNSphere(radius: 0.05), bird, at: SCNVector3(px, lineY + 0.14, -0.2), scale: SCNVector3(1, 0.85, 1.2))
            _ = piece(SCNSphere(radius: 0.035), bird, at: SCNVector3(px, lineY + 0.2, -0.15))
            let beak = piece(SCNCone(topRadius: 0, bottomRadius: 0.012, height: 0.035),
                             flatMaterial("beak", UIColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1)), at: SCNVector3(px, lineY + 0.19, -0.11))
            beak.eulerAngles.x = -.pi / 2
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

    // MARK: - Power-ups

    // Like Subway Surfers' jetpack, coin magnet, super sneakers, and the board
    // that saves you once, but cat ones. One shows up in a mix every 14 to 20 s,
    // in place of a can of food, so it's always somewhere she can reach. Each
    // lasts a few seconds, shows a timer under the pills, and stacks with the
    // others. No score multiplier (Rex's call, 2026-10-04).

    private func powerKey(_ power: PowerUp) -> String { "power-\(power)" }

    /// A different one from last time, and not one she already has.
    private func nextPower() -> PowerUp {
        if let forced = e2ePower { return forced }
        let fresh = PowerUp.allCases.filter { $0 != lastPower && powerLeft[$0] == nil }
        let pick = fresh.randomElement() ?? PowerUp.allCases.randomElement()!
        lastPower = pick
        return pick
    }

    private func startPower(_ power: PowerUp) {
        let fresh = powerLeft[power] == nil
        powerLeft[power] = power.seconds
        powerTotal[power] = power.seconds
        cart.show(power, true)
        hud.showCallout(power.title)
        haptic(.heavy)
        puff(at: SCNVector3(visualX, height + 1.1, 0.2), count: 20, color: powerColor(power))
        testLog("power \(power)")
        if power == .rocket && fresh { takeOff() }
        showPowers()
    }

    private func endPower(_ power: PowerUp) {
        powerLeft[power] = nil
        cart.show(power, false)
        if power == .rocket && flying {
            // Coast down to the road (or onto a roof). Gravity does the rest, and
            // nothing can hurt her until a moment after she lands.
            flying = false
            jumping = true
            vy = -1
            graceLeft = max(graceLeft, graceTime + 0.5)
            testLog("rocket landing")
        }
        showPowers()
    }

    /// Everything off, for a crash or a new run.
    private func endAllPowers() {
        powerLeft.removeAll()
        powerTotal.removeAll()
        flying = false
        graceLeft = 0
        cart.hidePowerLooks()
        catNode.opacity = 1
        showPowers()
    }

    /// Counts each power-up down and ends it when its time is up. The rocket
    /// keeps her flying past its time until the road ahead is clear to land on.
    private func updatePowers(dt: Float) {
        graceLeft = max(0, graceLeft - dt)
        for (power, left) in powerLeft {
            let now = left - dt
            if now > 0 {
                powerLeft[power] = now
            } else if power == .rocket && rocketOvertime < 2.5 && !roadClear(within: landingClear) {
                // Not yet: something's on the road where she'd come down. Fly on
                // a little, up to 2.5 s; the grace after landing covers the rest.
                rocketOvertime += dt
                powerLeft[power] = 0.001
            } else {
                endPower(power)
            }
        }
        // She blinks while nothing can hurt her.
        catNode.opacity = graceLeft > 0 && Int(graceLeft * 12) % 2 == 0 ? 0.45 : 1
        showPowers()
    }

    /// Nothing to land on badly this close ahead, in any lane.
    private func roadClear(within distance: Float) -> Bool {
        !items.contains { item in
            (item.kind == .coyote || item.kind == .low || item.kind == .tree)
                && item.z > -distance && item.back < 2
        }
    }

    /// The timers under the pills, sent only when one moves a notch.
    private func showPowers() {
        let list = PowerUp.allCases.compactMap { power -> (icon: String, left: CGFloat)? in
            guard let left = powerLeft[power] else { return nil }
            return (power.icon, CGFloat(max(0, min(1, left / (powerTotal[power] ?? power.seconds)))))
        }
        let key = list.map { "\($0.icon)\(Int($0.left * 40))" }.joined()
        guard key != powerShown else { return }
        powerShown = key
        hud.setPowers(list)
    }

    /// Fizz Rocket takes off: up she goes, the bottle gives up, and a trail of
    /// food appears in the sky.
    private func takeOff() {
        flying = true
        rocketOvertime = 0
        jumping = false
        platform = nil
        duckTimer = 0
        jumpBuffer = 0
        vy = 0
        chaseTimer = 0
        // Fly long enough to pass everything already on the road (a mix reaches
        // well past where it appears), so she comes down on clear road: 5 s, or
        // up to 9 s when the road is busy or she's slow.
        let speed = runSpeed()
        let farthest = items.filter { $0.kind == .coyote || $0.kind == .low || $0.kind == .tree }
            .map { -$0.back }.max() ?? 0
        let seconds = min(9, max(PowerUp.rocket.seconds, (farthest + 8) / speed))
        powerLeft[.rocket] = seconds
        powerTotal[.rocket] = seconds
        spawnSkyTrail(distance: min(skyTrailLength, speed * seconds))
    }

    /// The rocket's reward: a winding line of food at flying height, from just
    /// ahead to about where she'll land. It moves over a lane every few cans,
    /// so she steers through the sky to eat it all.
    private func spawnSkyTrail(distance: Float) {
        var trailLane = lane
        var run = 0
        var ahead: Float = 16
        while ahead < distance {
            let item = addItem(.food, lane: trailLane, z: -ahead, high: true)
            item.sky = true
            item.baseY = flightHeight + 0.35
            item.node.position.y = item.baseY
            // They pop in rather than appear.
            item.node.scale = SCNVector3(0.2, 0.2, 0.2)
            item.node.runAction(.scale(to: 1, duration: 0.3), forKey: "pop")
            run += 1
            if run >= 5 {
                run = 0
                trailLane = trailLane == 1 ? (Bool.random() ? 0 : 2) : 1
            }
            ahead += skyFoodGap
        }
    }

    /// Nine Lives: instead of crashing she loses the halo. Whatever she ran into
    /// is knocked out of the way (or, for a tree, she bounds up onto it), and
    /// for a moment nothing can hurt her. False if she has no life to spare.
    private func saveLife() -> Bool {
        guard state == .running, powerLeft[.lives] != nil else { return false }
        endPower(.lives)
        graceLeft = graceTime
        chaseTimer = 0
        stumbleGrace = 0.4
        testLog("saved by nine lives")
        for item in items where (item.kind == .coyote || item.kind == .low)
                && (item.lane == lane || item.lane == bodyLane) && item.z > -3 && item.back < 2 {
            item.hit = true
            item.node.isHidden = true
            puff(at: SCNVector3(laneX(item.lane), 0.8, item.z), count: 16, color: UIColor(white: 1, alpha: 0.9))
        }
        if let tree = items.first(where: { $0.kind == .tree && $0.lane == lane && overlapsCat($0) }) {
            popOnto(tree)
        }
        hud.showCallout("Saved!")
        haptic(.heavy)
        puff(at: SCNVector3(visualX, height + 1.6, 0.2), count: 24, color: powerColor(.lives))
        return true
    }

    /// Up onto a tree's top in one bound, for when she can't crash into it.
    private func popOnto(_ tree: TrackItem) {
        platform = tree
        height = tree.topAtCat
        vy = 0
        jumping = false
        landSquash = 1
        puff(at: SCNVector3(visualX, height + 0.2, 0.2), count: 12, color: UIColor(white: 1, alpha: 0.9))
    }

    private func powerColor(_ power: PowerUp) -> UIColor {
        switch power {
        case .rocket: return UIColor(red: 0.55, green: 0.86, blue: 1.0, alpha: 1)
        case .magnet: return UIColor(red: 1.0, green: 0.38, blue: 0.40, alpha: 1)
        case .pounce: return UIColor(red: 0.52, green: 0.92, blue: 0.56, alpha: 1)
        case .lives: return UIColor(red: 1.0, green: 0.84, blue: 0.36, alpha: 1)
        }
    }

    /// A power-up on the road: its model turning slowly inside a soft colored
    /// bubble, bobbing, so it reads as something special next to a can of food.
    private func makePowerUp(_ power: PowerUp) -> SCNNode {
        let node = SCNNode()
        let bob = SCNNode()
        bob.position = SCNVector3(0, 0.8, 0)
        node.addChildNode(bob)
        let model = powerModel(power)
        bob.addChildNode(model)
        model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2.4)))
        bob.runAction(.repeatForever(.sequence([
            .moveBy(x: 0, y: 0.16, z: 0, duration: 0.5),
            .moveBy(x: 0, y: -0.16, z: 0, duration: 0.5)
        ])))

        let bubble = SCNSphere(radius: 0.6)
        bubble.segmentCount = 28
        let skin = SCNMaterial()
        skin.diffuse.contents = powerColor(power)
        skin.lightingModel = .constant
        skin.transparency = 0.22
        skin.blendMode = .alpha
        skin.writesToDepthBuffer = false
        // A soap-bubble rim: clear in the middle, brighter and shifting through
        // faint rainbow tints toward the edge, where the sphere turns away from
        // the camera. applyLook keeps this surface modifier and adds the fog.
        skin.shaderModifiers = [.surface: Self.bubbleModifier]
        bubble.materials = [skin]
        let shell = SCNNode(geometry: bubble)
        shell.castsShadow = false
        shell.renderingOrder = 20
        bob.addChildNode(shell)
        // The bubble breathes a little.
        let grow = SCNAction.scale(to: 1.06, duration: 0.7)
        grow.timingMode = .easeInEaseOut
        let shrink = SCNAction.scale(to: 0.97, duration: 0.7)
        shrink.timingMode = .easeInEaseOut
        shell.runAction(.repeatForever(.sequence([grow, shrink])))

        applyLook(to: node)
        let shadow = shadowNode(width: 0.9, length: 0.7)
        shadow.name = "shadow"
        node.addChildNode(shadow)
        return node
    }

    private func powerModel(_ power: PowerUp) -> SCNNode {
        let model = SCNNode()
        func shiny(_ color: UIColor, glow: CGFloat = 0.25) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = color
            m.emission.intensity = glow
            m.specular.contents = UIColor(white: 1, alpha: 1)
            m.shininess = 0.6
            m.lightingModel = .blinn
            return m
        }
        func add(_ geometry: SCNGeometry, _ material: SCNMaterial, at p: SCNVector3) -> SCNNode {
            geometry.materials = [material]
            let n = SCNNode(geometry: geometry)
            n.position = p
            model.addChildNode(n)
            return n
        }
        switch power {
        case .rocket:
            // A La Croix can with a red nose cone and fins: a sparkling-water rocket.
            let tilt = SCNNode()
            tilt.eulerAngles.z = 0.35
            model.addChildNode(tilt)
            let wrap = shiny(UIColor(red: 0.82, green: 0.93, blue: 0.99, alpha: 1), glow: 0.15)
            wrap.diffuse.contents = UIImage(named: "canWrap") ?? UIColor(red: 0.82, green: 0.93, blue: 0.99, alpha: 1)
            let lid = shiny(UIColor(white: 0.86, alpha: 1))
            let can = SCNCylinder(radius: 0.17, height: 0.5)
            can.materials = [wrap, lid, lid]
            tilt.addChildNode(SCNNode(geometry: can))
            let red = shiny(UIColor(red: 0.95, green: 0.26, blue: 0.32, alpha: 1))
            let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.17, height: 0.24))
            cone.geometry?.materials = [red]
            cone.position = SCNVector3(0, 0.37, 0)
            tilt.addChildNode(cone)
            for i in 0..<3 {
                let a = Float(i) * 2 * .pi / 3
                let fin = SCNNode(geometry: SCNBox(width: 0.025, height: 0.2, length: 0.15, chamferRadius: 0.01))
                fin.geometry?.materials = [red]
                fin.position = SCNVector3(sin(a) * 0.19, -0.2, cos(a) * 0.19)
                fin.eulerAngles.y = a
                tilt.addChildNode(fin)
            }
            let puffMat = shiny(UIColor(white: 1, alpha: 1), glow: 0.6)
            for (i, r) in [0.09, 0.07, 0.05].enumerated() {
                let b = SCNNode(geometry: SCNSphere(radius: CGFloat(r)))
                b.geometry?.materials = [puffMat]
                b.position = SCNVector3(Float(i) * 0.04 - 0.04, -0.36 - Float(i) * 0.1, 0)
                tilt.addChildNode(b)
            }
        case .magnet:
            // A big red horseshoe magnet with silver tips.
            let shoe = UIBezierPath()
            shoe.addArc(withCenter: .zero, radius: 0.27, startAngle: 0, endAngle: .pi, clockwise: true)
            shoe.addLine(to: CGPoint(x: -0.27, y: -0.2))
            shoe.addLine(to: CGPoint(x: -0.13, y: -0.2))
            shoe.addLine(to: CGPoint(x: -0.13, y: 0))
            shoe.addArc(withCenter: .zero, radius: 0.13, startAngle: .pi, endAngle: 0, clockwise: false)
            shoe.addLine(to: CGPoint(x: 0.13, y: -0.2))
            shoe.addLine(to: CGPoint(x: 0.27, y: -0.2))
            shoe.close()
            let shape = SCNShape(path: shoe, extrusionDepth: 0.14)
            shape.chamferRadius = 0.02
            _ = add(shape, shiny(UIColor(red: 0.92, green: 0.16, blue: 0.2, alpha: 1)), at: SCNVector3(0, 0.05, 0))
            let silver = shiny(UIColor(white: 0.92, alpha: 1), glow: 0.3)
            for x: Float in [-0.2, 0.2] {
                _ = add(SCNBox(width: 0.14, height: 0.09, length: 0.15, chamferRadius: 0.015), silver,
                        at: SCNVector3(x, -0.19, 0))
            }
        case .pounce:
            // A coil spring with a pink paw print on top.
            let steel = shiny(UIColor(red: 0.6, green: 0.88, blue: 0.62, alpha: 1))
            for i in 0..<6 {
                let ring = add(SCNTorus(ringRadius: 0.2, pipeRadius: 0.035), steel,
                               at: SCNVector3(0, -0.3 + Float(i) * 0.1, 0))
                ring.eulerAngles.z = i % 2 == 0 ? 0.16 : -0.16
            }
            let pink = shiny(UIColor(red: 1.0, green: 0.62, blue: 0.72, alpha: 1), glow: 0.3)
            _ = add(SCNCylinder(radius: 0.2, height: 0.06), shiny(UIColor(white: 0.97, alpha: 1)), at: SCNVector3(0, 0.29, 0))
            _ = add(SCNCylinder(radius: 0.08, height: 0.04), pink, at: SCNVector3(0, 0.33, 0.03))
            for (x, z) in [(-0.1, -0.06), (-0.035, -0.12), (0.035, -0.12), (0.1, -0.06)] as [(Float, Float)] {
                _ = add(SCNCylinder(radius: 0.034, height: 0.04), pink, at: SCNVector3(x, 0.33, z))
            }
        case .lives:
            // A pink heart with a gold halo over it.
            let heart = UIBezierPath()
            heart.move(to: CGPoint(x: 0, y: -0.26))
            heart.addCurve(to: CGPoint(x: -0.26, y: 0.08), controlPoint1: CGPoint(x: -0.1, y: -0.15),
                           controlPoint2: CGPoint(x: -0.26, y: -0.06))
            heart.addArc(withCenter: CGPoint(x: -0.13, y: 0.08), radius: 0.13, startAngle: .pi, endAngle: 0, clockwise: false)
            heart.addArc(withCenter: CGPoint(x: 0.13, y: 0.08), radius: 0.13, startAngle: .pi, endAngle: 0, clockwise: false)
            heart.addCurve(to: CGPoint(x: 0, y: -0.26), controlPoint1: CGPoint(x: 0.26, y: -0.06),
                           controlPoint2: CGPoint(x: 0.1, y: -0.15))
            heart.close()
            let shape = SCNShape(path: heart, extrusionDepth: 0.13)
            shape.chamferRadius = 0.03
            _ = add(shape, shiny(UIColor(red: 1.0, green: 0.36, blue: 0.52, alpha: 1)), at: SCNVector3(0, -0.04, 0))
            let ring = add(SCNTorus(ringRadius: 0.17, pipeRadius: 0.03), shiny(UIColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 1), glow: 0.7),
                           at: SCNVector3(0, 0.32, 0))
            ring.eulerAngles.x = 0.25
        }
        return model
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
        // Mist from the nozzle: a little "psst" at the top of each hop while it
        // chases, a long one when it has her. Off until then; see updateChase.
        let spray = SCNParticleSystem()
        spray.particleImage = puffImage
        spray.birthRate = 0
        spray.particleLifeSpan = 0.45
        spray.particleLifeSpanVariation = 0.1
        spray.particleSize = 0.09
        spray.particleSizeVariation = 0.04
        spray.particleColor = UIColor(red: 0.80, green: 0.93, blue: 1.0, alpha: 0.75)
        spray.emittingDirection = SCNVector3(0, 0, -1)
        spray.spreadingAngle = 16
        spray.particleVelocity = 3.2
        spray.particleVelocityVariation = 0.8
        spray.blendMode = .alpha
        spray.isLocal = false
        spray.propertyControllers = [.opacity: Self.fadeOutController()]
        let mistNode = SCNNode()
        mistNode.position = SCNVector3(0, 0.99, -0.42)
        mistNode.addParticleSystem(spray)
        model.addChildNode(mistNode)
        mist = spray
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
        cart.didStumble()
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
        shakeCamera(amp: 0.12, time: 0.24)
        fovKick = 2
    }

    /// Second stumble: the bottle catches up and sprays her. It's a crash.
    private func caught() {
        if e2eGod {
            chaseTimer = chaseTime
            return
        }
        if saveLife() { return }
        sprayed = true
        crash()
        // A burst of mist over her head, and the nozzle keeps spraying a moment.
        puff(at: SCNVector3(visualX, height + 1.5, 0.3), count: 40,
             color: UIColor(red: 0.78, green: 0.92, blue: 1.0, alpha: 0.95))
        mistLeft = 0.9
        mist?.birthRate = 220
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
        // The mist turns itself off once its moment is up.
        if mistLeft > 0 {
            mistLeft -= dt
            if mistLeft <= 0 { mist?.birthRate = 0 }
        }
        bottle.isHidden = bottleZ > bottleGone
        guard !bottle.isHidden else { return }
        // 0 on the road, 1 at the top of a hop.
        let hopPhase: Float = sprayed ? 0 : abs(sin(bottleClock * 9))
        let hop = sprayed ? 0.25 : hopPhase * 0.32
        bottle.position = SCNVector3(bottleX, hop, bottleZ)
        // Leans over her when it catches her, nozzle down at her head.
        bottle.eulerAngles.z = sprayed ? 0.45 : 0
        let model = bottle.childNode(withName: "model", recursively: false)
        // Turned side-on, nozzle aimed in at her from her right, rocking as it hops.
        model?.eulerAngles = SCNVector3(sprayed ? 0 : -0.12 + sin(bottleClock * 9) * 0.08, 1.0,
                                        sprayed ? 0 : sin(bottleClock * 4.5) * 0.1)
        // Squashes flat as it lands and stretches at the top of each hop, like a
        // soft plastic bottle; when it has her it pumps with each squeeze.
        let ground = 1 - hopPhase
        let squish = ground * ground * 0.15
        let pump: Float = sprayed ? 0.04 * sin(bottleClock * 18) : 0
        model?.scale = SCNVector3(0.95 * (1 + squish + pump), 0.95 * (1 - squish - pump), 0.95 * (1 + squish + pump))
        // A short "psst" each time it reaches the top of a hop.
        if !sprayed && lastHop < 0.97 && hopPhase >= 0.97 {
            mistLeft = max(mistLeft, 0.07)
            mist?.birthRate = 90
        }
        lastHop = hopPhase
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
            if item.kind == .food || item.kind == .power {
                if item.pulled {
                    if item.z >= -0.8 { collect(item) }
                    continue
                }
                guard item.lane == lane, prevZ < 0, item.z >= 0 else { continue }
                // Food in the air is only reached high in a jump (or from a tree roof).
                if item.high && height < airFoodReach { continue }
                // The rocket's trail is only reached flying, and the road is out of
                // reach from up there.
                if item.sky && height < flightHeight - 1.2 { continue }
                if flying && !item.sky { continue }
                collect(item)
                continue
            }
            // Up on the rocket everything passes under her, and right after a
            // landing or a saved life nothing can hurt her.
            if flying || graceLeft > 0 { continue }
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
            if item.kind == .low && height > lowTop { continue }
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
        // The rocket flies over trees; she only gets on one once she lands.
        if flying { return }
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
        if graceLeft > 0 {
            // She can't crash right now, so she bounds up onto it instead.
            if heading { popOnto(item) }
            return
        }
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

    /// A can of food or a power-up reaches her. A can just disappears, with a
    /// light buzz and the food pill's pulse (Rex's call, 2026-10-09: he didn't
    /// like the hop into her lap). A power-up still hops into her lap.
    private func collect(_ item: TrackItem) {
        items.removeAll { $0 === item }
        if let power = item.power {
            flyAway(item)
            startPower(power)
            return
        }
        recycle(item)
        food += 1
        haptic(.light)
    }

    /// The power-up she grabbed hops up, spins once, and shrinks into her
    /// lap instead of vanishing. Its node stays in the scene for that quarter
    /// second, off the items list so the rules ignore it, then updateCollected
    /// puts it back in its pool.
    private func flyAway(_ item: TrackItem) {
        let node = item.node
        node.childNode(withName: "shadow", recursively: false)?.isHidden = true
        node.removeAction(forKey: "pop")
        let time = TimeInterval(collectTime)
        let up = SCNAction.moveBy(x: 0, y: 0.5, z: 0, duration: time * 0.4)
        up.timingMode = .easeOut
        let intoLap = SCNAction.move(to: SCNVector3(visualX, height + 0.9, 0.3), duration: time * 0.6)
        intoLap.timingMode = .easeIn
        node.runAction(.group([
            .sequence([up, intoLap]),
            .rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: time),
            .sequence([.scale(to: 1.25, duration: time * 0.35), .scale(to: 0.05, duration: time * 0.65)])
        ]), forKey: "collect")
        collected.append(Collected(node: node, left: collectTime + 0.05))
    }

    private func updateCollected(dt: Float) {
        guard !collected.isEmpty else { return }
        for c in collected {
            c.left -= dt
            if c.left <= 0 { returnToPool(c.node) }
        }
        collected.removeAll { $0.left <= 0 }
    }

    /// Back to its pool with every trace of the collect animation undone, so the
    /// next addItem gets a plain node.
    private func returnToPool(_ node: SCNNode) {
        node.removeAction(forKey: "collect")
        node.removeFromParentNode()
        node.scale = SCNVector3(1, 1, 1)
        node.eulerAngles = SCNVector3Zero
        node.opacity = 1
        if let key = node.name {
            itemPool[key, default: []].append(node)
        }
    }

    private func crash() {
        if saveLife() { return }
        if e2ePilot || e2eSwipes {
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
        endAllPowers()
        hideDuckHint()
        dust.birthRate = 0
        if Choices.haptics {
            DispatchQueue.main.async {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        hud.flashWhite()
        hud.clearLines()
        shakeCamera(amp: 0.26, time: 0.42)
        fovKick = 4
        // A silly tip-over, not a punishment: a hop, a roll onto her side with a
        // little settle, and cartoon stars circling over her head.
        let roll = SCNAction.rotateBy(x: 0, y: 0, z: tilt >= 0 ? 1.0 : -1.0, duration: 0.22)
        roll.timingMode = .easeOut
        let settleBack = SCNAction.rotateBy(x: 0, y: 0, z: tilt >= 0 ? -0.1 : 0.1, duration: 0.14)
        settleBack.timingMode = .easeInEaseOut
        let hop = SCNAction.moveBy(x: 0, y: 0.5, z: 0, duration: 0.12)
        hop.timingMode = .easeOut
        let drop = SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.18)
        drop.timingMode = .easeIn
        catNode.runAction(.group([
            .sequence([roll, settleBack]),
            .sequence([hop, drop, .moveBy(x: 0, y: 0.08, z: 0, duration: 0.07), .moveBy(x: 0, y: -0.08, z: 0, duration: 0.07)])
        ]), forKey: "tip")
        starsNode.isHidden = false
        starsClock = 0
        starsAngle = 0
        // Place them now, so the crash frame doesn't show last time's ring.
        updateStars(dt: 0)
        puff(at: SCNVector3(visualX, height + 0.3, 0.2), count: 16, color: UIColor(white: 0.95, alpha: 0.9))
        let newBest = score > bestScore
        if newBest {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: Self.bestKey)
        }
        // Real time survived, without the CATCART_TIME test head start.
        let seconds = Int(timeAlive - e2eStartTime)
        hud.showDead(score: score, food: food, seconds: seconds, best: bestScore, newBest: newBest)
    }

    /// Starts a camera shake that dies out over `time` seconds; updateCamera
    /// applies it. A new shake replaces the one running.
    private func shakeCamera(amp: Float = 0.2, time: Float = 0.32) {
        shakeAmp = amp
        shakeTotal = time
        shakeLeft = time
    }

    /// Builds the puff and ring effects once. Each emitter runs all the
    /// time at a birth rate of 0, and a puff turns it up for a twentieth of a
    /// second. Nothing here is built mid-run.
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
        // Landing rings: a soft ring picture lying on the floor that spreads and fades.
        let ringMaterial = SCNMaterial()
        ringMaterial.diffuse.contents = Self.drawRing()
        ringMaterial.lightingModel = .constant
        ringMaterial.blendMode = .alpha
        ringMaterial.writesToDepthBuffer = false
        Self.smoothSampling(ringMaterial.diffuse)
        for _ in 0..<3 {
            let node = SCNNode(geometry: groundPlane(width: 1.6, length: 1.6, material: ringMaterial))
            node.renderingOrder = 6
            node.castsShadow = false
            node.isHidden = true
            applyLook(to: node)
            scene.rootNode.addChildNode(node)
            rings.append(Ring(node: node))
        }
    }

    /// A ring that spreads on the floor where she landed. `strength` (0 to 1) is
    /// how hard she came down: a bigger, bolder ring for a slam.
    private func landingRing(at point: SCNVector3, strength: Float) {
        guard !rings.isEmpty else { return }
        let r = rings[nextRing]
        nextRing = (nextRing + 1) % rings.count
        r.node.position = point
        r.node.isHidden = false
        r.node.scale = SCNVector3(0.3, 1, 0.3)
        r.strength = strength
        r.left = ringTime
    }

    /// Spreads and fades each live ring, and slides it back with the road.
    private func updateRings(dt: Float, dz: Float) {
        for r in rings where r.left > 0 {
            r.left -= dt
            r.node.position.z += dz
            if r.left <= 0 {
                r.node.isHidden = true
                continue
            }
            let t = 1 - r.left / ringTime
            let s = 0.3 + (1.1 + 0.5 * r.strength) * t
            r.node.scale = SCNVector3(s, 1, s)
            r.node.opacity = CGFloat((1 - t) * (1 - t) * (0.5 + 0.4 * r.strength))
        }
    }

    /// Fires the next puff emitter in turn. Four is plenty: a puff lasts under half
    /// a second, and at most a landing, a lane-change scuff, and a power-up happen
    /// that close together.
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
        guard Choices.haptics else { return }
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    // MARK: - Input

    // Touches arrive on the main thread. We turn them into intents and let the
    // render thread act on them at the start of the next frame.

    func touchBegan(at point: CGPoint) {
        swipeStart = point
        swipeLast = point
        swipeConsumed = false
        enqueue(.tap)
    }

    func touchMoved(to point: CGPoint, minimum: CGFloat) {
        swipeLast = point
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
            enqueue(.lift(swipeLast ?? swipeStart!))
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
            case (.ready, .lift(let point)):
                // The menu button and the menu's controls; anywhere else
                // starts the run.
                switch hud.homeTap(at: point) {
                case nil:
                    startRun()
                case .openMenu?:
                    hud.setMenuOpen(true)
                    tick()
                case .closeMenu?:
                    hud.setMenuOpen(false)
                case .toggleSound?:
                    Choices.sound.toggle()
                    hud.setSwitches(sound: Choices.sound, haptics: Choices.haptics)
                    tick()
                case .toggleHaptics?:
                    Choices.haptics.toggle()
                    hud.setSwitches(sound: Choices.sound, haptics: Choices.haptics)
                    tick()
                case .ignore?:
                    break
                case let choice?:
                    pick(choice)
                }
            case (.ready, .left):
                // With the menu open, a swipe flips through the cats.
                if hud.menuOpen { pick(.cat(-1)) }
            case (.ready, .right):
                if hud.menuOpen { pick(.cat(1)) }
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
                // Up on the rocket there's nothing to jump off.
                if flying { break }
                if !jump() { jumpBuffer = jumpBufferTime }
            case (.running, .stumble):
                stumble(bounceBack: false)
            case (.running, .power(let power)):
                startPower(power)
            case (.running, .down):
                if flying { break }
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
        // Flying, she's above every tree, so a lane change is only a lane change.
        let beside = flying ? nil : items.filter { $0.kind == .tree && $0.lane == next && overlapsCat($0) }
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
        cart.didChangeLane(delta)
        if height - floorY < 0.1 {
            // A scuff of dust off the wheels she pushes away from.
            puff(at: SCNVector3(visualX - Float(delta) * 0.55, floorY + 0.08, 0.35), count: 5,
                 color: UIColor(white: 1, alpha: 0.45))
        }
        tick()
    }

    /// Returns false if she can't jump yet (still in the air).
    @discardableResult
    private func jump() -> Bool {
        guard !jumping, height - floorY < 0.1 else { return false }
        // Jumping pops her straight out of a duck.
        duckTimer = 0
        jumping = true
        vy = jumpSpeed
        cart.didJump()
        // A small widening of the view as she leaves the ground.
        fovKick = 2.2
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
        untilPower = e2ePowerEvery ?? firstPower
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
        collected.forEach { returnToPool($0.node) }
        collected.removeAll()
        for r in rings {
            r.left = 0
            r.node.isHidden = true
        }
        starsNode.isHidden = true
        shakeLeft = 0
        fovKick = 0
        landVy = 0
        mistLeft = 0
        mist?.birthRate = 0
        lastHop = 0
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
        endAllPowers()
        lastPower = nil
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
    private var updateMs = 0.0
    private var renderMs = 0.0
    private var updateEnd: CFTimeInterval = 0

    init(enabled: Bool) {
        self.enabled = enabled
    }

    mutating func note(_ event: String) {
        guard enabled else { return }
        events.append(event)
    }

    /// Our own game code for the frame, then SceneKit's drawing work after it.
    /// A hitch with a long update is our code; a long render is the graphics side.
    mutating func updateDone(since start: CFTimeInterval) {
        guard enabled else { return }
        updateEnd = CACurrentMediaTime()
        updateMs = (updateEnd - start) * 1000
    }

    mutating func renderDone() {
        guard enabled else { return }
        renderMs = (CACurrentMediaTime() - updateEnd) * 1000
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
            emit(String(format: "CATCART hitch %.0f ms at run %.1f s (prev frame: update %.1f ms, render %.1f ms)",
                        ms, runTime, updateMs, renderMs) + cause)
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

    /// A star with `points` points: four for glints, five with an
    /// outline for the cartoon stars over her head after a crash.
    static func drawStar(points: Int, color: UIColor, outline: UIColor?) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            let center = CGPoint(x: 32, y: 32)
            let path = UIBezierPath()
            let inner: CGFloat = points == 4 ? 0.28 : 0.46
            for i in 0..<(points * 2) {
                let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
                let r: CGFloat = i % 2 == 0 ? 28 : 28 * inner
                let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                if i == 0 {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
            }
            path.close()
            path.lineJoinStyle = .round
            color.setFill()
            path.fill()
            if let outline {
                outline.setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }
    }

    /// A soft ring for the landing effect: clear in the middle, white at about
    /// three quarters of the radius, clear again at the edge.
    static func drawRing() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 1).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.55, 0.76, 0.96])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                             endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    /// A yellow towel with white bands, for the farm clothesline.
    static func drawTowel() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 128)).image { ctx in
            UIColor(red: 0.98, green: 0.84, blue: 0.36, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 128))
            UIColor(white: 1, alpha: 0.9).setFill()
            for y in [22, 36, 92, 106] {
                ctx.fill(CGRect(x: 0, y: y, width: 64, height: 6))
            }
            UIColor(red: 0.86, green: 0.66, blue: 0.22, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 120, width: 64, height: 8))
        }
    }
}
