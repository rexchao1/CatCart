import SceneKit
import UIKit

// The player: Rex's kitten sitting in a La Croix 12-pack box on four wheels.
//
// The box is built here from SceneKit boxes and cylinders, wrapped in the
// textures from scripts/make_cart_textures.py. The kitten is a Blender model
// (Models/cat_kitten.scn, from scripts/blender/make_kitten_v3.py through
// scripts/build_kitten.sh) with separate head, ears, eyes, and tail nodes, so
// we can make her twitch and blink in code. Her fur is built into the model.
//
// Her life comes from little springs (see `MotionSpring` below), not canned clips.
// GameScene tells the cart what is happening each frame (`CartMotion`) and
// when something happens (a jump, a landing, a lane change), and each part
// chases a goal with some bounce: ears pin back in a jump and pop up when she
// lands, her head looks where she is going, her tail streams against the
// motion and whips on a turn, and the box dips on its wheels when she lands.
//
// The power-up looks live here too: springs under the wheels, a halo, a magnet
// over her head, and fizz from the cans. GameScene turns them on and off.
//
// Coordinates: meters, +y up. She faces -z, away from the run camera, so +x is
// her right and the screen's right. A positive turn about x lifts her nose.
// The node's origin is on the ground under the middle of the box.

/// What the cart is doing this frame. GameScene fills one in and hands it to
/// `KittenCart.update`. Everything is in meters and seconds, before the cart's
/// own scale.
struct CartMotion {
    /// Road speed, for the wheels and the wind in her ears.
    var speed: Float = 0
    /// Wheels on something (road, roof, or ramp): they spin and the box rattles.
    var rolling = true
    /// The cart's lean from GameScene (radians), for her head.
    var tilt: Float = 0
    /// How far she still has to slide to her lane, in meters, + toward +x. Her
    /// head and body lean into it, so she looks where she is going.
    var steer: Float = 0
    var ducking = false
    /// The home screen: curious head tilts, glances, and slow blinks.
    var idle = false
    /// Off the ground in a jump or a fall.
    var airborne = false
    /// Up is positive, in m/s. Drives the stretch, the head, and the tail.
    var verticalSpeed: Float = 0
    /// The Fizz Rocket is carrying her.
    var flying = false
    /// She crashed: ears back, eyes shut, tail down.
    var crashed = false
}

/// A damped spring: a value that chases a goal with some bounce. `kick` gives
/// it a shove, like a landing jolting her head. Stiffness is how hard it pulls
/// back, damping how fast the bounce dies out. Stepped with a short dt (the
/// cart caps it at 1/30 s), stiffness up to about 1000 stays stable.
struct MotionSpring {
    var value: Float = 0
    var velocity: Float = 0
    var stiffness: Float
    var damping: Float

    init(stiffness: Float, damping: Float) {
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(toward goal: Float, dt: Float) {
        velocity += ((goal - value) * stiffness - velocity * damping) * dt
        value += velocity * dt
    }

    mutating func kick(_ amount: Float) {
        velocity += amount
    }
}

final class KittenCart {

    let node = SCNNode()
    /// Everything below is built at real size, then scaled up so she reads well
    /// from the run camera.
    private let body = SCNNode()
    /// The box, the cans, and the kitten ride in here, on top of the wheels. It
    /// dips, rolls, and rattles on its own little suspension.
    private let box = SCNNode()
    static let scale: Float = 1.25
    static let tailLift: Float = 0.8

    private let boxWidth: CGFloat = 1.3
    private let boxDepth: CGFloat = 0.95
    private let boxHeight: CGFloat = 0.5
    private let boxBottom: Float = 0.27
    private let wall: CGFloat = 0.035
    private let wheelRadius: Float = 0.15
    /// Where her bottom rests: the rim is 0.42 m above this.
    private var seatY: Float { boxBottom + Float(boxHeight) - 0.42 }

    private var wheels: [SCNNode] = []
    private var head: SCNNode?
    private var headRest = SCNVector3Zero
    private var kitten: SCNNode?
    /// How far she has sunk into the box: 0 sitting up, 1 ducked. It's a spring,
    /// so she pops back up a little past sitting and settles.
    private var duck: Float = 0
    private var duckSpeed: Float = 0
    /// Ducked, her eyes sit at the rim. She sinks only as far as the box floor
    /// (any lower and her bottom shows under the box), and the rest comes from
    /// squashing her body, which the box walls hide. Her head and tail ride in
    /// holders that undo the squash, so they keep their shape.
    static let duckSink: Float = 0.08
    static let duckSquash: Float = 0.42
    private var kittenBody: SCNNode?
    private var unsquashed: [SCNNode] = []

    /// True when the Blender kitten loaded. False means a simple stand-in is showing.
    private(set) var hasModel = false

    /// Seconds since she was built, for the idle wiggles.
    private var clock: Float = 0
    /// The home screen's curious head tilt, eased in and out.
    private var idleTilt: Float = 0
    private var eyes: [SCNNode] = []
    /// Seconds to the next blink, and how far into a blink she is.
    private var blinkWait: Float = 2
    private var blinkClock: Float = -1
    private var blinkLength: Float = 0.16
    /// Eyes squeezed shut after a crash, so we know to open them again.
    private var eyesSqueezed = false

