// Packages Blender JSON as a self-contained SceneKit asset, including textures
// and looping coyote motion. Used by scripts/build_art.sh before the Xcode build.
import AppKit
import SceneKit

struct Material: Decodable {
    let name: String
    let color: [CGFloat]
    let roughness: CGFloat
    let metallic: CGFloat
    let texture: String?
    let vertexColor: Bool
    /// Linear light the surface gives off on its own (the coyote's amber eyes).
    let emission: [CGFloat]?
}
struct Part: Decodable {
    let name: String
    let parent: String?
    let position: [Float]
    let material: String?
    let vertices: [Float]?
    let normals: [Float]?
    let colors: [Float]?
    let uv: [Float]?
    let indices: [UInt32]?
}
struct Track: Decodable { let position: [[Float]]; let orientation: [[Float]] }
struct Asset: Decodable {
    let name: String
    let parts: [Part]
    let materials: [Material]
    let frames: Int
    let duration: Double
    let anim: [String: Track]
}
let args=CommandLine.arguments
precondition(args.count==3,"usage: build_game_pickup input.json output.scn")
let asset=try JSONDecoder().decode(Asset.self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
var materials:[String:SCNMaterial]=[:]
for entry in asset.materials {
    let m=SCNMaterial();m.name=entry.name
    m.lightingModel = entry.metallic > 0.2 || entry.roughness < 0.5 ? .blinn : .lambert
    // Blender base colors and geometry colors are linear, not sRGB.
    func srgb(_ value: CGFloat) -> CGFloat { value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055 }
    m.diffuse.contents = entry.vertexColor ? NSColor.white : NSColor(srgbRed:srgb(entry.color[0]),
        green:srgb(entry.color[1]),blue:srgb(entry.color[2]),alpha:entry.color[3])
    if let texture=entry.texture {
        guard let image=NSImage(contentsOfFile:texture) else { fatalError("Missing texture \(texture)") }
        m.diffuse.contents=image // NSImage is embedded in the SceneKit archive.
        m.diffuse.mipFilter = .linear;m.diffuse.minificationFilter = .linear;m.diffuse.magnificationFilter = .linear
        m.diffuse.maxAnisotropy=8
    }
    if let glow=entry.emission, glow.count>=3 {
        m.emission.contents=NSColor(srgbRed:srgb(glow[0]),green:srgb(glow[1]),blue:srgb(glow[2]),alpha:1)
    }
    m.specular.contents=NSColor(white:entry.metallic > 0.2 ? 0.65 : 0.18,alpha:1)
    m.shininess=max(0.05,1-entry.roughness)
    m.isDoubleSided=false
    materials[entry.name]=m
}
func source(_ values:[Float],_ semantic:SCNGeometrySource.Semantic,_ count:Int)->SCNGeometrySource {
    let data=values.withUnsafeBufferPointer { Data(buffer:$0) }
    return SCNGeometrySource(data:data,semantic:semantic,vectorCount:values.count/count,usesFloatComponents:true,
                             componentsPerVector:count,bytesPerComponent:4,dataOffset:0,dataStride:count*4)
}
var nodes:[String:SCNNode]=[:]
let scene=SCNScene()
for p in asset.parts {
    let node=SCNNode();node.name=p.name
    node.position=SCNVector3(p.position[0],p.position[1],p.position[2])
    if let v=p.vertices,let n=p.normals,let c=p.colors,let uv=p.uv,let i=p.indices,let m=p.material {
        precondition(v.count==n.count && c.count/4==v.count/3 && uv.count/2==v.count/3)
        let data=i.withUnsafeBufferPointer { Data(buffer:$0) }
        let element=SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:i.count/3,bytesPerIndex:4)
        let geo=SCNGeometry(sources:[source(v,.vertex,3),source(n,.normal,3),source(c,.color,4),source(uv,.texcoord,2)],elements:[element])
        geo.materials=[materials[m]!];node.geometry=geo
    }
    nodes[p.name]=node
    if let parent=p.parent { nodes[parent]!.addChildNode(node) } else { scene.rootNode.addChildNode(node) }
}
let times=(0...asset.frames).map { NSNumber(value:Double($0)/Double(asset.frames)) }
for (name,track) in asset.anim {
    let position=CAKeyframeAnimation(keyPath:"position")
    position.values=track.position.map { NSValue(scnVector3:SCNVector3($0[0],$0[1],$0[2])) }
    let rotation=CAKeyframeAnimation(keyPath:"orientation")
    rotation.values=track.orientation.map { NSValue(scnVector4:SCNVector4($0[0],$0[1],$0[2],$0[3])) }
    for a in [position,rotation] { a.duration=asset.duration;a.keyTimes=times;a.calculationMode = .linear }
    let group=CAAnimationGroup();group.animations=[position,rotation];group.duration=asset.duration
    group.repeatCount = .infinity;group.isRemovedOnCompletion=false
    nodes[name]!.addAnimation(group,forKey:"run")
}
let url=URL(fileURLWithPath:args[2])
precondition(scene.write(to:url,options:nil,delegate:nil,progressHandler:nil),"Failed to save \(url)")
let restored=try SCNScene(url:url,options:nil)
precondition(restored.rootNode.childNode(withName:asset.name,recursively:false) != nil)
print("Saved \(url.lastPathComponent): \(nodes.count) nodes, \(asset.anim.count) animations")
