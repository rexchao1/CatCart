import SpriteKit
import UIKit

// The flat layer drawn on top of the 3D world: the score and food pills, the home screen,
// the "Oh no!" panel, the crash flash, a few light speed lines, and the power-up
// callout and timers.
// SceneKit draws this SpriteKit scene over every frame (SCNView.overlaySKScene).
//
// The big type on the home and crash screens is drawn once with UIKit into a
// picture (rounded system font, thick navy outline, a dropped edge under it) and
// shown as a sprite. SKLabelNode can't do outlines, and this is what makes the
// titles look chunky like a toy box instead of plain text.

final class Hud: SKScene {

    /// The score and food pills are ordinary UIKit views on top of the game view,
    /// not part of this scene. See PillBar for why.
    weak var pills: PillBar?
    /// The power-up timers, UIKit like the pills.
    weak var powerBar: PowerBar?
    private var callout: SKNode?
    private var panel: SKNode!
    private var home: SKNode!
    private var dim: SKSpriteNode!
    private var flash: SKSpriteNode!
    private var lines: SKNode!
    private var linePool: [SKSpriteNode] = []
    private var nextLine = 0
    /// Test-only: CATCART_LINES=0 turns the speed lines off, to rule them in or out
    /// when something on the HUD misbehaves on the phone.
    private let linesOn = ProcessInfo.processInfo.environment["CATCART_LINES"] != "0"
    private var hint: SKNode?
    private var fadedHint: SKNode?
    private var topSafe: CGFloat = 54
    private var sentScore = -1
    private var sentFood = -1
    private var wantLine: CGFloat?

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
        // The speed lines are built once and reused; see speedLine.
        for _ in 0..<6 {
            let line = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 45))
            line.isHidden = true
            lines.addChild(line)
            linePool.append(line)
        }


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
        flash.isHidden = true
        flash.zPosition = 40
        addChild(flash)
        layout(topSafe: topSafe)
    }

    func layout(topSafe: CGFloat) {
        self.topSafe = max(topSafe, 54)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        pills?.layout(width: size.width, topSafe: self.topSafe)
        powerBar?.layout(width: size.width, topSafe: self.topSafe)
        panel.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        flash.size = size
        flash.position = center
        dim.size = size
        dim.position = center
        home.childNode(withName: "top")?.position = CGPoint(x: size.width / 2, y: size.height - self.topSafe - 66)
        home.childNode(withName: "bottom")?.position = CGPoint(x: size.width / 2, y: size.height * 0.17)
        // The menu button sits in the top-right corner, beside the camera cutout.
        home.childNode(withName: "menuButton")?.position = CGPoint(x: size.width - 38, y: size.height - 44)
        // The menu sits low, so she stays in view above it while you pick.
        home.childNode(withName: "menu")?.position = CGPoint(x: size.width / 2, y: max(menuSize.height / 2 + 30, size.height * 0.2))
        for (name, atTop) in [("shadeTop", true), ("shadeBottom", false)] {
            guard let shade = home.childNode(withName: name) as? SKSpriteNode else { continue }
            shade.size = CGSize(width: size.width, height: size.height * 0.36)
            let half = shade.size.height / 2
            shade.position = CGPoint(x: size.width / 2, y: atTop ? size.height - half : half)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard panel != nil else { return }
        layout(topSafe: topSafe)
    }

    // MARK: - Pills

    // The game calls these every frame from SceneKit's update, which runs on its own
    // thread, so a change is handed to the main thread, and only when it changed.
    // The score moves about 20 times a second; food only when she picks one up.
    func setScore(_ score: Int) {
        guard score != sentScore else { return }
        sentScore = score
        DispatchQueue.main.async { [weak self] in self?.pills?.setScore(score) }
    }

    func setFood(_ food: Int) {
        guard food != sentFood else { return }
        sentFood = food
        DispatchQueue.main.async { [weak self] in self?.pills?.setFood(food) }
    }

    override func update(_ currentTime: TimeInterval) {
        if let strength = wantLine {
            wantLine = nil
            spawnLine(strength: strength)
        }
    }

    private func setPillsHidden(_ hidden: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.pills?.setHidden(hidden)
            self?.powerBar?.isHidden = hidden
        }
    }

    // MARK: - Power-ups

    /// The power-ups she has, each with how much of it is left (1 to 0).
    /// Called from the render thread only when a timer moves a notch.
    func setPowers(_ list: [(icon: String, left: CGFloat)]) {
        DispatchQueue.main.async { [weak self] in self?.powerBar?.show(list) }
    }

    /// The power-up's name, popped once in big type when she grabs it.
    func showCallout(_ text: String) {
        callout?.removeFromParent()
        let node = SKNode()
        node.zPosition = 32
        node.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        let label = boldText(text, size: 38, fill: .white, lowerFill: icy, outlineWidth: 4.5, drop: 4)
        fit(label, maxWidth: size.width - 40)
        node.addChild(label)
        node.setScale(0.4)
        node.alpha = 0
        node.zRotation = -0.06
        addChild(node)
        // Pops up with a springy overshoot and a little straightening wobble,
        // hangs a moment, then floats away. Faded and hidden at the end, not
        // removed by an SKAction (see speedLine); the next one removes it.
        node.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.12),
                springIn(),
                .sequence([
                    .rotate(toAngle: 0.03, duration: 0.14, shortestUnitArc: true),
                    .rotate(toAngle: -0.01, duration: 0.1, shortestUnitArc: true),
                    .rotate(toAngle: 0, duration: 0.08, shortestUnitArc: true)
                ])
            ]),
            .wait(forDuration: 0.8),
            .group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 30, duration: 0.3)]),
            .hide()
        ]))
        callout = node
    }

    /// Scale to 1 the springy way: past it, back under it, and settle. Shared by
    /// the callout, the crash panel, and the "Dash again" button.
    private func springIn() -> SKAction {
        let over = SKAction.scale(to: 1.14, duration: 0.16)
        over.timingMode = .easeOut
        let under = SKAction.scale(to: 0.95, duration: 0.1)
        under.timingMode = .easeInEaseOut
        let back = SKAction.scale(to: 1.02, duration: 0.07)
        back.timingMode = .easeInEaseOut
        return .sequence([over, under, back, .scale(to: 1, duration: 0.05)])
    }

    // MARK: - Home

    /// What a tap on the home screen asks for. A tap that is none of these
    /// starts the run.
    enum HomeTap {
        case openMenu, closeMenu
        /// The next (+1) or the previous (-1) cat or cart.
        case cat(Int), cart(Int)
        case toggleSound, toggleHaptics
        /// A tap on the menu that hit nothing. It does nothing.
        case ignore
    }

    /// The menu: the cat and cart pickers and two switches, in a panel over the
    /// bottom of the screen so she stays in view above it.
    private let pickWidth: CGFloat = 236
    private let pickHeight: CGFloat = 44
    private let menuSize = CGSize(width: 300, height: 262)
    private let catRowY: CGFloat = 92
    private let cartRowY: CGFloat = 40
    private let switchRowY: CGFloat = -14
    private let doneRowY: CGFloat = -82
    private let menuButtonRadius: CGFloat = 24
    private(set) var menuOpen = false

    /// The title screen: big name up top, the kitten in the middle (that's the 3D
    /// scene), a paw button with the best score at the bottom, and a menu button
    /// in the corner that opens the cat and cart pickers and the switches.
    func showHome(best: Int, cat: CatChoice, cart: CartChoice) {
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
        // A slow bob and an even slower rock so the title feels alive while she waits.
        let bob = SKAction.moveBy(x: 0, y: 5, duration: 1.3)
        bob.timingMode = .easeInEaseOut
        title.run(.repeatForever(.sequence([bob, bob.reversed()])))
        let rockLeft = SKAction.rotate(toAngle: -0.05, duration: 2.1, shortestUnitArc: true)
        rockLeft.timingMode = .easeInEaseOut
        let rockRight = SKAction.rotate(toAngle: -0.02, duration: 2.1, shortestUnitArc: true)
        rockRight.timingMode = .easeInEaseOut
        title.run(.repeatForever(.sequence([rockLeft, rockRight])))

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

        home.addChild(menuButton())
        let menu = SKNode()
        menu.name = "menu"
        menu.isHidden = true
        home.addChild(menu)
        let back = SKShapeNode(rectOf: menuSize, cornerRadius: 28)
        back.fillColor = navy.withAlphaComponent(0.84)
        back.strokeColor = SKColor(white: 1, alpha: 0.35)
        back.lineWidth = 2
        menu.addChild(back)
        menu.addChild(pickRow(name: "catPick", caption: "CAT", y: catRowY))
        menu.addChild(pickRow(name: "cartPick", caption: "CART", y: cartRowY))
        menu.addChild(switchPill(name: "soundSwitch", title: "Sound", x: -72))
        menu.addChild(switchPill(name: "hapticsSwitch", title: "Vibration", x: 72))
        let done = textSprite("Done", size: 20, weight: .heavy, color: navy)
        let doneBack = SKShapeNode(rectOf: CGSize(width: 140, height: 44), cornerRadius: 22)
        doneBack.fillColor = icy
        doneBack.strokeColor = .white
        doneBack.lineWidth = 2
        doneBack.position = CGPoint(x: 0, y: doneRowY)
        done.position = doneBack.position
        menu.addChild(doneBack)
        menu.addChild(done)
        menuOpen = false
        setPicks(cat: cat, cart: cart)
        setSwitches(sound: Choices.sound, haptics: Choices.haptics)
        layout(topSafe: topSafe)
    }

    /// The round menu button in the top corner: three short white bars.
    private func menuButton() -> SKNode {
        let button = SKShapeNode(circleOfRadius: menuButtonRadius)
        button.name = "menuButton"
        button.fillColor = navy.withAlphaComponent(0.66)
        button.strokeColor = SKColor(white: 1, alpha: 0.5)
        button.lineWidth = 2
        for dy: CGFloat in [-7, 0, 7] {
            let bar = SKShapeNode(rectOf: CGSize(width: 20, height: 3.5), cornerRadius: 1.75)
            bar.fillColor = .white
            bar.strokeColor = .clear
            bar.position = CGPoint(x: 0, y: dy)
            button.addChild(bar)
        }
        return button
    }

    /// An on/off switch with its name beside it.
    private func switchPill(name: String, title: String, x: CGFloat) -> SKNode {
        let row = SKNode()
        row.name = name
        row.position = CGPoint(x: x, y: switchRowY)
        let back = SKShapeNode(rectOf: CGSize(width: 136, height: pickHeight), cornerRadius: pickHeight / 2)
        back.fillColor = SKColor(white: 1, alpha: 0.12)
        back.strokeColor = SKColor(white: 1, alpha: 0.3)
        back.lineWidth = 1.5
        row.addChild(back)
        let label = textSprite(title, size: 14, weight: .heavy, color: .white)
        label.anchorPoint.x = 0
        label.position = CGPoint(x: -56, y: 0)
        fit(label, maxWidth: 66)
        row.addChild(label)
        let track = SKShapeNode(rectOf: CGSize(width: 44, height: 26), cornerRadius: 13)
        track.name = "track"
        track.strokeColor = .clear
        track.position = CGPoint(x: 38, y: 0)
        row.addChild(track)
        let knob = SKShapeNode(circleOfRadius: 10)
        knob.name = "knob"
        knob.fillColor = .white
        knob.strokeColor = .clear
        track.addChild(knob)
        return row
    }

    /// Shows the switches on or off.
    func setSwitches(sound: Bool, haptics: Bool) {
        guard let menu = home.childNode(withName: "menu") else { return }
        for (name, on) in [("soundSwitch", sound), ("hapticsSwitch", haptics)] {
            guard let track = menu.childNode(withName: name)?.childNode(withName: "track") as? SKShapeNode,
                  let knob = track.childNode(withName: "knob") else { continue }
            track.fillColor = on ? SKColor(red: 0.36, green: 0.82, blue: 0.5, alpha: 1) : SKColor(white: 0.55, alpha: 1)
            knob.run(.moveTo(x: on ? 9 : -9, duration: 0.12))
        }
    }

    /// Opens or closes the menu. The play button and best score step aside
    /// while it's open.
    func setMenuOpen(_ open: Bool) {
        guard let menu = home.childNode(withName: "menu"), let bottom = home.childNode(withName: "bottom") else { return }
        menuOpen = open
        menu.removeAllActions()
        bottom.removeAllActions()
        if open {
            menu.isHidden = false
            menu.alpha = 0
            menu.setScale(0.85)
            menu.run(.group([.fadeIn(withDuration: 0.18), .scale(to: 1, duration: 0.18)]))
            bottom.run(.fadeOut(withDuration: 0.15))
        } else {
            menu.run(.sequence([.fadeOut(withDuration: 0.15), .hide()]))
            bottom.run(.fadeIn(withDuration: 0.2))
        }
    }

    /// One picker pill: a caption, the name in the middle, an arrow button at
    /// each end. The name is filled in by setPicks.
    private func pickRow(name: String, caption: String, y: CGFloat) -> SKNode {
        let row = SKNode()
        row.name = name
        row.position = CGPoint(x: 0, y: y)
        let back = SKShapeNode(rectOf: CGSize(width: pickWidth, height: pickHeight), cornerRadius: pickHeight / 2)
        back.fillColor = navy.withAlphaComponent(0.66)
        back.strokeColor = SKColor(white: 1, alpha: 0.35)
        back.lineWidth = 1.5
        row.addChild(back)
        let tag = textSprite(caption, size: 10, weight: .heavy, color: icy)
        tag.position = CGPoint(x: 0, y: 12)
        row.addChild(tag)
        for (dx, glyph) in [(-1, "‹"), (1, "›")] as [(CGFloat, String)] {
            let button = SKShapeNode(circleOfRadius: pickHeight / 2 - 4)
            button.fillColor = icy
            button.strokeColor = navy
            button.lineWidth = 2
            button.position = CGPoint(x: dx * (pickWidth / 2 - pickHeight / 2), y: 0)
            row.addChild(button)
            let arrow = boldText(glyph, size: 28, fill: navy, outlineWidth: 0, drop: 0)
            arrow.position = CGPoint(x: button.position.x + dx, y: 2)
            row.addChild(arrow)
        }
        return row
    }

    /// Shows the picked cat and cart on the pills, with a little pop.
    func setPicks(cat: CatChoice, cart: CartChoice) {
        for (rowName, title) in [("catPick", cat.title), ("cartPick", cart.title)] {
            guard let row = home.childNode(withName: "menu")?.childNode(withName: rowName) else { continue }
            let old = row.childNode(withName: "title") as? SKSpriteNode
            if old?.userData?["text"] as? String == title { continue }
            old?.removeFromParent()
            let label = boldText(title, size: 20, fill: .white, outlineWidth: 2.5, drop: 2)
            label.name = "title"
            label.userData = ["text": title]
            fit(label, maxWidth: pickWidth - pickHeight * 2 - 8)
            label.position = CGPoint(x: 0, y: -5)
            row.addChild(label)
            if old != nil {
                let s = label.xScale
                label.setScale(s * 0.7)
                label.run(.sequence([.scale(to: s * 1.1, duration: 0.1), .scale(to: s, duration: 0.08)]))
            }
        }
    }

    /// What a tap on the home screen hit. `point` is in the game view's points
    /// (y down); this scene is the same size with y up. Nil means start the run.
    func homeTap(at point: CGPoint) -> HomeTap? {
        guard !home.isHidden else { return nil }
        let p = CGPoint(x: point.x, y: size.height - point.y)
        if let button = home.childNode(withName: "menuButton"),
           hypot(p.x - button.position.x, p.y - button.position.y) < menuButtonRadius + 14 {
            return menuOpen ? .closeMenu : .openMenu
        }
        guard menuOpen, let menu = home.childNode(withName: "menu") else { return nil }
        let x = p.x - menu.position.x
        let y = p.y - menu.position.y
        // Off the panel closes it, so a stray tap never starts a run from the menu.
        guard abs(x) < menuSize.width / 2, abs(y) < menuSize.height / 2 else { return .closeMenu }
        // Rows get a little more than their height, for a thumb.
        let reach = pickHeight / 2 + 4
        if abs(y - catRowY) < reach { return .cat(x < 0 ? -1 : 1) }
        if abs(y - cartRowY) < reach { return .cart(x < 0 ? -1 : 1) }
        if abs(y - switchRowY) < reach { return x < 0 ? .toggleSound : .toggleHaptics }
        if abs(y - doneRowY) < reach { return .closeMenu }
        return .ignore
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

    /// The panel pops in at once with the numbers. The "Dash again" button waits
    /// for `showRetry`, when taps start working again.
    func showDead(score: Int, food: Int, seconds: Int, best: Int, newBest: Bool) {
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

        // Three big numbers across: score, food, and time survived (like 1:12).
        // A long score would shrink on its own and look smaller than the others,
        // so all three shrink together to the size the widest one needs.
        let column = width * 0.3
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let stats = [(-column, score.formatted(), "score"), (0, "\(food)", "food"), (column, time, "time")]
        let numbers = stats.map { textSprite($0.1, size: 46, weight: .black, color: ink) }
        let widest = numbers.map(\.size.width).max() ?? 1
        let shrink = min(1, width * 0.25 / widest)
        for ((x, _, word), number) in zip(stats, numbers) {
            number.setScale(shrink)
            number.position = CGPoint(x: x, y: 26)
            panel.addChild(number)
            let label = textSprite(word, size: 17, weight: .bold, color: softInk)
            label.position = CGPoint(x: x, y: -10)
            panel.addChild(label)
        }

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

        // Hidden until the death pause ends; see showRetry.
        let again = pawButton("Dash again")
        again.name = "again"
        again.position = CGPoint(x: 0, y: -182)
        again.alpha = 0
        again.setScale(0.6)
        panel.addChild(again)

        // Pop in: the panel springs up, the ribbon drops onto it a beat later and
        // settles with a small bounce and a wobble.
        panel.setScale(0.6)
        panel.alpha = 0
        panel.run(.group([.fadeIn(withDuration: 0.15), springIn()]))
        banner.alpha = 0
        banner.position.y += 40
        let drop = SKAction.moveBy(x: 0, y: -40, duration: 0.22)
        drop.timingMode = .easeIn
        let bounce = SKAction.sequence([.moveBy(x: 0, y: 7, duration: 0.08), .moveBy(x: 0, y: -7, duration: 0.08)])
        let wobble = SKAction.sequence([
            .rotate(toAngle: 0.025, duration: 0.1, shortestUnitArc: true),
            .rotate(toAngle: -0.03, duration: 0.12, shortestUnitArc: true)
        ])
        banner.run(.sequence([
            .wait(forDuration: 0.14),
            .group([.fadeIn(withDuration: 0.1), drop]),
            .group([bounce, wobble])
        ]))

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

    /// The death pause is over: the "Dash again" button bounces in like the panel did.
    func showRetry() {
        guard let again = panel.childNode(withName: "again") else { return }
        again.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), springIn()]),
            .run { [weak self] in self?.pulse(again) }
        ]))
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
        fadedHint?.removeFromParent()
        fadedHint = nil
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
        // Faded and hidden, not removed by an SKAction (see speedLine). The next
        // showHint takes it out directly.
        node.run(.sequence([.fadeOut(withDuration: 0.2), .hide()]))
        fadedHint = node
    }

    // MARK: - Effects

    func flashWhite() {
        flash.removeAllActions()
        flash.isHidden = false
        flash.alpha = 0.7
        // Hidden again once faded, so no full-screen white sprite sits in the
        // overlay for the rest of the run.
        flash.run(.sequence([.fadeOut(withDuration: 0.25), .hide()]))
    }

    /// Thin streaks near the screen edges that sell speed without covering the track.
    ///
    /// The streaks come from a small pool built with the HUD, and are never added
    /// or removed mid-run. Adding a sprite every 0.12 s that removed itself with
    /// an SKAction is reported to make SpriteKit draw out of order or with the
    /// wrong picture for a frame when it is SceneKit's overlay. The pool alone did
    /// not stop the white pills on the phone; see setScore for the other change.
    func speedLine(strength: CGFloat) {
        wantLine = strength
    }

    private func spawnLine(strength: CGFloat) {
        guard linesOn, !linePool.isEmpty else { return }
        let side: CGFloat = Bool.random() ? -1 : 1
        let x = size.width / 2 + side * CGFloat.random(in: 0.32...0.48) * size.width
        let y = CGFloat.random(in: 0.25...0.6) * size.height
        let line = linePool[nextLine]
        nextLine = (nextLine + 1) % linePool.count
        line.removeAllActions()
        line.color = SKColor(white: 1, alpha: 0.28 * strength)
        line.size = CGSize(width: 2, height: CGFloat.random(in: 30...60))
        line.position = CGPoint(x: x, y: y)
        line.alpha = 1
        line.isHidden = false
        // Lean the streak outward, like it's flying past the camera.
        line.zRotation = side * 0.35
        let drift = CGVector(dx: side * 60, dy: -140)
        line.run(.sequence([
            .group([.move(by: drift, duration: 0.28), .fadeOut(withDuration: 0.28)]),
            .hide()
        ]))
    }

    func clearLines() {
        wantLine = nil
        for line in linePool {
            line.removeAllActions()
            line.isHidden = true
        }
    }
}