    // The springs that make her move. Each one chases a goal set in update.
    /// Her body stretches tall going up and tucks coming down, as a scale on y.
    private var stretch = MotionSpring(stiffness: 220, damping: 16)
    /// The whole kitten rocking back on takeoff and curling forward to land.
    private var lean = MotionSpring(stiffness: 140, damping: 14)
    /// The kitten leaning sideways into a lane change.
    private var kittenRoll = MotionSpring(stiffness: 160, damping: 14)
    /// Head: where she looks (yaw, + is to her left), nose up or down (pitch),
    /// and a little bob up and down that lags the cart.
    private var headYaw = MotionSpring(stiffness: 130, damping: 13)
    private var headPitch = MotionSpring(stiffness: 160, damping: 13)
    private var headBob = MotionSpring(stiffness: 420, damping: 16)
    /// Ears, left then right: pinned back (pitch), swiveled (yaw), and the
    /// quick sideways flick. Loose damping so they pop.
    private var earPitch = [MotionSpring(stiffness: 320, damping: 13), MotionSpring(stiffness: 320, damping: 13)]
    private var earSwivel = [MotionSpring(stiffness: 120, damping: 12), MotionSpring(stiffness: 120, damping: 12)]
    private var earFlick = [MotionSpring(stiffness: 520, damping: 15), MotionSpring(stiffness: 520, damping: 15)]
    private var earFlickWait: [Float] = [2.5, 4]
    /// Tail: lagging behind the motion up and down (pitch) and side to side
    /// (yaw), with the tip trailing the tail a beat later.
    private var tailPitch = MotionSpring(stiffness: 90, damping: 7)
    private var tailYaw = MotionSpring(stiffness: 60, damping: 5)
    private var tipPitch = MotionSpring(stiffness: 170, damping: 9)
    private var tipYaw = MotionSpring(stiffness: 150, damping: 9)
    /// The box on its wheels: dip (meters), roll, pitch, and yaw (radians).
    private var suspension = MotionSpring(stiffness: 420, damping: 18)
    private var boxRoll = MotionSpring(stiffness: 260, damping: 12)
    private var boxPitch = MotionSpring(stiffness: 300, damping: 14)
    private var boxYaw = MotionSpring(stiffness: 200, damping: 12)
    /// Home screen glances: seconds to the next one, how long it holds, and
    /// where it looks. The ear on that side turns toward it.
    private var glanceWait: Float = 3
    private var glanceHold: Float = 0
    private var glanceYaw: Float = 0
    private var glancePitch: Float = 0

    private var tail: SCNNode?
    private var tailRest = SCNVector3Zero
    private var tailTip: SCNNode?
    private var tailTipRest = SCNVector3Zero
    private var ears: [SCNNode] = []
    private var earRests: [SCNVector3] = []

    // Power-up looks. See GameScene's PowerUp for what each one does.
    private let springs = SCNNode()
    private var springsOn = false
    /// How far the springs lift the box right now, eased.
    private var springLift: Float = 0
    /// Fully stretched, the springs hold the box this far up.
    private let springHeight: Float = 0.3
    private let halo = SCNNode()
    private let magnet = SCNNode()
    private let fizzNode = SCNNode()
    private var fizz: SCNParticleSystem?

    init() {
        body.scale = SCNVector3(Self.scale, Self.scale, Self.scale)
        node.addChildNode(body)
        // The box turns about its axles, not the ground, so a dip or a roll
        // doesn't slide it sideways. The pivot moves the contents down by the
        // axle height and the position moves them back up, so at rest nothing
        // has moved; only the center of its turns has.
        box.pivot = SCNMatrix4MakeTranslation(0, wheelRadius, 0)
        box.position = SCNVector3(0, wheelRadius, 0)
        body.addChildNode(box)
        buildBox()
        buildWheels()
        buildCans()
        loadKitten()
        buildPowerLooks()
    }

    // MARK: - Events

    /// She left the ground. The box rocks back on its wheels, her body squeezes
    /// for a beat and then stretches tall, and her ears go back.
    func didJump() {
        boxPitch.kick(0.9)
        suspension.kick(-0.5)
        stretch.kick(-0.9)
        headBob.kick(-0.5)
        for i in 0..<2 { earPitch[i].kick(3) }
        tailPitch.kick(2.5)
    }

    /// Wheels back on something. `impact` is 0 to 1, from a soft step down to
    /// a slam from the top of a jump. The box dips on its wheels, she squashes,
    /// her head nods and her ears flop, and the tail whips up.
    func didLand(impact: Float) {
        let hit = max(0.2, min(1, impact))
        suspension.kick(-1.1 * hit)
        boxPitch.kick(-0.9 * hit)
        stretch.kick(-1.6 * hit)
        lean.kick(-1.2 * hit)
        headBob.kick(-0.9 * hit)
        headPitch.kick(-2.4 * hit)
        earFlick[0].kick(4 * hit)
        earFlick[1].kick(4 * hit)
        earPitch[0].kick(2 * hit)
        earPitch[1].kick(2 * hit)
        tailPitch.kick(-5 * hit)
        tipPitch.kick(-3 * hit)
    }

    /// She swiped to a new lane. `direction` is +1 toward +x (right), -1 left.
    /// The box rolls and yaws into the turn, and her tail swings the other way.
    func didChangeLane(_ direction: Int) {
        let dir: Float = direction > 0 ? 1 : -1
        boxRoll.kick(-dir * 0.9)
        boxYaw.kick(-dir * 0.7)
        tailYaw.kick(-dir * 4)
        tipYaw.kick(-dir * 2)
        headYaw.kick(-dir * 1.5)
    }

