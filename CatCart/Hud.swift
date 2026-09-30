import SpriteKit

// The flat layer drawn on top of the 3D world: the two pills, the ready and
// "Oh no!" panels, the crash flash, and a few light speed lines.
// SceneKit draws this SpriteKit scene over every frame (SCNView.overlaySKScene).

final class Hud: SKScene {

    private var metersChip: SKSpriteNode!
    private var foodChip: SKSpriteNode!
    private var metersLabel: SKLabelNode!
    private var foodLabel: SKLabelNode!
    private var panel: SKNode!
    private var flash: SKSpriteNode!
    private var lines: SKNode!
    private var topSafe: CGFloat = 54
    private var shownMeters = -1
    private var shownFood = -1

    private let ink = SKColor(red: 0.16, green: 0.30, blue: 0.46, alpha: 1)
    private let softInk = SKColor(red: 0.28, green: 0.36, blue: 0.48, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        lines = SKNode()
        lines.zPosition = 5
        addChild(lines)

        metersChip = makeChip()
        foodChip = makeChip()
        metersLabel = makeLabel()
        foodLabel = makeLabel()
        [metersChip, foodChip].forEach { addChild($0) }
        [metersLabel, foodLabel].forEach { addChild($0) }

        panel = SKNode()
        panel.zPosition = 50
        addChild(panel)

        flash = SKSpriteNode(color: .white, size: size)
        flash.alpha = 0
        flash.zPosition = 40
        addChild(flash)
        layout(topSafe: topSafe)
    }

    private func makeChip() -> SKSpriteNode {
        let chip = SKSpriteNode(imageNamed: "uiHud")
        chip.size = CGSize(width: 150, height: 40)
        chip.zPosition = 10
        return chip
    }

    private func makeLabel() -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = 17
        label.fontColor = ink
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        label.zPosition = 11
        return label
    }

    func layout(topSafe: CGFloat) {
        self.topSafe = max(topSafe, 54)
        let y = size.height - self.topSafe - 28
        metersChip.position = CGPoint(x: size.width * 0.28, y: y)
        foodChip.position = CGPoint(x: size.width * 0.74, y: y)
        metersLabel.position = CGPoint(x: size.width * 0.28 - 28, y: y)
        foodLabel.position = CGPoint(x: size.width * 0.74 - 28, y: y)
        panel.position = CGPoint(x: size.width / 2, y: size.height * 0.70)
        flash.size = size
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        if let panelBack = panel.childNode(withName: "back") as? SKSpriteNode {
            panelBack.size.width = size.width * 0.86
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard metersChip != nil else { return }
        layout(topSafe: topSafe)
    }

    // MARK: - Pills

    func setMeters(_ meters: Int) {
        guard meters != shownMeters else { return }
        shownMeters = meters
        metersLabel.text = "\(meters) m"
    }

    func setFood(_ food: Int) {
        guard food != shownFood else { return }
        let grew = shownFood >= 0 && food > shownFood
        shownFood = food
        foodLabel.text = "food \(food)"
        if grew {
            // A small pulse on the pill instead of score text flying around the screen.
            foodChip.removeAction(forKey: "pulse")
            foodChip.setScale(1)
            foodChip.run(.sequence([
                .scale(to: 1.12, duration: 0.07),
                .scale(to: 1.0, duration: 0.12)
            ]), withKey: "pulse")
        }
    }

    // MARK: - Panels

    func showReady() {
        panel.removeAllChildren()
        panel.isHidden = false
        addPanelBack(height: 300)
        addTitle("Cat Cart")
        addLine("Swipe to steer", y: -28)
        addLine("Jump coyotes  ·  ride the cat trees", y: -56)
        addLine("Grab the wet food", y: -84)
        addLine("Tap to dash", y: -122)
        addPaw(size: 64, y: -168)
        setMeters(0)
        setFood(0)
    }

    func showDead(meters: Int, food: Int, best: Int) {
        panel.removeAllChildren()
        panel.isHidden = false
        addPanelBack(height: 230)
        addTitle("Oh no!")
        addLine("\(meters) m   ·   \(food) food", y: -38)
        addLine("best  \(best) m", y: -68)
        addLine("Tap to dash again", y: -108)
        addPaw(size: 56, y: -150)
        panel.setScale(0.85)
        panel.alpha = 0
        panel.run(.group([.scale(to: 1, duration: 0.18), .fadeIn(withDuration: 0.18)]))
    }

    func hidePanel() {
        panel.removeAllChildren()
        panel.isHidden = true
        panel.setScale(1)
        panel.alpha = 1
    }

    private func addPanelBack(height: CGFloat) {
        let back = SKSpriteNode(imageNamed: "uiPanel")
        back.name = "back"
        back.size = CGSize(width: size.width * 0.86, height: height)
        back.position = CGPoint(x: 0, y: -48)
        panel.addChild(back)
    }

    private func addTitle(_ text: String) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 44
        label.fontColor = ink
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 36)
        panel.addChild(label)
    }

    private func addLine(_ text: String, y: CGFloat) {
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = 17
        label.fontColor = softInk
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: y)
        panel.addChild(label)
    }

    private func addPaw(size: CGFloat, y: CGFloat) {
        let paw = SKSpriteNode(imageNamed: "uiButton")
        paw.size = CGSize(width: size, height: size)
        paw.position = CGPoint(x: 0, y: y)
        paw.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))
        panel.addChild(paw)
    }

    // MARK: - Effects

    func flashWhite() {
        flash.removeAllActions()
        flash.alpha = 0.7
        flash.run(.fadeOut(withDuration: 0.25))
    }

    /// Thin streaks near the screen edges that sell speed without covering the track.
    func speedLine(strength: CGFloat) {
        let side: CGFloat = Bool.random() ? -1 : 1
        let x = size.width / 2 + side * CGFloat.random(in: 0.32...0.48) * size.width
        let y = CGFloat.random(in: 0.25...0.6) * size.height
        let line = SKSpriteNode(color: SKColor(white: 1, alpha: 0.28 * strength),
                                size: CGSize(width: 2, height: CGFloat.random(in: 30...60)))
        line.position = CGPoint(x: x, y: y)
        // Lean the streak outward, like it's flying past the camera.
        line.zRotation = side * 0.35
        lines.addChild(line)
        let drift = CGVector(dx: side * 60, dy: -140)
        line.run(.sequence([
            .group([.move(by: drift, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .removeFromParent()
        ]))
    }

    func clearLines() {
        lines.removeAllChildren()
    }
}
