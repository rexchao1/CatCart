import SceneKit
import UIKit

// The player: Rex's kitten sitting in a La Croix 12-pack box on four wheels.
//
// The box is built here from SceneKit boxes and cylinders, wrapped in the
// textures from scripts/make_cart_textures.py. The kitten is a Blender model
// (Models/cat_kitten.scn, from scripts/blender/make_cat.py) with separate
// head, ears, eyes, and tail nodes, so we can make her twitch and blink in code.
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

    init() {
        body.scale = SCNVector3(Self.scale, Self.scale, Self.scale)
        node.addChildNode(body)
        buildBox()
        buildWheels()
        buildCans()
        loadKitten()
    }

    // MARK: - Per frame

    /// Spin the wheels with the road, lean her head into lane changes, and sink
    /// her into the box while `ducking` is true.
    func update(dt: Float, speed: Float, rolling: Bool, tilt: Float, ducking: Bool = false) {
        // A springy chase toward the goal: stiff enough to duck in under a tenth of
        // a second, loose enough to overshoot on the way up, so she pops out.
        let goal: Float = ducking ? 1 : 0
        duckSpeed += ((goal - duck) * 900 - duckSpeed * 34) * dt
        duck += duckSpeed * dt
        duck = max(-0.12, min(1.05, duck))
        if let kitten, let kittenBody {
            kitten.position.y = seatY - Self.duckSink * min(1, duck)
            // Below 0 (the pop on the way up) she stretches a little taller.
            let squash = 1 - Self.duckSquash * duck
            kittenBody.scale.y = squash
            for holder in unsquashed { holder.scale.y = 1 / squash }
        }
        if rolling {
            let spin = speed / wheelRadius * dt
            for w in wheels { w.eulerAngles.x -= spin }
        }
        if let head {
            head.eulerAngles.z = headRest.z + tilt * 1.2
            head.eulerAngles.y = headRest.y - tilt * 0.8
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

    /// Little life while she rides: tail sway, ear flicks, blinks.
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
        let eyes = ["eyeL", "eyeR"].compactMap { kitten.childNode(withName: $0, recursively: true) }
        let blink = SCNAction.sequence([
            .wait(duration: 3, withRange: 3),
            .customAction(duration: 0.16) { _, t in
                let k = Float(abs(t / 0.16 - 0.5) * 2)
                for e in eyes { e.scale.y = max(0.08, k) }
            }
        ])
        eyes.first?.runAction(.repeatForever(blink))
    }
}