    /// A glancing hit. The box lurches and her ears and tail jump.
    func didStumble() {
        let dir: Float = Bool.random() ? 1 : -1
        boxRoll.kick(dir * 2.2)
        boxYaw.kick(-dir * 1.2)
        suspension.kick(-0.8)
        headBob.kick(-0.7)
        headYaw.kick(dir * 2.5)
        for i in 0..<2 {
            earFlick[i].kick(6)
            earPitch[i].kick(5)
        }
        tailPitch.kick(-5)
        tailYaw.kick(dir * 5)
    }

    // MARK: - Per frame

    /// Spin the wheels with the road, sink her into the box while ducking, and
    /// move every spring toward what the moment calls for. On the home screen
    /// (`idle`) she tilts her head at you, glances around, and gives slow blinks.
    func update(dt rawDt: Float, motion m: CartMotion) {
        // A long frame would make the stiff springs overshoot wildly, so it's capped.
        let dt: Float = min(rawDt, 1.0 / 30.0)
        clock += dt
        // A springy chase toward the goal: stiff enough to duck in under a tenth of
        // a second, loose enough to overshoot on the way up, so she pops out.
        let goal: Float = m.ducking ? 1 : 0
        duckSpeed += ((goal - duck) * 900 - duckSpeed * 34) * dt
        duck += duckSpeed * dt
        duck = max(-0.12, min(1.05, duck))
        let ducked: Float = max(0, min(1, duck))
        let up: Float = max(-1, min(1, m.verticalSpeed / 15))
        let inAir = m.airborne && !m.flying

        updateKitten(dt: dt, m: m, ducked: ducked, up: up, inAir: inAir)
        updateHead(dt: dt, m: m, ducked: ducked, up: up, inAir: inAir)
        updateEars(dt: dt, m: m, ducked: ducked, up: up, inAir: inAir)
        updateTail(dt: dt, m: m, up: up, inAir: inAir)
        updateBoxMotion(dt: dt, m: m)

        if m.rolling && !m.crashed {
            let spin = m.speed / wheelRadius * dt
            for w in wheels { w.eulerAngles.x -= spin }
        }
        updateBlink(dt: dt, idle: m.idle)
        // A crash squeezes her eyes shut. They open again on the first frame she
        // isn't crashed, so the blink doesn't have to notice.
        if m.crashed {
            for e in eyes { e.scale.y = 0.12 }
            eyesSqueezed = true
        } else if eyesSqueezed {
            eyesSqueezed = false
            for e in eyes { e.scale.y = 1 }
        }
        updatePowerLooks(dt: dt, ducking: m.ducking)
    }

    /// Her body: the duck squash, breathing, stretching in the air, and leaning.
    private func updateKitten(dt: Float, m: CartMotion, ducked: Float, up: Float, inAir: Bool) {
        // Taller going up, tucked coming down. Nothing while ducked: the duck
        // heights in docs/plans/duck.md are measured sitting still.
        var stretchGoal: Float = 0
        if inAir && ducked < 0.5 {
            stretchGoal = max(-0.05, min(0.07, up * 0.09))
        }
        stretch.step(toward: stretchGoal, dt: dt)
        stretch.value = max(-0.12, min(0.12, stretch.value))

        // Rocked back a little while she rises, curled forward as she drops to
        // land. Flying, she sits back and bobs on the fizz.
        var leanGoal: Float = 0
        if inAir {
            leanGoal = max(-0.13, min(0.13, up * 0.14))
        } else if m.flying {
            leanGoal = 0.08 + 0.02 * sin(clock * 5.3)
        }
        lean.step(toward: leanGoal, dt: dt)
        lean.value = max(-0.3, min(0.3, lean.value))

        // Into the turn: moving toward +x, her top leans to +x, a negative turn about z.
        let rollGoal: Float = max(-0.14, min(0.14, -m.steer * 0.12))
        kittenRoll.step(toward: rollGoal, dt: dt)

        guard let kitten, let kittenBody else { return }
        kitten.position.y = seatY - Self.duckSink * ducked
        // Below 0 (the pop on the way up) she stretches a little taller.
        // She breathes, a slow small swell of her chest; quicker in the air.
        let breath: Float = 1 + 0.012 * sin(clock * (inAir ? 4.5 : 2.4))
        let squash: Float = (1 - Self.duckSquash * duck) * breath * (1 + stretch.value)
        // A little thinner when stretched and wider when squashed, like a real body.
        let girth: Float = 1 - stretch.value * 0.5
        kittenBody.scale = SCNVector3(girth, squash, girth)
        for holder in unsquashed {
            holder.scale = SCNVector3(1 / girth, 1 / squash, 1 / girth)
        }
        kitten.eulerAngles.x = lean.value
        kitten.eulerAngles.z = kittenRoll.value
    }

