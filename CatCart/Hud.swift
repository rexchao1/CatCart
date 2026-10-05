import SpriteKit
import UIKit

// The flat layer drawn on top of the 3D world: the score and food pills, the home screen,
// the "Oh no!" panel, the crash flash, and a few light speed lines.
// SceneKit draws this SpriteKit scene over every frame (SCNView.overlaySKScene).
//
// The big type on the home and crash screens is drawn once with UIKit into a
// picture (rounded system font, thick navy outline, a dropped edge under it) and
// shown as a sprite. SKLabelNode can't do outlines, and this is what makes the
// titles look chunky like a toy box instead of plain text.

final class Hud: SKScene {

    private var scoreChip: SKSpriteNode!
    private var foodChip: SKSpriteNode!
    private var scoreLabel: SKLabelNode!
    private var foodLabel: SKLabelNode!
    private var panel: SKNode!
    private var home: SKNode!
    private var dim: SKSpriteNode!
    private var flash: SKSpriteNode!
    private var lines: SKNode!
    private var hint: SKNode?
    private var topSafe: CGFloat = 54
    private var shownScore = -1
    private var shownFood = -1

    private let ink = SKColor(red: 0.16, green: 0.30, blue: 0.46, alpha: 1)
    private let softInk = SKColor(red: 0.28, green: 0.36, blue: 0.48, alpha: 1)
    /// Deep navy for outlines, the dropped edge under bold type, and shades.
    private let navy = SKColor(red: 0.10, green: 0.17, blue: 0.38, alpha: 1)
    private let icy = SKColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 1)

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

        scoreChip = makeChip()
        foodChip = makeChip()
        scoreLabel = makeLabel()
        foodLabel = makeLabel()
        [scoreChip, foodChip].forEach { addChild($0) }
        [scoreLabel, foodLabel].forEach { addChild($0) }

        // Darkens the world behind the crash panel so the panel pops.
        dim = SKSpriteNode(color: navy, size: size)
        dim.alpha = 0
        dim.zPosition = 45
        addChild(dim)

        panel = SKNode()
        panel.zPosition = 50
        addChild(panel)

        home = SKNode()
        home.zPosition = 50
        home.isHidden = true
        addChild(home)

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
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        scoreChip.position = CGPoint(x: size.width * 0.28, y: y)
        foodChip.position = CGPoint(x: size.width * 0.74, y: y)
        scoreLabel.position = CGPoint(x: size.width * 0.28 - 28, y: y)
        foodLabel.position = CGPoint(x: size.width * 0.74 - 28, y: y)
        panel.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        flash.size = size
        flash.position = center
        dim.size = size
        dim.position = center
        home.childNode(withName: "top")?.position = CGPoint(x: size.width / 2, y: size.height - self.topSafe - 66)
        home.childNode(withName: "bottom")?.position = CGPoint(x: size.width / 2, y: size.height * 0.17)
        for (name, atTop) in [("shadeTop", true), ("shadeBottom", false)] {
            guard let shade = home.childNode(withName: name) as? SKSpriteNode else { continue }
            shade.size = CGSize(width: size.width, height: size.height * 0.36)
            let half = shade.size.height / 2
            shade.position = CGPoint(x: size.width / 2, y: atTop ? size.height - half : half)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard scoreChip != nil else { return }
        layout(topSafe: topSafe)
    }

    // MARK: - Pills

    func setScore(_ score: Int) {
        guard score != shownScore else { return }
        shownScore = score
        scoreLabel.text = score.formatted()
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

    private func setPillsHidden(_ hidden: Bool) {
        for node in [scoreChip, foodChip, scoreLabel, foodLabel] as [SKNode] {
            node.removeAllActions()
            if hidden {
                node.alpha = 0
            } else {
                node.run(.fadeIn(withDuration: 0.3))
            }
        }
    }

    // MARK: - Home

    /// The title screen: big name up top, the kitten in the middle (that's the 3D
    /// scene), and a paw button with the best score at the bottom.
    func showHome(best: Int) {
        panel.removeAllChildren()
        panel.isHidden = true
        dim.alpha = 0
        home.removeAllChildren()
        home.isHidden = false
        home.alpha = 1
        setPillsHidden(true)

        // Soft navy shade along the top and bottom so white type reads over any world.
        home.addChild(shade(name: "shadeTop", fromTop: true, strength: 0.42))
        home.addChild(shade(name: "shadeBottom", fromTop: false, strength: 0.5))

        let top = SKNode()
        top.name = "top"
        home.addChild(top)
        let title = boldText("Cat Cart", size: 76, fill: .white, lowerFill: icy, outlineWidth: 6, drop: 8)
        fit(title, maxWidth: size.width - 36)
        title.zRotation = -0.035
        top.addChild(title)
        // A slow bob so the title feels alive while she waits.
        let bob = SKAction.moveBy(x: 0, y: 5, duration: 1.3)
        bob.timingMode = .easeInEaseOut
        title.run(.repeatForever(.sequence([bob, bob.reversed()])))

        let tag = textSprite("Swipe to steer  ·  jump coyotes  ·  ride cat trees", size: 14, weight: .bold, color: .white)
        fit(tag, maxWidth: size.width - 64)
        let tagWidth = tag.size.width * tag.xScale + 32
        let tagBack = SKShapeNode(rectOf: CGSize(width: tagWidth, height: 32), cornerRadius: 16)
        tagBack.fillColor = navy.withAlphaComponent(0.62)
        tagBack.strokeColor = SKColor(white: 1, alpha: 0.3)
        tagBack.lineWidth = 1.5
        tagBack.position = CGPoint(x: 0, y: -title.size.height / 2 - 18)
        tag.position = tagBack.position
        top.addChild(tagBack)
        top.addChild(tag)

        top.setScale(0.6)
        top.alpha = 0
        top.run(.group([
            .fadeIn(withDuration: 0.3),
            .sequence([.scale(to: 1.06, duration: 0.22), .scale(to: 1, duration: 0.12)])
        ]))

        let bottom = SKNode()
        bottom.name = "bottom"
        home.addChild(bottom)
        let play = pawButton("Tap to play")
        bottom.addChild(play)
        pulse(play)
        if best > 0 {
            let chip = SKSpriteNode(imageNamed: "uiHud")
            chip.size = CGSize(width: 200, height: 46)
            chip.position = CGPoint(x: 0, y: -80)
            bottom.addChild(chip)
            let row = bestRow(best, valueSize: 22)
            // Nudged right of the paw printed on the pill.
            row.position = CGPoint(x: chip.position.x + 14, y: chip.position.y)
            bottom.addChild(row)
        }
        bottom.alpha = 0
        bottom.run(.sequence([.wait(forDuration: 0.15), .fadeIn(withDuration: 0.3)]))
        layout(topSafe: topSafe)
    }

    func hideHome() {
        guard !home.isHidden else { return }
        home.run(.sequence([.fadeOut(withDuration: 0.25), .run { [weak self] in
            self?.home.removeAllChildren()
            self?.home.isHidden = true
        }]))
        setPillsHidden(false)
    }

    // MARK: - Crash panel

    func showDead(score: Int, food: Int, best: Int, newBest: Bool) {
        panel.removeAllChildren()
        panel.isHidden = false
        // The panel shows the numbers now, so the pills step aside.
        setPillsHidden(true)
        dim.removeAllActions()
        dim.run(.fadeAlpha(to: 0.42, duration: 0.3))

        let width = min(size.width * 0.86, 360)
        let back = SKSpriteNode(imageNamed: "uiPanel")
        back.size = CGSize(width: width, height: 236)
        panel.addChild(back)

        // Two big numbers side by side, with a thin line between.
        let column = width * 0.22
        for (x, value, word) in [(-column, score.formatted(), "score"),
                                 (column, "\(food)", "food")] {
            let number = textSprite(value, size: 48, weight: .black, color: ink)
            fit(number, maxWidth: column * 1.7)
            number.position = CGPoint(x: x, y: 26)
            panel.addChild(number)
            let label = textSprite(word, size: 16, weight: .bold, color: softInk)
            label.position = CGPoint(x: x, y: -10)
            panel.addChild(label)
        }
        let divider = SKShapeNode(rectOf: CGSize(width: 2, height: 58), cornerRadius: 1)
        divider.fillColor = softInk.withAlphaComponent(0.22)
        divider.strokeColor = .clear
        divider.position = CGPoint(x: 0, y: 10)
        panel.addChild(divider)

        let row = bestRow(best, valueSize: 19)
        row.position = CGPoint(x: 0, y: -62)
        panel.addChild(row)

        // A pink ribbon across the top edge.
        let banner = SKNode()
        banner.position = CGPoint(x: 0, y: 118)
        banner.zRotation = -0.03
        let ribbon = SKSpriteNode(texture: SKTexture(image: Self.capsuleImage(
            size: CGSize(width: 220, height: 64),
            top: SKColor(red: 1.0, green: 0.56, blue: 0.70, alpha: 1),
            bottom: SKColor(red: 0.93, green: 0.30, blue: 0.50, alpha: 1),
            edge: navy)))
        ribbon.size = ribbon.texture!.size()
        banner.addChild(ribbon)
        let title = boldText("Oh no!", size: 40, fill: .white, outlineWidth: 4, drop: 4)
        title.position = CGPoint(x: 0, y: 3)
        banner.addChild(title)
        panel.addChild(banner)

        let again = pawButton("Dash again")
        again.position = CGPoint(x: 0, y: -182)
        panel.addChild(again)
        pulse(again)

        // Pop in: the panel bounces up, the ribbon drops onto it a beat later.
        panel.setScale(0.6)
        panel.alpha = 0
        panel.run(.group([
            .fadeIn(withDuration: 0.15),
            .sequence([.scale(to: 1.06, duration: 0.18), .scale(to: 1, duration: 0.1)])
        ]))
        banner.alpha = 0
        banner.position.y += 40
        let drop = SKAction.moveBy(x: 0, y: -40, duration: 0.22)
        drop.timingMode = .easeOut
        banner.run(.sequence([.wait(forDuration: 0.12), .group([.fadeIn(withDuration: 0.12), drop])]))

        if newBest {
            // A gold sticker slapped on the corner when she beats her record.
            let sticker = SKNode()
            sticker.position = CGPoint(x: width / 2 - 56, y: 150)
            sticker.zRotation = 0.2
            let badge = SKSpriteNode(texture: SKTexture(image: Self.capsuleImage(
                size: CGSize(width: 128, height: 40),
                top: SKColor(red: 1.0, green: 0.88, blue: 0.40, alpha: 1),
                bottom: SKColor(red: 1.0, green: 0.68, blue: 0.16, alpha: 1),
                edge: navy)))
            badge.size = badge.texture!.size()
            sticker.addChild(badge)
            let words = textSprite("New best!", size: 19, weight: .black, color: navy)
            words.position = CGPoint(x: 0, y: 2)
            sticker.addChild(words)
            panel.addChild(sticker)
            sticker.setScale(0)
            let wobble = SKAction.sequence([
                .rotate(toAngle: 0.26, duration: 0.5, shortestUnitArc: true),
                .rotate(toAngle: 0.14, duration: 0.5, shortestUnitArc: true)
            ])
            sticker.run(.sequence([
                .wait(forDuration: 0.35),
                .scale(to: 1.2, duration: 0.14),
                .scale(to: 1, duration: 0.1),
                .repeatForever(wobble)
            ]))
        }
    }

    func hidePanel() {
        let wasShowing = !panel.isHidden
        panel.removeAllChildren()
        panel.isHidden = true
        panel.setScale(1)
        panel.alpha = 1
        dim.removeAllActions()
        dim.alpha = 0
        if wasShowing {
            setPillsHidden(false)
        }
    }

    // MARK: - Pieces

    /// The play button: a glossy icy-blue capsule with the paw button on its left end.
    private func pawButton(_ text: String) -> SKNode {
        let node = SKNode()
        let width: CGFloat = 250
        let capsule = SKSpriteNode(texture: SKTexture(image: Self.capsuleImage(
            size: CGSize(width: width, height: 66),
            top: SKColor(red: 0.62, green: 0.84, blue: 1.0, alpha: 1),
            bottom: SKColor(red: 0.27, green: 0.56, blue: 0.90, alpha: 1),
            edge: navy)))
        capsule.size = capsule.texture!.size()
        capsule.position = CGPoint(x: 14, y: 0)
        node.addChild(capsule)
        let label = boldText(text, size: 27, fill: .white, outlineWidth: 3.5, drop: 3)
        fit(label, maxWidth: width - 104)
        label.position = CGPoint(x: capsule.position.x + 32, y: 3)
        node.addChild(label)
        let paw = SKSpriteNode(imageNamed: "uiButton")
        paw.size = CGSize(width: 88, height: 90)
        paw.position = CGPoint(x: capsule.position.x - width / 2 + 16, y: 3)
        node.addChild(paw)
        return node
    }

    /// "BEST 8,820" with the word small and the number big.
    private func bestRow(_ best: Int, valueSize: CGFloat) -> SKNode {
        let row = SKNode()
        let word = textSprite("BEST", size: valueSize * 0.6, weight: .heavy, color: softInk)
        let value = textSprite(best.formatted(), size: valueSize, weight: .black, color: ink)
        let gap: CGFloat = 8
        let total = word.size.width + gap + value.size.width
        word.anchorPoint.x = 0
        value.anchorPoint.x = 0
        word.position = CGPoint(x: -total / 2, y: 0)
        value.position = CGPoint(x: -total / 2 + word.size.width + gap, y: 0)
        row.addChild(word)
        row.addChild(value)
        return row
    }

    private func pulse(_ node: SKNode) {
        let grow = SKAction.scale(to: 1.05, duration: 0.55)
        grow.timingMode = .easeInEaseOut
        let shrink = SKAction.scale(to: 1.0, duration: 0.55)
        shrink.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([grow, shrink])))
    }

    private func fit(_ sprite: SKSpriteNode, maxWidth: CGFloat) {
        if sprite.size.width > maxWidth {
            sprite.setScale(maxWidth / sprite.size.width)
        }
    }

    /// A navy wash that fades out toward the middle of the screen.
    private func shade(name: String, fromTop: Bool, strength: CGFloat) -> SKSpriteNode {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 128)).image { ctx in
            let dark = navy.withAlphaComponent(strength).cgColor
            let clear = navy.withAlphaComponent(0).cgColor
            let colors = (fromTop ? [dark, clear] : [clear, dark]) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.name = name
        sprite.zPosition = -1
        return sprite
    }

    // MARK: - Drawn type

    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: rounded, size: size)
    }

    /// Plain text in the rounded font, as a sprite centered on its capital letters.
    private func textSprite(_ text: String, size: CGFloat, weight: UIFont.Weight, color: SKColor) -> SKSpriteNode {
        styledText(text, font: Self.rounded(size, weight), fill: color, lowerFill: nil, outline: nil, outlineWidth: 0, drop: 0)
    }

    /// Chunky toy-box type: a navy copy dropped underneath, a thick navy outline,
    /// then the face. With lowerFill the bottom of each letter gets a second color.
    private func boldText(_ text: String, size: CGFloat, fill: SKColor, lowerFill: SKColor? = nil,
                          outlineWidth: CGFloat, drop: CGFloat) -> SKSpriteNode {
        styledText(text, font: Self.rounded(size, .black), fill: fill, lowerFill: lowerFill,
                   outline: navy, outlineWidth: outlineWidth, drop: drop)
    }

    private func styledText(_ text: String, font: UIFont, fill: SKColor, lowerFill: SKColor?,
                            outline: SKColor?, outlineWidth: CGFloat, drop: CGFloat) -> SKSpriteNode {
        let string = text as NSString
        let textSize = string.size(withAttributes: [.font: font])
        let pad = ceil(outlineWidth) + 1
        let canvas = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 2 + drop))
        // NSAttributedString measures stroke width in percent of the font size, and
        // centers it on the letter edge, so it's doubled to show outlineWidth outside.
        let strokePercent = outlineWidth * 2 / font.pointSize * 100
        let image = UIGraphicsImageRenderer(size: canvas).image { ctx in
            func draw(_ color: SKColor, stroke: CGFloat, dy: CGFloat) {
                string.draw(at: CGPoint(x: pad, y: pad + dy), withAttributes: [
                    .font: font, .foregroundColor: color, .strokeColor: color, .strokeWidth: stroke
                ])
            }
            if let outline {
                if drop > 0 { draw(outline, stroke: -strokePercent, dy: drop) }
                draw(outline, stroke: -strokePercent, dy: 0)
            }
            draw(fill, stroke: 0, dy: 0)
            if let lowerFill {
                // Like two-tone candy: the lower part of each capital is a touch icier.
                let cut = pad + font.ascender - font.capHeight * 0.42
                ctx.cgContext.saveGState()
                ctx.cgContext.clip(to: CGRect(x: 0, y: cut, width: canvas.width, height: canvas.height - cut))
                draw(lowerFill, stroke: 0, dy: 0)
                ctx.cgContext.restoreGState()
            }
        }
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.size = image.size
        // Center on the capital letters, not the whole line box, which has empty
        // room for descenders below. Keeps text optically centered in buttons.
        let capCenter = pad + font.ascender - font.capHeight / 2
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1 - capCenter / canvas.height)
        return sprite
    }

    /// A glossy capsule with a darker lip under it, like a pressable toy button.
    private static func capsuleImage(size: CGSize, top: SKColor, bottom: SKColor, edge: SKColor) -> UIImage {
        let line: CGFloat = 3
        let lip: CGFloat = 5
        let canvas = CGSize(width: size.width + line * 2, height: size.height + lip + line * 2)
        return UIGraphicsImageRenderer(size: canvas).image { ctx in
            let cg = ctx.cgContext
            let body = CGRect(x: line, y: line, width: size.width, height: size.height)
            let radius = size.height / 2
            edge.setFill()
            UIBezierPath(roundedRect: body.offsetBy(dx: 0, dy: lip), cornerRadius: radius).fill()

            let path = UIBezierPath(roundedRect: body, cornerRadius: radius)
            cg.saveGState()
            path.addClip()
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
            // Gloss across the top half.
            SKColor(white: 1, alpha: 0.35).setFill()
            let gloss = CGRect(x: body.minX + radius * 0.6, y: body.minY + 5,
                               width: body.width - radius * 1.2, height: body.height * 0.36)
            UIBezierPath(roundedRect: gloss, cornerRadius: gloss.height / 2).fill()
            cg.restoreGState()

            edge.setStroke()
            path.lineWidth = line
            path.stroke()
        }
    }

    // MARK: - Hint

    /// One line of big type low on the screen, for a move the player hasn't
    /// learned yet. It bobs gently so it's noticed without covering the road.
    func showHint(_ text: String) {
        hideHint()
        let node = SKNode()
        node.zPosition = 30
        // Below the cart, so it never covers her or the road ahead.
        node.position = CGPoint(x: size.width / 2, y: size.height * 0.13)
        let label = boldText(text, size: 30, fill: .white, lowerFill: icy, outlineWidth: 4, drop: 3)
        fit(label, maxWidth: size.width - 40)
        node.addChild(label)
        node.alpha = 0
        node.setScale(0.8)
        addChild(node)
        node.run(.group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.2)]))
        let bob = SKAction.moveBy(x: 0, y: -10, duration: 0.4)
        bob.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([bob, bob.reversed()])))
        hint = node
    }

    func hideHint() {
        guard let node = hint else { return }
        hint = nil
        node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
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
