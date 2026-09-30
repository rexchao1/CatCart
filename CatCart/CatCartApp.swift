import SceneKit
import SwiftUI

// SwiftUI owns the iPhone window. SceneKit owns the 3D game inside it.
@main
struct CatCartApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

// SwiftUI has no built-in SceneKit view that hands us touches and a render loop,
// so we wrap UIKit's SCNView. The coordinator keeps the game alive: if we built it
// inside body, SwiftUI would throw it away and start over on every redraw.
struct GameView: UIViewRepresentable {
    final class Coordinator {
        var game: GameScene?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GameSCNView {
        let view = GameSCNView(frame: .zero)
        context.coordinator.game = GameScene(view: view)
        return view
    }

    func updateUIView(_ uiView: GameSCNView, context: Context) {}
}

/// The SceneKit view. It only forwards touches and size changes to the game.
final class GameSCNView: SCNView {
    weak var game: GameScene?

    override func layoutSubviews() {
        super.layoutSubviews()
        game?.viewDidLayout(size: bounds.size, topSafe: safeAreaInsets.top)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        game?.touchBegan(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        game?.touchMoved(to: point, minimum: 22)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        game?.touchMoved(to: point, minimum: 24)
        game?.touchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        game?.touchEnded()
    }
}