    /// Her head: looks where she is going, tips up at the top of a jump, nods
    /// on landing, and on the home screen tilts and glances around.
    private func updateHead(dt: Float, m: CartMotion, ducked: Float, up: Float, inAir: Bool) {
        // On the home screen she tilts her head one way, then the other, like a
        // kitten working out what you are, and now and then looks off to a side.
        let tiltGoal: Float = m.idle ? 0.16 * sin(clock * 0.55) : 0
        idleTilt += (tiltGoal - idleTilt) * min(1, 3 * dt)
        updateGlance(dt: dt, idle: m.idle)

        // Yaw: + turns her nose to her left (-x). Steering toward +x she looks
        // toward +x, so the goal is negative. A little wander while flying.
        var yawGoal: Float = max(-0.42, min(0.42, -m.steer * 0.3)) + glanceYaw
        if m.flying { yawGoal += 0.12 * sin(clock * 0.9) }
        headYaw.step(toward: yawGoal, dt: dt)
        headYaw.value = max(-0.7, min(0.7, headYaw.value))

        // Pitch: + is nose up. Looking ahead at the top of a jump, nose up as
        // she rises, level as she falls, down a touch on a slam. Ducked she
        // looks down into the box, which also keeps her head top low.
        var pitchGoal: Float = -abs(idleTilt) * 0.25 + glancePitch
        if inAir {
            pitchGoal = 0.18 + max(-0.3, min(0.12, up * 0.18))
        } else if m.flying {
            pitchGoal = 0.12 + 0.03 * sin(clock * 1.7)
        } else if m.crashed {
            pitchGoal = -0.3
        }
        pitchGoal -= 0.3 * ducked
        headPitch.step(toward: pitchGoal, dt: dt)
        headPitch.value = max(-0.6, min(0.6, headPitch.value))

        // The bob is a small lag up and down, kicked by takeoffs and landings.
        headBob.step(toward: 0, dt: dt)
        headBob.value = max(-0.04, min(0.03, headBob.value))

        guard let head else { return }
        head.eulerAngles.x = headRest.x + headPitch.value
        head.eulerAngles.y = headRest.y + headYaw.value
        head.eulerAngles.z = headRest.z + m.tilt * 1.2 + idleTilt
        head.position.y = headBob.value
    }

    /// Home screen only: every few seconds she looks off to one side for a
    /// moment, and the ear on that side turns toward whatever she heard.
    private func updateGlance(dt: Float, idle: Bool) {
        guard idle else {
            glanceYaw = 0
            glancePitch = 0
            glanceHold = 0
            return
        }
        if glanceHold > 0 {
            glanceHold -= dt
            if glanceHold <= 0 {
                glanceYaw = 0
                glancePitch = 0
                glanceWait = Float.random(in: 2.5...6)
            }
            return
        }
        glanceWait -= dt
        guard glanceWait <= 0 else { return }
        glanceHold = Float.random(in: 0.9...2.0)
        let side: Float = Bool.random() ? 1 : -1
        glanceYaw = -side * Float.random(in: 0.25...0.45)
        glancePitch = Float.random(in: -0.08...0.14)
        // The ear on that side (right ear is index 1) flicks first.
        let i = side > 0 ? 1 : 0
        if i < earFlick.count { earFlick[i].kick(side > 0 ? -5 : 5) }
    }

    /// Ears: pinned back in a jump, the wind, a duck, or a crash; a quick
    /// sideways flick now and then, each ear on its own clock; swiveled toward
    /// a home-screen glance.
    private func updateEars(dt: Float, m: CartMotion, ducked: Float, up: Float, inAir: Bool) {
        // How far back they lie: + is back, toward the camera.
        var pin: Float = max(0, (m.speed - 15) / 25) * 0.12
        if inAir { pin = max(pin, 0.12 + max(0, up) * 0.3) }
        if m.flying { pin = max(pin, 0.5 + 0.06 * sin(clock * 11) + 0.04 * sin(clock * 17.3)) }
        pin = max(pin, ducked * 0.95)
        if m.crashed { pin = 0.95 }

        for i in 0..<min(2, ears.count) {
            // Left ear flicks outward with a positive turn about z, right with a negative.
            let dir: Float = i == 0 ? 1 : -1
            earFlickWait[i] -= dt
            if earFlickWait[i] <= 0 && !m.crashed {
                earFlick[i].kick(dir * Float.random(in: 5...8))
                let wait: ClosedRange<Float> = m.idle ? 1.5...4.5 : 2.5...7
                earFlickWait[i] = Float.random(in: wait)
                // Sometimes the other ear answers right after.
                if Float.random(in: 0...1) < 0.3 {
                    let j = 1 - i
                    earFlickWait[j] = min(earFlickWait[j], Float.random(in: 0.08...0.2))
                }
            }
            earPitch[i].step(toward: pin, dt: dt)
            earPitch[i].value = max(-0.25, min(1.1, earPitch[i].value))
            earFlick[i].step(toward: 0, dt: dt)
            earFlick[i].value = max(-0.5, min(0.5, earFlick[i].value))
            // Toward the glance: the ear on the side she looks turns outward.
            var swivelGoal: Float = 0
            if glanceHold > 0 {
                let side: Float = glanceYaw < 0 ? 1 : -1
                if (side > 0 && i == 1) || (side < 0 && i == 0) { swivelGoal = -side * 0.3 }
            }
            earSwivel[i].step(toward: swivelGoal, dt: dt)

            let rest = earRests[i]
            ears[i].eulerAngles = SCNVector3(rest.x + earPitch[i].value,
                                             rest.y + earSwivel[i].value,
                                             rest.z + earFlick[i].value)
        }
    }

