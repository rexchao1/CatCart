import SpriteKit
import UIKit

// This is the whole game. SpriteKit calls didMove once when the screen appears,
// then update(_:) every frame while we're playing.

final class GameScene: SKScene {

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

    private enum World: Int, CaseIterable {
        case city, jungle, house, farm

        var imageName: String {
            switch self {
            case .city: return "bgCity"
            case .jungle: return "bgJungle"
            case .house: return "bgHouse"
            case .farm: return "bgFarm"
            }
        }

        var groundName: String {
            switch self {
            case .city: return "groundCity"
            case .jungle: return "groundJungle"
            case .house: return "groundHouse"
            case .farm: return "groundFarm"
            }
        }

        var wallName: String {
            switch self {
            case .city: return "wallCity"
            case .jungle: return "wallJungle"
            case .house: return "wallHouse"
            case .farm: return "wallFarm"
            }
        }

        var sideName: String {
            switch self {
            case .city: return "sideCity"
            case .jungle: return "sideJungle"
            case .house: return "sideHouse"
            case .farm: return "sideFarm"
            }
        }

        var wash: SKColor {
            switch self {
            case .city: return SKColor(red: 0.42, green: 0.38, blue: 0.44, alpha: 1)
            case .jungle: return SKColor(red: 0.36, green: 0.22, blue: 0.14, alpha: 1)
            case .house: return SKColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1)
            case .farm: return SKColor(red: 0.52, green: 0.40, blue: 0.26, alpha: 1)
            }
        }

        var kit: [(name: String, width: CGFloat, rail: CGFloat)] {
            switch self {
            case .city:
                return [
                    ("sideCityWall", 0.28, 1.82),
                    ("sideCity", 0.13, 1.56),
                    ("sideCityCrate", 0.15, 1.78)
                ]
            case .jungle:
                return [
                    ("sideJungleBush", 0.22, 1.56),
                    ("sideJungleRock", 0.18, 1.76)
                ]
            case .house:
                return [
                    ("sideHouseDoor", 0.24, 1.70),
                    ("sideHouse", 0.16, 1.54),
                    ("sideHouseRad", 0.16, 1.78)
                ]
            case .farm:
                return [
                    ("sideFarmCrop", 0.22, 1.56),
                    ("sideFarmHay", 0.18, 1.76)
                ]
            }
        }

        var haze: (CGFloat, CGFloat, CGFloat) {
            switch self {
            case .city: return (0.85, 0.62, 0.48)
            case .jungle: return (0.45, 0.62, 0.38)
            case .house: return (0.93, 0.78, 0.62)
            case .farm: return (0.72, 0.82, 0.90)
            }
        }