/// The score and food pills at the top of the screen, as plain UIKit views laid
/// over the game view instead of sprites in the SpriteKit overlay.
///
/// Why: on the phone, the overlay scene sometimes drew the pills with each other's
/// pictures for a single frame: the score pill as a white box, the pill picture
/// squeezed onto a digit, digits shifted one place. A 500 screenshot run caught it
/// 7 times, with a pill built from SKLabelNodes and again with one built from
/// per-digit sprites, so it is the overlay and not what we put in it. The
/// simulator never shows it. UIKit draws these itself, with no SpriteKit in the way.
///
/// It takes no touches, so swipes still reach the game view underneath.
final class PillBar: UIView {
    private let scoreChip = UIImageView(image: UIImage(named: "uiHud"))
    private let foodChip = UIImageView(image: UIImage(named: "uiHud"))
    private let scoreLabel = PillBar.makeLabel()
    private let foodLabel = PillBar.makeLabel()
    private var shownFood = -1
    private var shownScore = -1

    private static let chipSize = CGSize(width: 150, height: 40)
    private static let ink = UIColor(red: 0.16, green: 0.30, blue: 0.46, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for chip in [scoreChip, foodChip] {
            chip.bounds = CGRect(origin: .zero, size: Self.chipSize)
            addSubview(chip)
        }
        addSubview(scoreLabel)
        addSubview(foodLabel)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// AvenirNext-Heavy 17 like before, with digits that all share one width so a
    /// number doesn't shift sideways as it counts up.
    private static func makeLabel() -> UILabel {
        let label = UILabel()
        let base = UIFont(name: "AvenirNext-Heavy", size: 17) ?? .systemFont(ofSize: 17, weight: .heavy)
        let fixed = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        ])
        label.font = UIFont(descriptor: fixed, size: 17)
        label.textColor = ink
        label.textAlignment = .left
        return label
    }

    /// The pills sit at 28% and 74% of the width, 28 points under the safe area
    /// (at least 54), and the text starts 28 points left of each pill's center.
    func layout(width: CGFloat, topSafe: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: width, height: topSafe + 60)
        let y = topSafe + 28
        for (chip, label, x) in [(scoreChip, scoreLabel, width * 0.28), (foodChip, foodLabel, width * 0.74)] {
            chip.center = CGPoint(x: x, y: y)
            label.bounds = CGRect(x: 0, y: 0, width: 100, height: 24)
            label.center = CGPoint(x: x - 28 + 50, y: y)
        }
    }

    func setScore(_ score: Int) {
        // A small pop each time the score passes another thousand: a milestone,
        // not a pop per point.
        if shownScore >= 0 && score / 1000 > shownScore / 1000 {
            pop(scoreChip)
        }
        shownScore = score
        scoreLabel.text = score.formatted()
    }

    func setFood(_ food: Int) {
        let grew = shownFood >= 0 && food > shownFood
        shownFood = food
        foodLabel.text = "food \(food)"
        if grew {
            // A small pulse on the pill instead of score text flying around the screen.
            pop(foodChip)
        }
    }

    /// A quick swell and a springy settle, the way a toy button would.
    private func pop(_ chip: UIView) {
        chip.layer.removeAllAnimations()
        chip.transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 2,
                       options: [], animations: { chip.transform = .identity })
    }

    func setHidden(_ hidden: Bool) {
        layer.removeAllAnimations()
        if hidden {
            alpha = 0
        } else {
            UIView.animate(withDuration: 0.3) { self.alpha = 1 }
        }
    }
}