    /// Tail: held up (see `tailLift`) and swaying, trailing against the motion
    /// up and down, whipping the other way on a turn, with the tip a beat behind.
    private func updateTail(dt: Float, m: CartMotion, up: Float, inAir: Bool) {
        guard let tail else { return }
        // Pitch: + brings it down toward the back wall. Rising, it lags down;
        // falling, it streams up over her. Flying, it streams out behind and
        // flutters. Crashed, it drops.
        var pitchGoal: Float = 0
        if inAir {
            pitchGoal = max(-0.4, min(0.35, up * 0.38))
        } else if m.flying {
            pitchGoal = 0.45 + 0.05 * sin(clock * 9.1) + 0.03 * sin(clock * 13.7)
        } else if m.crashed {
            pitchGoal = 0.7
        }
        tailPitch.step(toward: pitchGoal, dt: dt)
        tailPitch.value = max(-0.7, min(0.9, tailPitch.value))

        // Yaw: a slow, uneven sway instead of a metronome. Bigger and slower
        // on the home screen, where she's just sitting with you.
        let rate: Float = m.idle ? 0.7 : 1.1
        let swayAmount: Float = m.crashed ? 0.05 : (m.idle ? 0.3 : 0.22)
        let sway: Float = swayAmount * Self.noise(clock * rate, seed: 0.7)
        tailYaw.step(toward: 0, dt: dt)
        tailYaw.value = max(-0.8, min(0.8, tailYaw.value))

        let yaw: Float = tailYaw.value + sway
        tail.eulerAngles.x = tailRest.x + tailPitch.value
        tail.eulerAngles.y = tailRest.y + yaw

        // The tip follows the tail late, so the tail bends like a whip. A flying
        // flutter on top.
        guard let tailTip else { return }
        tipPitch.step(toward: tailPitch.value, dt: dt)
        tipYaw.step(toward: yaw, dt: dt)
        var lagPitch: Float = (tipPitch.value - tailPitch.value) * 0.9
        let lagYaw: Float = (tipYaw.value - yaw) * 0.9
        if m.flying { lagPitch += 0.08 * sin(clock * 15.3) }
        tailTip.eulerAngles.x = tailTipRest.x + max(-0.6, min(0.6, lagPitch))
        tailTip.eulerAngles.y = tailTipRest.y + max(-0.6, min(0.6, lagYaw))
    }

    /// The box on its wheels: a suspension dip, roll and yaw into turns, a nose
    /// dip on landing, and a faint rattle from the road.
    private func updateBoxMotion(dt: Float, m: CartMotion) {
        suspension.step(toward: 0, dt: dt)
        suspension.value = max(-0.07, min(0.03, suspension.value))
        boxRoll.step(toward: 0, dt: dt)
        boxRoll.value = max(-0.2, min(0.2, boxRoll.value))
        boxPitch.step(toward: 0, dt: dt)
        boxPitch.value = max(-0.15, min(0.15, boxPitch.value))
        boxYaw.step(toward: 0, dt: dt)
        boxYaw.value = max(-0.15, min(0.15, boxYaw.value))

        // Road rattle: two sines that never line up, scaled by speed. Tiny on
        // purpose; GameScene already bumps the whole cart.
        var rattle: Float = 0
        var rattleRoll: Float = 0
        if m.rolling && !m.crashed {
            let amount: Float = min(1, m.speed / 20)
            rattle = (0.0035 * sin(clock * 43.7) + 0.0025 * sin(clock * 71.3)) * amount
            rattleRoll = 0.004 * sin(clock * 37.1) * amount
        }
        box.position.y = wheelRadius + suspension.value + rattle
        box.eulerAngles = SCNVector3(boxPitch.value, boxYaw.value, boxRoll.value + rattleRoll)
    }

    /// Smooth wandering noise in -1...1: three sines at rates that never line
    /// up, so it never repeats on a beat you can hear.
    private static func noise(_ t: Float, seed: Float) -> Float {
        let a: Float = sin(t + seed)
        let b: Float = 0.5 * sin(2.13 * t + seed * 1.7)
        let c: Float = 0.25 * sin(3.71 * t - seed)
        return (a + b + c) / 1.75
    }

    /// Quick blinks every few seconds. On the home screen some are slow: eyes
    /// half shut, held, then open, which is how a cat says she trusts you.
    private func updateBlink(dt: Float, idle: Bool) {
        guard !eyes.isEmpty else { return }
        if blinkClock < 0 {
            blinkWait -= dt
            guard blinkWait <= 0 else { return }
            blinkClock = 0
            blinkLength = idle && Float.random(in: 0...1) < 0.45 ? 1.3 : 0.16
            blinkWait = Float.random(in: 2.5...5.5)
        }
        blinkClock += dt
        let t = min(1, blinkClock / blinkLength)
        let open: Float
        if blinkLength > 0.5 {
            // Slow: down to a sleepy squint, hold it, back up.
            let close = min(1, t / 0.3) * (t < 0.7 ? 1 : max(0, 1 - (t - 0.7) / 0.3))
            open = 1 - 0.72 * close
        } else {
            open = max(0.08, abs(t - 0.5) * 2)
        }
        for e in eyes { e.scale.y = open }
        if t >= 1 {
            blinkClock = -1
            for e in eyes { e.scale.y = 1 }
        }
    }

    // MARK: - Box

    private func material(_ name: String, fallback: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIImage(named: name) ?? fallback
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 8
        m.lightingModel = .lambert
        return m
    }

