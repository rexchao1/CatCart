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
// The power-up looks live here too: springs under the wheels, a halo, a magnet
// over her head, and fizz from the cans. GameScene turns them on and off.
//
// Coordinates: meters, +y up. She faces -z, away from the run camera.
// The node's origin is on the ground under the middle of the box.

final class KittenCart {

    let node = SCNNode()
    /// Everything below is built at real size, then scaled up so she reads well
    /// from the run camera.
    private let body = SCNNode()
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
        buildBox()
        buildWheels()
        buildCans()
        loadKitten()
        buildPowerLooks()
    }

    // MARK: - Per frame

    /// Spin the wheels with the road, lean her head into lane changes, and sink
    /// her into the box while `ducking` is true. `idle` is the home screen, where
    /// she tilts her head at you and gives slow cat blinks.
    func update(dt: Float, speed: Float, rolling: Bool, tilt: Float, ducking: Bool = false, idle: Bool = false) {
        clock += dt
        // A springy chase toward the goal: stiff enough to duck in under a tenth of
        // a second, loose enough to overshoot on the way up, so she pops out.
        let goal: Float = ducking ? 1 : 0
        duckSpeed += ((goal - duck) * 900 - duckSpeed * 34) * dt
        duck += duckSpeed * dt
        duck = max(-0.12, min(1.05, duck))
        if let kitten, let kittenBody {
            kitten.position.y = seatY - Self.duckSink * min(1, duck)
            // Below 0 (the pop on the way up) she stretches a little taller.
            // She breathes, a slow small swell of her chest.
            let breath = 1 + 0.012 * sin(clock * 2.4)
            let squash = (1 - Self.duckSquash * duck) * breath
            kittenBody.scale.y = squash
            for holder in unsquashed { holder.scale.y = 1 / squash }
        }
        if rolling {
            let spin = speed / wheelRadius * dt
            for w in wheels { w.eulerAngles.x -= spin }
        }
        // On the home screen she tilts her head one way, then the other, like a
        // kitten working out what you are.
        let tiltGoal: Float = idle ? 0.16 * sin(clock * 0.55) : 0
        idleTilt += (tiltGoal - idleTilt) * min(1, 3 * dt)
        if let head {
            head.eulerAngles.z = headRest.z + tilt * 1.2 + idleTilt
            head.eulerAngles.y = headRest.y - tilt * 0.8
            head.eulerAngles.x = headRest.x - abs(idleTilt) * 0.25
        }
        updateBlink(dt: dt, idle: idle)
        updatePowerLooks(dt: dt, ducking: ducking)
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
        body.addChildNode(backNode)

        // Front wall, the one the home screen sees. Outside faces -z.
        let front = SCNBox(width: boxWidth, height: boxHeight, length: wall, chamferRadius: 0.012)
        front.materials = [kraft, kraft, side, kraft, rim, kraft]
        let frontNode = SCNNode(geometry: front)
        frontNode.position = SCNVector3(0, midY, -Float(boxDepth - wall) / 2)
        body.addChildNode(frontNode)

        // Ends.
        for sx: Float in [-1, 1] {
            let e = SCNBox(width: wall, height: boxHeight, length: boxDepth - wall * 2, chamferRadius: 0.012)
            e.materials = sx > 0 ? [kraft, end, kraft, kraft, rim, kraft] : [kraft, kraft, kraft, end, rim, kraft]
            let n = SCNNode(geometry: e)
            n.position = SCNVector3(sx * Float(boxWidth - wall) / 2, midY, 0)
            body.addChildNode(n)
        }

        // Floor, raised to her seat so she sits high enough to see over the rim.
        let floorHeight = CGFloat(seatY - boxBottom)
        let floor = SCNBox(width: boxWidth - wall * 2, height: floorHeight, length: boxDepth - wall * 2, chamferRadius: 0)
        floor.materials = [kraft]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, boxBottom + Float(floorHeight) / 2, 0)
        body.addChildNode(floorNode)
    }

    private func buildWheels() {
        let rubber = SCNMaterial()
        rubber.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        rubber.lightingModel = .lambert
        let hubMat = SCNMaterial()
        hubMat.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        hubMat.lightingModel = .blinn
        hubMat.specular.contents = UIColor(white: 0.6, alpha: 1)

        let tire = SCNCylinder(radius: CGFloat(wheelRadius), height: 0.1)
        tire.materials = [rubber]
        let hub = SCNCylinder(radius: CGFloat(wheelRadius) * 0.5, height: 0.11)
        hub.materials = [hubMat]
        // A stripe on the hub so you can see it spin.
        let spoke = SCNBox(width: 0.035, height: CGFloat(wheelRadius) * 0.9, length: 0.115, chamferRadius: 0)
        spoke.materials = [rubber]

        let x = Float(boxWidth) / 2 - 0.12
        let z = Float(boxDepth) / 2 - 0.16
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(Float, Float)] {
            let axle = SCNNode()
            axle.position = SCNVector3(sx * x, wheelRadius, sz * z)
            let spinner = SCNNode()
            // Cylinders stand along y; lay them on their side so they roll along z.
            let t = SCNNode(geometry: tire)
            t.eulerAngles.z = .pi / 2
            let h = SCNNode(geometry: hub)
            h.eulerAngles.z = .pi / 2
            let s = SCNNode(geometry: spoke)
            s.eulerAngles.z = .pi / 2
            spinner.addChildNode(t)
            spinner.addChildNode(h)
            spinner.addChildNode(s)
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
            body.addChildNode(n)
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
        body.addChildNode(kitten)
        self.kitten = kitten
        hasModel = true

        head = kitten.childNode(withName: "head", recursively: true)
        headRest = head?.eulerAngles ?? SCNVector3Zero
        // The model's origin is under her bottom, so squashing "body" in y keeps her seated.
        kittenBody = kitten.childNode(withName: "body", recursively: false)
        holdUnsquashed(head)
        holdUnsquashed(kitten.childNode(withName: "tail", recursively: true))
        startIdle(kitten)
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
        body.addChildNode(b)
        let skull = SCNSphere(radius: 0.3)
        skull.materials = [fur]
        let h = SCNNode(geometry: skull)
        h.name = "head"
        h.position = SCNVector3(0, seatY + 0.78, -0.05)
        h.scale = SCNVector3(1.12, 0.95, 1)
        body.addChildNode(h)
        head = h
        headRest = h.eulerAngles
    }

    /// Little life while she rides: tail sway, ear flicks. Blinks are in updateBlink.
    private func startIdle(_ kitten: SCNNode) {
        if let tail = kitten.childNode(withName: "tail", recursively: true) {
            // Held up like a happy cat instead of draped over the back wall,
            // so the La Croix name on the box stays readable from the run camera.
            tail.eulerAngles.x -= Self.tailLift
            let rest = tail.eulerAngles
            tail.runAction(.repeatForever(.sequence([
                .rotateTo(x: CGFloat(rest.x), y: CGFloat(rest.y + 0.28), z: CGFloat(rest.z), duration: 0.7, usesShortestUnitArc: true),
                .rotateTo(x: CGFloat(rest.x), y: CGFloat(rest.y - 0.28), z: CGFloat(rest.z), duration: 0.7, usesShortestUnitArc: true)
            ])))
        }
        for (name, dir) in [("earL", Float(1)), ("earR", Float(-1))] {
            guard let ear = kitten.childNode(withName: name, recursively: true) else { continue }
            let rest = ear.eulerAngles
            let flick = SCNAction.sequence([
                .rotateTo(x: CGFloat(rest.x), y: CGFloat(rest.y), z: CGFloat(rest.z + dir * 0.35), duration: 0.06, usesShortestUnitArc: true),
                .rotateTo(x: CGFloat(rest.x), y: CGFloat(rest.y), z: CGFloat(rest.z), duration: 0.12, usesShortestUnitArc: true)
            ])
            ear.runAction(.repeatForever(.sequence([
                .wait(duration: 2.5, withRange: 3),
                flick
            ])))
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
        let headHolder = head ?? body
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
        body.addChildNode(magnet)

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