/// The power-up timers: a round badge for each power-up she has, in a row
/// under the score pill, with a gold ring that runs down as it wears off.
/// UIKit views, for the same reason as the pills (see PillBar).
final class PowerBar: UIView {
    private var badges: [String: Badge] = [:]
    private var order: [String] = []
    private var rowWidth: CGFloat = 390

    private static let size: CGFloat = 48
    private static let navy = UIColor(red: 0.10, green: 0.17, blue: 0.38, alpha: 1)
    private static let gold = UIColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1)

    /// One timer: the power-up's picture in a cream circle, ringed in gold.
    private final class Badge: UIView {
        private let ring = CAShapeLayer()

        init(icon: String) {
            let d = PowerBar.size
            super.init(frame: CGRect(x: 0, y: 0, width: d, height: d))
            backgroundColor = UIColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 0.95)
            layer.cornerRadius = d / 2
            layer.borderWidth = 2.5
            layer.borderColor = PowerBar.navy.cgColor
            let path = UIBezierPath(arcCenter: CGPoint(x: d / 2, y: d / 2), radius: d / 2 - 6,
                                    startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
            let track = CAShapeLayer()
            track.path = path
            track.fillColor = nil
            track.strokeColor = UIColor(white: 0.86, alpha: 1).cgColor
            track.lineWidth = 4
            layer.addSublayer(track)
            ring.path = path
            ring.fillColor = nil
            ring.strokeColor = PowerBar.gold.cgColor
            ring.lineWidth = 4
            ring.lineCap = .round
            layer.addSublayer(ring)
            let label = UILabel(frame: bounds)
            label.text = icon
            label.font = .systemFont(ofSize: 22)
            label.textAlignment = .center
            addSubview(label)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        func set(left: CGFloat) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.strokeEnd = left
            CATransaction.commit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Just under the pills, which sit 28 points under the safe area.
    func layout(width: CGFloat, topSafe: CGFloat) {
        rowWidth = width
        frame = CGRect(x: 0, y: topSafe + 54, width: width, height: Self.size + 8)
        arrange()
    }

    func show(_ list: [(icon: String, left: CGFloat)]) {
        let icons = list.map { $0.icon }
        for (icon, badge) in badges where !icons.contains(icon) {
            badge.removeFromSuperview()
            badges[icon] = nil
        }
        for item in list {
            let badge: Badge
            if let b = badges[item.icon] {
                badge = b
            } else {
                badge = Badge(icon: item.icon)
                addSubview(badge)
                badges[item.icon] = badge
                // Pops in with a little bounce.
                badge.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.55,
                               initialSpringVelocity: 0, options: [], animations: { badge.transform = .identity })
            }
            badge.set(left: item.left)
        }
        order = icons
        arrange()
    }

    /// A row from the left edge of the score pill.
    private func arrange() {
        let start = rowWidth * 0.28 - 75 + Self.size / 2
        for (i, icon) in order.enumerated() {
            badges[icon]?.center = CGPoint(x: start + CGFloat(i) * (Self.size + 8), y: Self.size / 2 + 4)
        }
    }
}