    private func buildBox() {
        let side = material("cartSide", fallback: UIColor(red: 0.83, green: 0.93, blue: 0.98, alpha: 1))
        let end = material("cartEnd", fallback: UIColor(red: 0.83, green: 0.93, blue: 0.98, alpha: 1))
        let kraft = material("cartKraft", fallback: UIColor(red: 0.85, green: 0.75, blue: 0.59, alpha: 1))
        let rim = material("cartEnd", fallback: .white)
        rim.diffuse.contents = UIColor(red: 0.93, green: 0.97, blue: 1.0, alpha: 1)

        let midY = boxBottom + Float(boxHeight) / 2
        // SCNBox faces: front (+z), right (+x), back (-z), left (-x), top, bottom.
        // Back wall, the one the run camera sees. Outside faces +z.
        let back = SCNBox(width: boxWidth, height: boxHeight, length: wall, chamferRadius: 0.012)
        back.materials = [side, kraft, kraft, kraft, rim, kraft]
        let backNode = SCNNode(geometry: back)
        backNode.position = SCNVector3(0, midY, Float(boxDepth - wall) / 2)
        box.addChildNode(backNode)

        // Front wall, the one the home screen sees. Outside faces -z.
        let front = SCNBox(width: boxWidth, height: boxHeight, length: wall, chamferRadius: 0.012)
        front.materials = [kraft, kraft, side, kraft, rim, kraft]
        let frontNode = SCNNode(geometry: front)
        frontNode.position = SCNVector3(0, midY, -Float(boxDepth - wall) / 2)
        box.addChildNode(frontNode)

        // Ends, each with the hand hole a real 12-pack has cut near its top: a
        // dark slot just proud of the wall, so it reads as a hole from any angle.
        let hole = SCNMaterial()
        hole.diffuse.contents = UIColor(red: 0.30, green: 0.24, blue: 0.17, alpha: 1)
        hole.lightingModel = .lambert
        let slot = SCNBox(width: 0.006, height: 0.055, length: 0.17, chamferRadius: 0.003)
        slot.materials = [hole]
        for sx: Float in [-1, 1] {
            let e = SCNBox(width: wall, height: boxHeight, length: boxDepth - wall * 2, chamferRadius: 0.012)
            e.materials = sx > 0 ? [kraft, end, kraft, kraft, rim, kraft] : [kraft, kraft, kraft, end, rim, kraft]
            let n = SCNNode(geometry: e)
            n.position = SCNVector3(sx * Float(boxWidth - wall) / 2, midY, 0)
            box.addChildNode(n)
            let s = SCNNode(geometry: slot)
            s.position = SCNVector3(sx * (Float(boxWidth) / 2 + 0.002), boxBottom + Float(boxHeight) - 0.09, 0)
            box.addChildNode(s)
        }

        // Floor, raised to her seat so she sits high enough to see over the rim.
        let floorHeight = CGFloat(seatY - boxBottom)
        let floor = SCNBox(width: boxWidth - wall * 2, height: floorHeight, length: boxDepth - wall * 2, chamferRadius: 0)
        floor.materials = [kraft]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, boxBottom + Float(floorHeight) / 2, 0)
        box.addChildNode(floorNode)
    }