        var wallRepeat: (Float, Float) {
            switch self {
            case .city: return (2.6, 5.5)
            case .jungle: return (2.0, 3.8)
            case .house: return (1.4, 1.6)
            case .farm: return (2.2, 2.8)
            }
        }
    }

    private final class TrackItem: SKSpriteNode {
        var kind: Kind = .coyote
        var lane = 1
        var baseWidth: CGFloat = 1
        var z: CGFloat = 1
        var zLength: CGFloat = 0
        var jumpable: Bool { kind == .coyote }
        var isCollectible: Bool { kind == .food }
        var isRideable: Bool { kind == .tree }
        var zBack: CGFloat { z + zLength }
    }

    private final class SideProp: SKSpriteNode {
        var z: CGFloat = 1
        var side: CGFloat = 1
        var rail: CGFloat = 1.75
        var flip: CGFloat = 1
        var baseWidth: CGFloat = 1
        var widthFactor: CGFloat = 0.2
        var artSlot = 0
    }

    private var state: State = .ready
    private var didBuild = false

    private var worldNode: SKNode!
    private var backgroundA: SKSpriteNode!
    private var backgroundB: SKSpriteNode!
    private var corridorA: SKSpriteNode!
    private var corridorB: SKSpriteNode!
    private var worldScroll: CGFloat = 0
    private var props: [SideProp] = []
    private var laneGuides: SKNode!
    private var speedLines: SKNode!
    private var flash: SKSpriteNode!

    private var playerRoot: SKNode!
    private var playerSprite: SKSpriteNode!
    private var shadow: SKShapeNode!
    private var hud: SKLabelNode!
    private var foodHud: SKLabelNode!
    private var overlay: SKNode!

    private var lane = 1
    private var visualX: CGFloat = 0
    private var tilt: CGFloat = 0
    private var jumping = false
    private var jumpOffset: CGFloat = 0
    private var hangLeft: CGFloat = 0
    private var wasAirborne = false
    private var onPlatform = false
    private var items: [TrackItem] = []

    private var timeAlive: CGFloat = 0
    private var meters: CGFloat = 0
    private var food = 0
    private var bestMeters: CGFloat = 0
    private var spawnTimer: CGFloat = 0
    private var runSpeed: CGFloat = 0.22
    private var playerScale: CGFloat = 1
    private var topSafe: CGFloat = 54
    private var lineTimer: CGFloat = 0

    private var worldIndex = 0
    private var worldTime: CGFloat = 0
    private var fadingWorld = false
    private var fadeTime: CGFloat = 0
    private let worldHold: CGFloat = 10
    private let worldFade: CGFloat = 1.6

    private var swipeStart: CGPoint?
    private var swipeConsumed = false

    private let e2eAutoRun = ProcessInfo.processInfo.environment["CATCART_AUTO_RUN"] == "1"
    private let e2eGod = ProcessInfo.processInfo.environment["CATCART_GOD"] == "1"

    private var playerY: CGFloat { size.height * 0.19 }
    private var horizonY: CGFloat { size.height * 0.54 }
    private var spawnY: CGFloat { horizonY }
    private var jumpPeak: CGFloat { size.height * 0.16 }
    private var platformLift: CGFloat { size.height * 0.11 }

    private var farSpread: CGFloat { size.width * 0.07 }
    private var nearSpread: CGFloat { size.width * 0.24 }
    private let propSpacing: CGFloat = 0.068

    private var zFar: CGFloat { 1.0 }
    private var zNear: CGFloat { 0.22 }

    private var isHighEnough: Bool { jumpOffset > jumpPeak * 0.4 || onPlatform }

    private lazy var coyoteFrames: [SKTexture] = {
        ["coyoteOpen", "coyoteMid", "coyoteClosed", "coyoteMid"].map { SKTexture(imageNamed: $0) }
    }()

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        topSafe = max(view.safeAreaInsets.top, 54)
        if didBuild { return }
        didBuild = true
        bestMeters = CGFloat(UserDefaults.standard.double(forKey: "bestMeters"))
        applyE2ELaunchFlags()
        backgroundColor = currentWorld().wash
        buildWorld()
        showReady()
        if e2eAutoRun {
            startRun()
        }
    }

    private func applyE2ELaunchFlags() {
        switch ProcessInfo.processInfo.environment["CATCART_WORLD"]?.lowercased() {
        case "jungle": worldIndex = 1
        case "house": worldIndex = 2
        case "farm": worldIndex = 3
        default: break
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didBuild, oldSize != size else { return }
        layoutBackground(backgroundA)
        layoutBackground(backgroundB)
        layoutCorridor(corridorA)
        layoutCorridor(corridorB)
        dressCorridor(corridorA, world: currentWorld())
        dressCorridor(corridorB, world: nextWorld())
        layoutLaneGuides()
        placePlayer()
        layoutHUD()
        placeAllProps()
        overlay.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        flash.size = size
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Track math

    private func spread(atY y: CGFloat) -> CGFloat {
        let trip = spawnY - playerY
        let t = trip > 0 ? (spawnY - y) / trip : 1
        return farSpread + (nearSpread - farSpread) * t
    }

    private func laneX(_ lane: Int, y: CGFloat) -> CGFloat {
        size.width / 2 + CGFloat(lane - 1) * spread(atY: y)
    }

    private func perspectiveT(z: CGFloat) -> CGFloat {
        let zSafe = max(z, 0.06)
        let a = 1 / zSafe
        let aFar = 1 / zFar
        let aNear = 1 / zNear
        return (a - aFar) / (aNear - aFar)
    }

    private func screenY(forZ z: CGFloat) -> CGFloat {
        spawnY + (playerY - spawnY) * perspectiveT(z: z)
    }

    private func depthZ(forScreenY y: CGFloat) -> CGFloat {
        let t = (y - spawnY) / (playerY - spawnY)
        let a = 1 / zFar + t * (1 / zNear - 1 / zFar)
        return 1 / max(a, 0.001)
    }

    private func scale(forZ z: CGFloat) -> CGFloat {
        min(zNear / max(z, 0.08), 1.25)
    }

    private func zSpeed() -> CGFloat {
        let secondsToCat = max(1.05, 1.45 - timeAlive * 0.028)
        return (zFar - zNear) / secondsToCat
    }

    private func pixelSpeed(atZ z: CGFloat) -> CGFloat {
        let zSafe = max(z, 0.08)
        let denom = 1 / zNear - 1 / zFar
        let dyDz = (playerY - spawnY) * (-1 / (zSafe * zSafe)) / denom
        return abs(dyDz * zSpeed())
    }

    private func currentWorld() -> World {
        World.allCases[worldIndex % World.allCases.count]
    }

    private func nextWorld() -> World {
        World.allCases[(worldIndex + 1) % World.allCases.count]
    }

    private func treeOverlaps(_ item: TrackItem) -> Bool {
        item.z <= zNear && item.zBack >= zNear
    }

    // MARK: - Setup

    private func buildWorld() {
        worldNode = SKNode()
        addChild(worldNode)

        backgroundA = SKSpriteNode(imageNamed: currentWorld().imageName)
        backgroundA.anchorPoint = CGPoint(x: 0.5, y: 0.58)
        backgroundA.zPosition = 0
        worldNode.addChild(backgroundA)

        backgroundB = SKSpriteNode(imageNamed: nextWorld().imageName)
        backgroundB.anchorPoint = CGPoint(x: 0.5, y: 0.58)
        backgroundB.zPosition = 0.1
        backgroundB.alpha = 0
        worldNode.addChild(backgroundB)

        corridorA = makeCorridor()
        corridorA.zPosition = 1
        worldNode.addChild(corridorA)

        corridorB = makeCorridor()
        corridorB.zPosition = 1.1
        corridorB.alpha = 0
        worldNode.addChild(corridorB)

        laneGuides = SKNode()
        laneGuides.zPosition = 3
        worldNode.addChild(laneGuides)

        speedLines = SKNode()
        speedLines.zPosition = 5
        worldNode.addChild(speedLines)

        playerRoot = SKNode()
        playerRoot.zPosition = 80
        worldNode.addChild(playerRoot)

        shadow = SKShapeNode(ellipseOf: CGSize(width: 90, height: 22))
        shadow.fillColor = SKColor(white: 0, alpha: 0.28)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        playerRoot.addChild(shadow)

        playerSprite = SKSpriteNode(imageNamed: "playerBack")
        playerSprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        playerRoot.addChild(playerSprite)
        startBob()

        layoutBackground(backgroundA)
        layoutBackground(backgroundB)
        layoutCorridor(corridorA)
        layoutCorridor(corridorB)
        dressCorridor(corridorA, world: currentWorld())
        dressCorridor(corridorB, world: nextWorld())
        layoutLaneGuides()
        placePlayer()
        buildScenery()

        hud = makeHUDLabel()
        foodHud = makeHUDLabel()
        addChild(makeHUDChip(name: "hudBack"))
        addChild(makeHUDChip(name: "foodBack"))
        addChild(hud)
        addChild(foodHud)
        layoutHUD()

        overlay = SKNode()
        overlay.zPosition = 220
        overlay.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        addChild(overlay)

        flash = SKSpriteNode(color: .white, size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.zPosition = 210
        flash.alpha = 0
        addChild(flash)
    }

    private func makeHUDChip(name: String) -> SKSpriteNode {
        let chip = SKSpriteNode(imageNamed: "uiHud")
        chip.name = name
        chip.size = CGSize(width: 150, height: 40)
        chip.zPosition = 199
        return chip
    }

    private func makeHUDLabel() -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = 17
        label.fontColor = SKColor(red: 0.18, green: 0.28, blue: 0.42, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        label.zPosition = 200
        return label
    }

    private func layoutHUD() {
        let y = size.height - topSafe - 28
        if let back = childNode(withName: "hudBack") {
            back.position = CGPoint(x: size.width * 0.28, y: y)
        }
        if let back = childNode(withName: "foodBack") {
            back.position = CGPoint(x: size.width * 0.74, y: y)
        }
        hud.position = CGPoint(x: size.width * 0.28 - 28, y: y)
        foodHud.position = CGPoint(x: size.width * 0.74 - 28, y: y)
        hud.text = hud.text ?? "0 m"
        foodHud.text = foodHud.text ?? "food 0"
    }

    private func makeCorridor() -> SKSpriteNode {
        let ground = SKTexture(imageNamed: World.city.groundName)
        let node = SKSpriteNode(texture: ground)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.blendMode = .alpha
        node.shader = makeCorridorShader(world: .city)
        return node
    }

    private static let corridorShaderSource = """
    void main() {
        float x = v_tex_coord.x - 0.5;
        float y = v_tex_coord.y;
        float horizon = u_horizon;
        float player = u_player;

        float roadHalf;
        if (y < horizon) {
            float f = clamp(y / max(horizon, 0.001), 0.0, 1.0);
            roadHalf = mix(u_roadBot, u_roadTop, f);
        } else {
            float f = clamp((y - horizon) / max(1.0 - horizon, 0.001), 0.0, 1.0);
            roadHalf = mix(u_roadTop, u_skyGap, f);
        }

        float t = (y - horizon) / min(player - horizon, -0.001);
        float aFar = 1.0 / u_zFar;
        float aNear = 1.0 / u_zNear;
        float a = aFar + t * (aNear - aFar);
        a = max(a, 0.12);
        float z = 1.0 / a;

        float edge = smoothstep(roadHalf - 0.016, roadHalf + 0.01, abs(x));
        float sky = smoothstep(horizon - 0.01, horizon + 0.05, y);
        float skyHole = (1.0 - edge) * sky;

        vec2 gUV = vec2(x / z * u_gRepeat + 0.5, u_scroll / z);
        float across = abs(x) - roadHalf;
        vec2 wUV = vec2(across * 3.2 + u_scroll * 0.55 * u_wRepeat, y * u_wUp);
        vec4 ground = texture2D(u_texture, fract(gUV));
        vec4 wall = texture2D(u_wall, fract(wUV));
        vec4 col = mix(ground, wall, edge);

        float haze = smoothstep(horizon - 0.12, horizon + 0.06, y);
        vec3 fog = vec3(u_hazeR, u_hazeG, u_hazeB);
        col.rgb = mix(col.rgb, fog, haze * mix(0.45, 0.18, edge));

        float alpha = 1.0 - skyHole;

        gl_FragColor = vec4(col.rgb * alpha, alpha);
    }
    """

    private func makeCorridorShader(world: World) -> SKShader {
        let wall = SKTexture(imageNamed: world.wallName)
        wall.filteringMode = .linear
        let haze = world.haze
        let wr = world.wallRepeat
        let shader = SKShader(source: Self.corridorShaderSource)
        shader.uniforms = [
            SKUniform(name: "u_wall", texture: wall),
            SKUniform(name: "u_scroll", float: 0),
            SKUniform(name: "u_horizon", float: 0.54),
            SKUniform(name: "u_player", float: 0.19),
            SKUniform(name: "u_zNear", float: Float(zNear)),
            SKUniform(name: "u_zFar", float: Float(zFar)),
            SKUniform(name: "u_roadTop", float: 0.11),
            SKUniform(name: "u_roadBot", float: 0.44),
            SKUniform(name: "u_skyGap", float: 0.27),
            SKUniform(name: "u_gRepeat", float: 5.2),
            SKUniform(name: "u_wRepeat", float: wr.0),
            SKUniform(name: "u_wUp", float: wr.1),
            SKUniform(name: "u_hazeR", float: Float(haze.0)),
            SKUniform(name: "u_hazeG", float: Float(haze.1)),
            SKUniform(name: "u_hazeB", float: Float(haze.2))
        ]
        return shader
    }

    private func layoutCorridor(_ node: SKSpriteNode?) {
        guard let node else { return }
        node.size = size
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let h = Float(horizonY / max(size.height, 1))
        let p = Float(playerY / max(size.height, 1))
        node.shader?.uniformNamed("u_horizon")?.floatValue = h
        node.shader?.uniformNamed("u_player")?.floatValue = p
        let top = Float(spread(atY: horizonY) * 1.55 / max(size.width, 1))
        node.shader?.uniformNamed("u_roadTop")?.floatValue = top
    }

    private func dressCorridor(_ node: SKSpriteNode?, world: World) {
        guard let node else { return }
        let scroll = node.shader?.uniformNamed("u_scroll")?.floatValue ?? 0
        let ground = SKTexture(imageNamed: world.groundName)
        ground.filteringMode = .linear
        node.texture = ground
        node.shader = makeCorridorShader(world: world)
        layoutCorridor(node)
        node.shader?.uniformNamed("u_scroll")?.floatValue = scroll
    }

    private func layoutBackground(_ node: SKSpriteNode?) {
        guard let node else { return }
        let ts = node.texture?.size() ?? CGSize(width: 9, height: 16)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.58)
        let coverW = size.width / max(ts.width, 1)
        let skyH = size.height - horizonY
        let coverSky = skyH / max(0.42 * ts.height, 1)
        node.setScale(max(coverW, coverSky) * 1.08)
        node.position = CGPoint(x: size.width / 2, y: horizonY)
    }

    private func layoutLaneGuides() {
        guard let laneGuides else { return }
        laneGuides.removeAllChildren()
        let center = size.width / 2
        func addRail(scale: CGFloat, alpha: CGFloat, width: CGFloat) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center + spread(atY: horizonY) * scale, y: horizonY))
            path.addLine(to: CGPoint(x: center + spread(atY: 0) * scale, y: 0))
            let line = SKShapeNode(path: path)
            line.strokeColor = SKColor(white: 1, alpha: alpha)
            line.lineWidth = width
            line.lineCap = .round
            laneGuides.addChild(line)
        }
        addRail(scale: -0.5, alpha: 0.55, width: 3)
        addRail(scale: 0.5, alpha: 0.55, width: 3)
        addRail(scale: -1.5, alpha: 0.22, width: 2)
        addRail(scale: 1.5, alpha: 0.22, width: 2)
    }

    private func placePlayer() {
        guard let playerRoot, let playerSprite else { return }
        visualX = laneX(lane, y: playerY)
        playerRoot.position = CGPoint(x: visualX, y: playerY)
        let rawWidth = playerSprite.texture?.size().width ?? 400
        playerScale = (size.width * 0.28) / max(rawWidth, 1)
        playerSprite.setScale(playerScale)
        shadow.setScale(playerScale * 2.2)
        shadow.position = CGPoint(x: 0, y: 8)
        shadow.alpha = 1
    }

    private func startBob() {
        playerSprite.removeAction(forKey: "bob")
        let bob = SKAction.repeatForever(
            .sequence([
                .moveBy(x: 0, y: 4, duration: 0.22),
                .moveBy(x: 0, y: -4, duration: 0.22)
            ])
        )
        playerSprite.run(bob, withKey: "bob")
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = min(CGFloat(1.0 / 30.0), CGFloat(frameDelta(currentTime)))
        let rush = pixelSpeed(atZ: zNear)
        if state == .running {
            scrollCorridor(dt: dt, speedScale: 1)
            updateScenery(dt: dt, speedScale: 1)
            spawnSpeedLines(dt: dt, speed: rush)
            updateWorlds(dt: dt)
        } else if state == .ready {
            scrollCorridor(dt: dt, speedScale: 0.45)
            updateScenery(dt: dt, speedScale: 0.45)
            updateWorlds(dt: dt * 0.45)
        }

        guard state == .running else { return }

        timeAlive += dt
        runSpeed = min(0.58, 0.20 + timeAlive * 0.012)
        meters += rush * dt * 0.08
        spawnTimer -= dt
        if spawnTimer <= 0 {
            spawnWave()
            spawnTimer = max(0.62, 1.15 - timeAlive * 0.016)
        }

        updateJump(dt: dt)
        updateSteer(dt: dt)
        updateRide()

        let dz = zSpeed() * dt
        for item in items {
            let prevZ = item.z
            item.z -= dz
            item.position.y = screenY(forZ: item.z)
            item.position.x = laneX(item.lane, y: item.position.y)
            let target = size.width * itemWidth(item.kind) * scale(forZ: item.z)
            item.setScale(target / max(item.baseWidth, 1))
            item.zPosition = 20 + (zFar - item.z) * 50
            if prevZ >= zFar - 0.04 {
                item.alpha = min(1, (zFar - item.z) / 0.04)
            } else {
                item.alpha = 1
            }
        }

        resolveContacts(dz: dz)

        items.removeAll { item in
            if item.position.y < -90 || item.zBack < 0.07 {
                item.removeFromParent()
                return true
            }
            return false
        }

        hud.text = String(format: "%.0f m", meters)
        foodHud.text = "food \(food)"
    }

    private func updateWorlds(dt: CGFloat) {
        if fadingWorld {
            fadeTime += dt
            let t = min(1, fadeTime / worldFade)
            let smooth = t * t * (3 - 2 * t)
            backgroundB.alpha = smooth
            corridorB.alpha = smooth
            corridorA.alpha = 1 - smooth * 0.85
            backgroundColor = lerpColor(currentWorld().wash, nextWorld().wash, smooth)
            if t >= 1 {
                fadingWorld = false
                worldIndex = (worldIndex + 1) % World.allCases.count
                backgroundA.texture = SKTexture(imageNamed: currentWorld().imageName)
                layoutBackground(backgroundA)
                backgroundA.alpha = 1
                backgroundB.alpha = 0
                backgroundB.texture = SKTexture(imageNamed: nextWorld().imageName)
                layoutBackground(backgroundB)
                dressCorridor(corridorA, world: currentWorld())
                dressCorridor(corridorB, world: nextWorld())
                corridorA.alpha = 1
                corridorB.alpha = 0
                retintScenery()
                backgroundColor = currentWorld().wash
                worldTime = 0
            }
            return
        }

        worldTime += dt

        if worldTime >= worldHold {
            fadingWorld = true
            fadeTime = 0
            backgroundB.texture = SKTexture(imageNamed: nextWorld().imageName)
            layoutBackground(backgroundB)
            backgroundB.alpha = 0
            dressCorridor(corridorB, world: nextWorld())
            corridorB.alpha = 0
        }
    }

    private func lerpColor(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return SKColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: 1
        )
    }

    private func updateJump(dt: CGFloat) {
        if jumping {
            hangLeft -= dt
            if hangLeft <= 0 {
                slamDown()
            }
        }

        let floor: CGFloat = onPlatform ? platformLift : 0
        let target: CGFloat = floor + (jumping ? jumpPeak : 0)
        let rate: CGFloat = jumping ? 14 : 22
        jumpOffset += (target - jumpOffset) * min(1, rate * dt)
        if jumpOffset < 0.5 && !onPlatform { jumpOffset = 0 }

        playerSprite.position.y = jumpOffset
        let air = min(1, jumpOffset / max(jumpPeak + platformLift, 1))
        shadow.alpha = 0.28 + (1 - air) * 0.72
        shadow.setScale(playerScale * (2.2 - air * 1.1))
        shadow.position.y = 8 - jumpOffset * 0.15
        playerSprite.xScale = playerScale * (1 + air * 0.04)
        playerSprite.yScale = playerScale * (1 - air * 0.04)

        let airborne = isHighEnough
        if wasAirborne && !airborne && !jumping {
            puff(at: CGPoint(x: visualX, y: playerY), count: 7, color: SKColor(white: 1, alpha: 0.9))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            startBob()
        }
        wasAirborne = airborne
    }

    private func updateSteer(dt: CGFloat) {
        let goal = laneX(lane, y: playerY)
        visualX += (goal - visualX) * min(1, 22 * dt)
        playerRoot.position = CGPoint(x: visualX, y: playerY)
        tilt *= max(0, 1 - 10 * dt)
        if abs(tilt) < 0.01 { tilt = 0 }
        playerSprite.zRotation = tilt
    }

    private func updateRide() {
        guard onPlatform else { return }
        let stillOn = items.contains { $0.isRideable && $0.lane == lane && treeOverlaps($0) }
        if !stillOn {
            onPlatform = false
            puff(at: CGPoint(x: visualX, y: playerY + platformLift), count: 5, color: SKColor(white: 1, alpha: 0.85))
        }
    }

    private func scrollCorridor(dt: CGFloat, speedScale: CGFloat) {
        worldScroll += zSpeed() * dt * speedScale * 2.8
        let s = Float(worldScroll)
        corridorA.shader?.uniformNamed("u_scroll")?.floatValue = s
        corridorB.shader?.uniformNamed("u_scroll")?.floatValue = s
    }

    private func buildScenery() {
        props.forEach { $0.removeFromParent() }
        props.removeAll()
        let world = currentWorld()
        let kit = world.kit
        let rows = 10
        for kind in 0..<kit.count {
            for i in 0..<rows {
                for side: CGFloat in [-1, 1] {
                    let spec = kit[kind]
                    let prop = SideProp(imageNamed: spec.name)
                    prop.anchorPoint = CGPoint(x: 0.5, y: 0)
                    prop.side = side
                    prop.flip = side > 0 ? -1 : 1
                    prop.artSlot = kind
                    prop.rail = spec.rail + (i % 2 == 0 ? 0 : 0.12)
                    let stagger = CGFloat(kind) * (propSpacing * 0.33)
                    prop.z = zNear + 0.03 + CGFloat(i) * 0.075 + stagger
                    dressProp(prop, world: world)
                    worldNode.addChild(prop)
                    props.append(prop)
                }
            }
        }
        placeAllProps()
    }

    private func dressProp(_ prop: SideProp, world: World) {
        let kit = world.kit
        let spec = kit[prop.artSlot % kit.count]
        let tex = SKTexture(imageNamed: spec.name)
        tex.filteringMode = .linear
        prop.texture = tex
        prop.baseWidth = tex.size().width
        prop.widthFactor = spec.width
        prop.rail = spec.rail + (prop.rail > spec.rail + 0.06 ? 0.12 : 0)
    }

    private func retintScenery() {
        let world = currentWorld()
        for prop in props {
            dressProp(prop, world: world)
        }
        placeAllProps()
    }

    private func placeAllProps() {
        for prop in props { placeProp(prop) }
    }

    private func placeProp(_ prop: SideProp) {
        let y = screenY(forZ: prop.z)
        // Same spread as the path. Near props rush off the sides instead of growing in place.
        let xOff = spread(atY: y) * prop.rail
        prop.position = CGPoint(
            x: size.width / 2 + prop.side * xOff,
            y: y
        )
        let s = (size.width * prop.widthFactor * scale(forZ: prop.z)) / max(prop.baseWidth, 1)
        prop.xScale = prop.flip * s
        prop.yScale = s
        // Same draw order as coyotes and cat trees so a near plant can pass a far coyote.
        prop.zPosition = 20 + (zFar - prop.z) * 50
        if prop.z > zFar - 0.05 {
            prop.alpha = max(0, (zFar - prop.z) / 0.05)
        } else if prop.z < 0.12 {
            prop.alpha = max(0, (prop.z - 0.07) / 0.05)
        } else {
            prop.alpha = 1
        }
    }

    private func updateScenery(dt: CGFloat, speedScale: CGFloat) {
        let dz = zSpeed() * dt * speedScale
        var farthest = props.map(\.z).max() ?? zFar
        let wrapWorld = fadingWorld ? nextWorld() : currentWorld()
        for prop in props {
            prop.z -= dz
            if prop.z < 0.07 {
                farthest = max(farthest, zFar) + propSpacing
                prop.z = farthest
                dressProp(prop, world: wrapWorld)
            }
            placeProp(prop)
        }
    }

    private func spawnSpeedLines(dt: CGFloat, speed: CGFloat) {
        lineTimer -= dt
        if lineTimer <= 0 {
            lineTimer = 0.07
            let line = SKSpriteNode(color: SKColor(white: 1, alpha: 0.35), size: CGSize(width: 2, height: 28))
            let lanePick = Int.random(in: 0...2)
            line.position = CGPoint(x: laneX(lanePick, y: spawnY * 0.7), y: spawnY * 0.85)
            line.zPosition = 6
            speedLines.addChild(line)
            let dist = spawnY
            line.run(.sequence([
                .group([
                    .moveBy(x: 0, y: -dist, duration: Double(dist / max(speed, 1))),
                    .fadeOut(withDuration: Double(dist / max(speed, 1)))
                ]),
                .removeFromParent()
            ]))
        }
    }

    private var lastTime: TimeInterval = 0
    private func frameDelta(_ currentTime: TimeInterval) -> TimeInterval {
        if lastTime == 0 {
            lastTime = currentTime
            return 1.0 / 60.0
        }
        let value = currentTime - lastTime
        lastTime = currentTime
        return value
    }

    private func itemWidth(_ kind: Kind) -> CGFloat {
        switch kind {
        case .coyote: return 0.20
        case .food: return 0.13
        case .tree: return 0.22
        }
    }

    // MARK: - Spawning

    private func spawnWave() {
        let patterns: [[(Kind, Int, CGFloat)]] = [
            [(.coyote, 0, 0)],
            [(.coyote, 1, 0)],
            [(.coyote, 2, 0)],
            [(.coyote, 0, 0), (.food, 1, 0)],
            [(.coyote, 0, 0), (.coyote, 2, 0)],
            [(.coyote, 0, 0), (.coyote, 1, 0)],
            [(.coyote, 1, 0), (.food, 1, -55)],
            [(.tree, 1, 0)],
            [(.tree, 0, 0), (.coyote, 2, 0)],
            [(.tree, 2, 0), (.coyote, 0, 0), (.food, 1, 0)],
            [(.tree, 0, 0), (.tree, 1, 0), (.food, 2, 0)],
            [(.tree, 1, 0), (.food, 1, -40)],
            [(.food, 0, 0), (.food, 1, -30), (.food, 2, -60)],
            [(.coyote, 0, 0), (.tree, 2, 0)],
            [(.coyote, 1, 0), (.tree, 0, 0), (.coyote, 2, 0)]
        ]
        let pattern = patterns.randomElement() ?? [(.coyote, 1, 0)]
        let rot = Int.random(in: 0...2)
        for (kind, rawLane, dy) in pattern {
            addItem(kind, lane: (rawLane + rot) % 3, y: spawnY + dy)
        }
    }

    private func addItem(_ kind: Kind, lane: Int, y: CGFloat) {
        let name: String
        switch kind {
        case .coyote: name = "coyoteOpen"
        case .food: name = "wetFood"
        case .tree: name = "catTree"
        }
        let item = TrackItem(imageNamed: name)
        item.kind = kind
        item.lane = lane
        item.z = depthZ(forScreenY: y)
        if kind == .tree {
            item.zLength = 0.62
        }
        item.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        item.baseWidth = item.texture?.size().width ?? item.size.width
        item.position = CGPoint(x: laneX(lane, y: y), y: screenY(forZ: item.z))
        let start = size.width * itemWidth(kind) * scale(forZ: item.z)
        item.setScale(start / max(item.baseWidth, 1))
        worldNode.addChild(item)
        items.append(item)
        if kind == .food {
            item.run(.repeatForever(.rotate(byAngle: .pi, duration: 1.4)))
        } else if kind == .coyote {
            let snarl = SKAction.animate(with: coyoteFrames, timePerFrame: 0.11, resize: false, restore: false)
            item.run(.repeatForever(snarl), withKey: "snarl")
        }
    }

    // MARK: - Contacts

    private func resolveContacts(dz: CGFloat) {
        for item in items where item.lane == lane {
            if item.isRideable {
                handleTree(item, dz: dz)
                continue
            }
            let prevZ = item.z + dz
            let crossed = prevZ >= zNear && item.z < zNear
            guard crossed else { continue }
            if item.isCollectible {
                collect(item)
            } else if item.jumpable && isHighEnough {
                continue
            } else if !e2eGod {
                crash()
                return
            }
        }
    }

    private func handleTree(_ item: TrackItem, dz: CGFloat) {
        let entered = (item.z + dz) > zNear && item.z <= zNear
        let overlapping = treeOverlaps(item)
        guard overlapping || entered else { return }

        if onPlatform {
            return
        }
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
        playerSprite.removeAction(forKey: "bob")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        puff(at: CGPoint(x: visualX, y: playerY + platformLift), count: 8, color: SKColor(red: 0.85, green: 0.72, blue: 0.48, alpha: 1))
        startBob()
    }

    private func collect(_ item: TrackItem) {
        food += 1
        meters += 8
        let spot = item.position
        item.removeFromParent()
        items.removeAll { $0 === item }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        puff(at: spot, count: 8, color: SKColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1))
        popText("+food", at: spot)
    }

    private func crash() {
        state = .dead
        jumping = false
        onPlatform = false
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        playerSprite.removeAction(forKey: "bob")
        flash.alpha = 0.7
        flash.run(.fadeOut(withDuration: 0.25))
        shakeWorld()
        if meters > bestMeters {
            bestMeters = meters
            UserDefaults.standard.set(Double(bestMeters), forKey: "bestMeters")
        }
        showDead()
    }

    private func shakeWorld() {
        worldNode.removeAction(forKey: "shake")
        let shake = SKAction.sequence([
            .moveBy(x: 10, y: 4, duration: 0.03),
            .moveBy(x: -16, y: -6, duration: 0.04),
            .moveBy(x: 12, y: 3, duration: 0.04),
            .moveBy(x: -6, y: -1, duration: 0.04),
            .moveTo(x: 0, duration: 0.05)
        ])
        worldNode.position = .zero
        worldNode.run(shake, withKey: "shake")
    }

    private func puff(at point: CGPoint, count: Int, color: SKColor) {
        for _ in 0..<count {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...7))
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.position = point
            dot.zPosition = 170
            worldNode.addChild(dot)
            let dx = CGFloat.random(in: -36...36)
            let dy = CGFloat.random(in: 10...50)
            dot.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.35),
                    .fadeOut(withDuration: 0.35),
                    .scale(to: 0.2, duration: 0.35)
                ]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        swipeStart = touches.first?.location(in: self)
        swipeConsumed = false
        if state == .ready {
            startRun()
        } else if state == .dead {
            resetRun()
            startRun()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .running, !swipeConsumed,
              let start = swipeStart,
              let now = touches.first?.location(in: self) else { return }
        trySwipe(from: start, to: now, minimum: 22)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .running, !swipeConsumed,
              let start = swipeStart,
              let end = touches.first?.location(in: self) else { return }
        trySwipe(from: start, to: end, minimum: 24)
        swipeStart = nil
    }

    private func trySwipe(from start: CGPoint, to end: CGPoint, minimum: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) > minimum else { return }
        swipeConsumed = true
        if abs(dx) > abs(dy) {
            moveLane(dx > 0 ? 1 : -1)
        } else if dy > 0 {
            jump()
        } else {
            slamDown()
        }
    }

    private func moveLane(_ delta: Int) {
        let next = max(0, min(2, lane + delta))
        guard next != lane else { return }
        if onPlatform {
            let hasTree = items.contains { $0.isRideable && $0.lane == next && treeOverlaps($0) }
            if !hasTree {
                onPlatform = false
            }
        }
        lane = next
        tilt = delta > 0 ? -0.2 : 0.2
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func jump() {
        guard !jumping else { return }
        jumping = true
        hangLeft = onPlatform ? 0.95 : 1.15
        playerSprite.removeAction(forKey: "bob")
        playerSprite.position.y = jumpOffset
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func slamDown() {
        guard jumping || jumpOffset > 2 else { return }
        jumping = false
        hangLeft = 0
    }

    // MARK: - States

    private func startRun() {
        overlay.removeAllChildren()
        overlay.isHidden = true
        state = .running
        lastTime = 0
        spawnTimer = 0.9
        worldNode.position = .zero
        startBob()
    }

    private func resetRun() {
        items.forEach { $0.removeFromParent() }
        items.removeAll()
        speedLines.removeAllChildren()
        lane = 1
        jumping = false
        jumpOffset = 0
        hangLeft = 0
        wasAirborne = false
        onPlatform = false
        tilt = 0
        timeAlive = 0
        meters = 0
        food = 0
        runSpeed = 0.22
        playerSprite.zRotation = 0
        playerSprite.position.y = 0
        playerSprite.xScale = playerScale
        playerSprite.yScale = playerScale
        placePlayer()
        overlay.removeAllChildren()
        flash.alpha = 0
        worldNode.position = .zero
        resetWorld()
    }

    private func resetWorld() {
        fadingWorld = false
        fadeTime = 0
        worldTime = 0
        worldIndex = 0
        worldScroll = 0
        backgroundA.texture = SKTexture(imageNamed: World.city.imageName)
        backgroundB.texture = SKTexture(imageNamed: World.jungle.imageName)
        backgroundA.alpha = 1
        backgroundB.alpha = 0
        layoutBackground(backgroundA)
        layoutBackground(backgroundB)
        dressCorridor(corridorA, world: currentWorld())
        dressCorridor(corridorB, world: nextWorld())
        corridorA.alpha = 1
        corridorB.alpha = 0
        corridorA.shader?.uniformNamed("u_scroll")?.floatValue = 0
        corridorB.shader?.uniformNamed("u_scroll")?.floatValue = 0
        backgroundColor = World.city.wash
        buildScenery()
    }

    private func showReady() {
        state = .ready
        overlay.isHidden = false
        overlay.removeAllChildren()
        addOverlayPanel(height: 300)
        addOverlayTitle("Cat Cart")
        addOverlayLine("Swipe to steer", y: -28)
        addOverlayLine("Jump coyotes  ·  ride the cat trees", y: -56)
        addOverlayLine("Grab the wet food", y: -84)
        addOverlayLine("Tap to dash", y: -122)
        let paw = SKSpriteNode(imageNamed: "uiButton")
        paw.size = CGSize(width: 64, height: 64)
        paw.position = CGPoint(x: 0, y: -168)
        overlay.addChild(paw)
        hud.text = "0 m"
        foodHud.text = "food 0"
    }

    private func showDead() {
        overlay.isHidden = false
        overlay.removeAllChildren()
        addOverlayPanel(height: 230)
        addOverlayTitle("Oh no!")
        addOverlayLine(String(format: "%.0f m   ·   %d food", meters, food), y: -38)
        addOverlayLine(String(format: "best  %.0f m", bestMeters), y: -68)
        addOverlayLine("Tap to dash again", y: -108)
        let paw = SKSpriteNode(imageNamed: "uiButton")
        paw.size = CGSize(width: 56, height: 56)
        paw.position = CGPoint(x: 0, y: -150)
        overlay.addChild(paw)
    }

    private func addOverlayPanel(height: CGFloat) {
        let panel = SKSpriteNode(imageNamed: "uiPanel")
        panel.size = CGSize(width: size.width * 0.86, height: height)
        panel.position = CGPoint(x: 0, y: -48)
        overlay.addChild(panel)
    }

    private func addOverlayTitle(_ text: String) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 44
        label.fontColor = SKColor(red: 0.16, green: 0.32, blue: 0.48, alpha: 1)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 36)
        overlay.addChild(label)
    }

    private func addOverlayLine(_ text: String, y: CGFloat) {
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = 17
        label.fontColor = SKColor(red: 0.28, green: 0.36, blue: 0.48, alpha: 1)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: y)
        overlay.addChild(label)
    }

    private func popText(_ text: String, at point: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 20
        label.fontColor = SKColor(red: 0.95, green: 0.45, blue: 0.20, alpha: 1)
        label.position = point
        label.zPosition = 180
        worldNode.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 44, duration: 0.4),
                .fadeOut(withDuration: 0.4),
                .scale(to: 1.2, duration: 0.4)
            ]),
            .removeFromParent()
        ]))
    }
}
