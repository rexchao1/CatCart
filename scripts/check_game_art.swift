// Focused checks for the committed game assets. Run from the repository root:
// swift scripts/check_game_art.swift [preview-directory]
import AppKit
import SceneKit
import Metal

let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let output=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "/tmp/catcart-art-check")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
func load(_ file:String,_ name:String)->SCNNode {
    let scene=try! SCNScene(url:root.appendingPathComponent("CatCart/Models/\(file).scn"),options:nil)
    guard let node=scene.rootNode.childNode(withName:name,recursively:false) else { fatalError("Missing \(name)") }
    var count=0
    node.enumerateHierarchy { n,_ in
        precondition(n.camera==nil && n.light==nil,"Studio was exported")
        for e in n.geometry?.elements ?? [] { count+=e.primitiveCount }
        precondition(!(n.name ?? "").contains(" fur"),"Strand fur was exported")
    }
    precondition(count>1000 && count<(name=="coyote" ? 28000 : 6500),"Unexpected geometry budget: \(count)")
    print("\(name): \(count) triangles")
    return node
}
let food=load("wet_food","wet_food")
let coyote=load("coyote_run","coyote")
var labelFound=false
food.enumerateHierarchy { n,_ in
    for m in n.geometry?.materials ?? [] where m.name=="Turquoise label" {
        let embedded = (m.diffuse.contents as? NSImage) ?? (m.diffuse.contents as? Data).flatMap { NSImage(data:$0) }
        precondition(embedded != nil,"Food label must contain image bytes, not an external filename")
        precondition(!(n.geometry?.sources(for:.texcoord).isEmpty ?? true),"Missing label UV coordinates")
        labelFound=true
    }
}
precondition(labelFound,"Missing turquoise label")
for name in ["body","head","jaw","frontUpperL","frontLowerL","hindUpperR","hindLowerR","tail1"] {
    precondition(coyote.childNode(withName:name,recursively:true)?.animationPlayer(forKey:"run") != nil,"Missing motion on \(name)")
}
let stage=SCNScene();stage.background.contents=NSColor(srgbRed:0.65,green:0.76,blue:0.80,alpha:1)
let light=SCNNode();light.light=SCNLight();light.light!.type = .omni;light.position=SCNVector3(-2,4,3);stage.rootNode.addChildNode(light)
let ambient=SCNNode();ambient.light=SCNLight();ambient.light!.type = .ambient;ambient.light!.intensity=450;stage.rootNode.addChildNode(ambient)
let camera=SCNNode();camera.camera=SCNCamera();camera.camera!.usesOrthographicProjection=true;camera.camera!.orthographicScale=1.55
camera.position=SCNVector3(1.2,1.5,2.6);camera.look(at:SCNVector3(0,0.48,0));stage.rootNode.addChildNode(camera)
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=stage;renderer.pointOfView=camera
func render(_ time:Double,_ name:String) {
    let image=renderer.snapshot(atTime:time,with:CGSize(width:800,height:800),antialiasingMode:.multisampling4X)
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
stage.rootNode.addChildNode(food)
render(0,"food-game.png")
food.removeFromParentNode()
let clone=coyote.clone();stage.rootNode.addChildNode(clone)
camera.camera!.orthographicScale=1.9;camera.position=SCNVector3(1.7,1.4,2.5);camera.look(at:SCNVector3(0,0.6,0))
render(0,"coyote-start.png")
render(0.10,"coyote-stride.png")
let leg=clone.childNode(withName:"frontUpperL",recursively:true)!
let jaw=clone.childNode(withName:"jaw",recursively:true)!
let legA=leg.presentation.eulerAngles.x,jawA=jaw.presentation.eulerAngles.x
render(0.225,"coyote-snap.png")
precondition(abs(leg.presentation.eulerAngles.x-legA)>0.1,"Clone legs do not animate")
precondition(abs(jaw.presentation.eulerAngles.x-jawA)>0.03,"Clone jaw does not animate")
print("PASS: embedded food label, game geometry budgets, coyote clone gallop and snarl")