    private func buildWheels() {
        let rubber = SCNMaterial()
        rubber.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        rubber.lightingModel = .lambert
        let hubMat = SCNMaterial()
        hubMat.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        hubMat.lightingModel = .blinn
        hubMat.specular.contents = UIColor(white: 0.6, alpha: 1)
        let chrome = SCNMaterial()
        chrome.diffuse.contents = UIColor(white: 0.95, alpha: 1)
        chrome.lightingModel = .blinn
        chrome.specular.contents = UIColor(white: 1, alpha: 1)
        chrome.shininess = 0.9

        // A fat rounded tire, like a toy wagon's, with a pale hub inside it.
        let tire = SCNTorus(ringRadius: CGFloat(wheelRadius) - 0.045, pipeRadius: 0.048)
        tire.materials = [rubber]
        let hub = SCNCylinder(radius: CGFloat(wheelRadius) * 0.62, height: 0.1)
        hub.materials = [hubMat]
        // A stripe on the hub so you can see it spin.
        let spoke = SCNBox(width: 0.035, height: CGFloat(wheelRadius) * 1.05, length: 0.105, chamferRadius: 0)
        spoke.materials = [rubber]
        // A shiny center cap, the hubcap's bolt.
        let cap = SCNCylinder(radius: 0.03, height: 0.125)
        cap.materials = [chrome]

        let x = Float(boxWidth) / 2 - 0.12
        let z = Float(boxDepth) / 2 - 0.16
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
            let axle = SCNNode()
            axle.position = SCNVector3(sx * x, wheelRadius, sz * z)
            let spinner = SCNNode()
            // Cylinders and the torus stand along y; lay them on their side so
            // they roll along z.
            let t = SCNNode(geometry: tire)
            t.eulerAngles.z = .pi / 2
            let h = SCNNode(geometry: hub)
            h.eulerAngles.z = .pi / 2
            let s = SCNNode(geometry: spoke)
            s.eulerAngles.z = .pi / 2
            let c = SCNNode(geometry: cap)
            c.eulerAngles.z = .pi / 2
            spinner.addChildNode(t)
            spinner.addChildNode(h)
            spinner.addChildNode(s)
            spinner.addChildNode(c)
            axle.addChildNode(spinner)
            body.addChildNode(axle)
            wheels.append(spinner)
        }
    }

    /// Cans in the four corners, like a real open 12-pack.
    private func buildCans() {
        let wrap = material("canWrap", fallback: UIColor(red: 0.8, green: 0.92, blue: 0.98, alpha: 1))
        let lid = SCNMaterial()
        lid.diffuse.contents = UIColor(white: 0.82, alpha: 1)
        lid.lightingModel = .blinn
        lid.specular.contents = UIColor(white: 0.8, alpha: 1)
        let can = SCNCylinder(radius: 0.085, height: 0.3)
        can.materials = [wrap, lid, lid]
        let top = boxBottom + Float(boxHeight) - 0.03
        let x = Float(boxWidth) / 2 - 0.13
        let z = Float(boxDepth) / 2 - 0.13
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
            let n = SCNNode(geometry: can)
            n.position = SCNVector3(sx * x, top - 0.15, sz * z)
            n.eulerAngles.y = Float.random(in: 0...(2 * .pi))
            box.addChildNode(n)
        }
    }

    // MARK: - Kitten

    private func loadKitten() {
        guard let url = Bundle.main.url(forResource: "cat_kitten", withExtension: "scn"),
              let scene = try? SCNScene(url: url, options: nil) else {
            addStandIn()
            return
        }
        let root = scene.rootNode.childNode(withName: "kitten", recursively: true) ?? scene.rootNode
        let kitten = root.clone()
        kitten.position = SCNVector3(0, seatY, 0)
        box.addChildNode(kitten)
        self.kitten = kitten
        hasModel = true

        head = kitten.childNode(withName: "head", recursively: true)
        headRest = head?.eulerAngles ?? SCNVector3Zero
        // The model's origin is under her bottom, so squashing "body" in y keeps her seated.
        kittenBody = kitten.childNode(withName: "body", recursively: false)
        holdUnsquashed(head)
        holdUnsquashed(kitten.childNode(withName: "tail", recursively: true))
        findParts(kitten)
    }

    /// Puts a part in a holder at the same spot. When the body squashes for the
    /// duck, the holder scales the other way. The part's own turns (head lean,
    /// tail sway) happen inside the holder, so they never get skewed.
    private func holdUnsquashed(_ part: SCNNode?) {
        guard let part, let parent = part.parent else { return }
        let holder = SCNNode()
        holder.position = part.position
        part.removeFromParentNode()
        part.position = SCNVector3Zero
        holder.addChildNode(part)
        parent.addChildNode(holder)
        unsquashed.append(holder)
    }

    /// A plain gray kitten shape, only shown if the Blender model is missing.
    private func addStandIn() {
        let fur = SCNMaterial()
        fur.diffuse.contents = UIColor(red: 0.52, green: 0.54, blue: 0.60, alpha: 1)
        fur.lightingModel = .lambert
        let torso = SCNSphere(radius: 0.36)
        torso.materials = [fur]
        let b = SCNNode(geometry: torso)
        b.position = SCNVector3(0, seatY + 0.3, 0.05)
        b.scale = SCNVector3(1, 0.9, 0.9)
        box.addChildNode(b)
        let skull = SCNSphere(radius: 0.3)
        skull.materials = [fur]
        let h = SCNNode(geometry: skull)
        h.name = "head"
        h.position = SCNVector3(0, seatY + 0.78, -0.05)
        h.scale = SCNVector3(1.12, 0.95, 1)
        box.addChildNode(h)
        head = h
        headRest = h.eulerAngles
    }

    /// Finds the parts the springs move and remembers where each one rests.
    /// The motion itself is all in update; nothing runs on an SCNAction, so
    /// every part can answer to what she's doing right now.
    private func findParts(_ kitten: SCNNode) {
        if let t = kitten.childNode(withName: "tail", recursively: true) {
            // Held up like a happy cat instead of draped over the back wall,
            // so the La Croix name on the box stays readable from the run camera.
            t.eulerAngles.x -= Self.tailLift
            tail = t
            tailRest = t.eulerAngles
            if let tip = t.childNode(withName: "tailTip", recursively: true) {
                tailTip = tip
                tailTipRest = tip.eulerAngles
            }
        }
        // Left ear first, then right, to match the spring arrays.
        for name in ["earL", "earR"] {
            guard let ear = kitten.childNode(withName: name, recursively: true) else { continue }
            ears.append(ear)
            earRests.append(ear.eulerAngles)
        }
        // If one ear is missing the arrays would disagree, so keep none.
        if ears.count != 2 {
            ears.removeAll()
            earRests.removeAll()
        }
        // Blinks are driven from update, so the home screen can slow them down.
        eyes = ["eyeL", "eyeR"].compactMap { kitten.childNode(withName: $0, recursively: true) }
    }

    // MARK: - Power-up looks

    /// Turns a power-up's look on or off. The springs ease in and out in
    /// update; the rest pop.
    func show(_ power: PowerUp, _ on: Bool) {
        switch power {
        case .pounce: springsOn = on
        case .lives: halo.isHidden = !on
        case .magnet: magnet.isHidden = !on
        case .rocket: fizz?.birthRate = on ? 90 : 0
        }
    }

    /// Tucks every look away, for a new run.
    func hidePowerLooks() {
        for p in PowerUp.allCases { show(p, false) }
        springLift = 0
        body.position.y = 0
        springs.isHidden = true
    }

    private func updatePowerLooks(dt: Float, ducking: Bool) {
        // Springs: stretched out under the wheels, squeezed flat while she ducks
        // (so her head still clears low things), with a little bounce.
        let goal: Float = springsOn ? (ducking ? 0.04 : springHeight) : 0
        springLift += (goal - springLift) * min(1, 10 * dt)
        let bounce: Float = springsOn ? 0.035 * abs(sin(clock * 9)) : 0
        let lift = springLift + bounce * springLift / springHeight
        body.position.y = lift
        springs.isHidden = springLift < 0.01
        springs.scale.y = max(0.01, lift / springHeight)
        if !halo.isHidden {
            halo.eulerAngles.y = clock * 1.6
            halo.position.y = haloY + 0.02 * sin(clock * 3)
        }
        if !magnet.isHidden {
            magnet.position.y = magnetY + 0.05 * sin(clock * 4)
            magnet.eulerAngles.z = 0.2 * sin(clock * 2.5)
        }
    }

    private var haloY: Float = 0
    private var magnetY: Float = 0

    private func glowMaterial(_ color: UIColor, glow: CGFloat = 0.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.emission.contents = color.withAlphaComponent(1)
        m.emission.intensity = glow
        m.specular.contents = UIColor(white: 1, alpha: 1)
        m.shininess = 0.7
        m.lightingModel = .blinn
        return m
    }

    private func buildPowerLooks() {
        // Springs: one coil under each wheel, built at full stretch and squeezed
        // by scaling. They hang off the unscaled node, so they're real size.
        let steel = glowMaterial(UIColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1), glow: 0.15)
        let coil = SCNTorus(ringRadius: 0.11, pipeRadius: 0.022)
        coil.materials = [steel]
        let x = (Float(boxWidth) / 2 - 0.12) * Self.scale
        let z = (Float(boxDepth) / 2 - 0.16) * Self.scale
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
            for i in 0..<5 {
                let ring = SCNNode(geometry: coil)
                ring.position = SCNVector3(sx * x, springHeight * (Float(i) + 0.5) / 5, sz * z)
                // Tipped a little, alternating, so it reads as one coil, not rings.
                ring.eulerAngles.z = i % 2 == 0 ? 0.18 : -0.18
                springs.addChildNode(ring)
            }
        }
        springs.isHidden = true
        node.addChildNode(springs)

        // Nine Lives: a gold halo over her head that leans with it.
        let gold = glowMaterial(UIColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 1), glow: 0.9)
        let ringGeo = SCNTorus(ringRadius: 0.17, pipeRadius: 0.022)
        ringGeo.materials = [gold]
        halo.geometry = ringGeo
        halo.name = "glow"
        halo.isHidden = true
        let headHolder = head ?? box
        // The head's pivot is her neck; the top of her head is about 0.4 above it.
        haloY = head != nil ? 0.5 : seatY + 1.15
        halo.position = SCNVector3(0, haloY, head != nil ? -0.04 : 0)
        headHolder.addChildNode(halo)

        // Can Magnet: a red horseshoe magnet bobbing over her right shoulder.
        let red = glowMaterial(UIColor(red: 0.92, green: 0.16, blue: 0.2, alpha: 1), glow: 0.35)
        let silver = glowMaterial(UIColor(white: 0.9, alpha: 1), glow: 0.3)
        let shoe = UIBezierPath()
        shoe.addArc(withCenter: .zero, radius: 0.12, startAngle: 0, endAngle: .pi, clockwise: true)
        shoe.addLine(to: CGPoint(x: -0.12, y: -0.1))
        shoe.addLine(to: CGPoint(x: -0.06, y: -0.1))
        shoe.addLine(to: CGPoint(x: -0.06, y: 0))
        shoe.addArc(withCenter: .zero, radius: 0.06, startAngle: .pi, endAngle: 0, clockwise: false)
        shoe.addLine(to: CGPoint(x: 0.06, y: -0.1))
        shoe.addLine(to: CGPoint(x: 0.12, y: -0.1))
        shoe.close()
        let shape = SCNShape(path: shoe, extrusionDepth: 0.06)
        shape.chamferRadius = 0.01
        shape.materials = [red]
        // The arch is on top and the open end points down at her.
        magnet.addChildNode(SCNNode(geometry: shape))
        for tx: Float in [-0.09, 0.09] {
            let tip = SCNNode(geometry: SCNBox(width: 0.06, height: 0.04, length: 0.065, chamferRadius: 0.008))
            tip.geometry?.materials = [silver]
            tip.position = SCNVector3(tx, -0.12, 0)
            magnet.addChildNode(tip)
        }
        magnetY = seatY + 1.25
        magnet.position = SCNVector3(0.42, magnetY, 0)
        magnet.isHidden = true
        box.addChildNode(magnet)

        // Fizz Rocket: the cans fizz out the bottom of the box like rockets.
        let ps = SCNParticleSystem()
        ps.particleImage = Self.bubbleImage()
        ps.birthRate = 0
        ps.particleLifeSpan = 0.55
        ps.particleLifeSpanVariation = 0.2
        ps.particleSize = 0.09
        ps.particleSizeVariation = 0.05
        ps.particleColor = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.95)
        ps.emitterShape = SCNBox(width: boxWidth * 0.9, height: 0.02, length: boxDepth * 0.8, chamferRadius: 0)
        ps.emittingDirection = SCNVector3(0, -1, 0.5)
        ps.spreadingAngle = 30
        ps.particleVelocity = 5
        ps.particleVelocityVariation = 2
        ps.acceleration = SCNVector3(0, 2, 6)
        ps.blendMode = .alpha
        ps.isLocal = false
        let fade = CAKeyframeAnimation()
        fade.values = [1.0, 0.8, 0]
        fade.keyTimes = [0, 0.5, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        fizz = ps
        fizzNode.position = SCNVector3(0, boxBottom, 0)
        fizzNode.addParticleSystem(ps)
        body.addChildNode(fizzNode)
    }

    /// A small soft bubble with a bright rim, for the fizz.
    private static func bubbleImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
            cg.fillEllipse(in: CGRect(x: 6, y: 6, width: 36, height: 36))
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.95).cgColor)
            cg.setLineWidth(4)
            cg.strokeEllipse(in: CGRect(x: 6, y: 6, width: 36, height: 36))
            cg.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: 14, y: 13, width: 9, height: 8))
        }
    }
}
