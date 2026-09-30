import SpriteKit
import SwiftUI

// SwiftUI owns the iPhone window. SpriteKit owns the game inside it.
@main
struct CatCartApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}

struct GameView: View {
    // @State keeps this scene alive. If we created it inside body,
    // SwiftUI would throw the game away and start over on every redraw.
    @State private var scene = GameScene(size: CGSize(width: 390, height: 844))

    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .onAppear {
                    scene.size = geo.size
                    // Fill the phone. Our layout math uses scene.size directly.
                    scene.scaleMode = .resizeFill
                }
                .onChange(of: geo.size) { _, newSize in
                    scene.size = newSize
                }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
