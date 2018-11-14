import Cocoa
import simd
import Dispatch

struct Image {
    var width: Int
    var height: Int
    var rep: NSBitmapImageRep
    var pointer: UnsafeMutableBufferPointer<UInt8>
    var lineLength: Int
    var pixelLength: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: NSDeviceRGBColorSpace, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        pointer = UnsafeMutableBufferPointer(start: rep.bitmapData, count: rep.bytesPerPlane)
        lineLength = rep.bytesPerRow
        pixelLength = rep.bitsPerPixel / 8
    }

    var image: NSImage {
        return NSImage(cgImage: rep.cgImage!, size: NSSize(width: width, height: height))
    }

    func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 0xFF) {
        let baseAddr = y * lineLength + x * pixelLength
        pointer[baseAddr + 0] = r
        pointer[baseAddr + 1] = g
        pointer[baseAddr + 2] = b
        pointer[baseAddr + 3] = a
    }

    func savePNG(to: URL) {
        _ = try? rep.representation(using: .PNG, properties: [:])?.write(to: to)
    }
}


var a = Image(width: 500, height: 500)

extension float3 {
    var length: Float {
        return sqrt(dot(self, self))
    }

    var normalized: float3 {
        return self * (1.0 / length)
    }
}
struct Ray {
    var origin: float3
    var direction: float3
}

struct Camera {
    var location: float3
    var direction: float3
    var up: float3
    var distance: Float
    let fov = 45 * Float.pi / 180
    let aspect = 1.0 as Float

    func ray(x: Float, y: Float) -> Ray {
        let right = cross(direction, up)
        let w = 2 * distance * tan(fov / 2)
        let imagePoint = location + distance * direction + w * x * right + w * aspect * y * up
        return Ray(origin: location, direction: (imagePoint - location).normalized)
    }
}

let camera = Camera(
    location: [30, 10, 1.5],
    direction: [-1, 0, 0],
    up: [0, 1, 0],
    distance: float3([30, 10, 1.5]).length
)

protocol Primitive {
    func intersects(ray: Ray) -> (Float, float3)?
}

struct Sphere {
    var center: float3
    var radius: Float
}

struct Plane {
    var center: float3
    var normal: float3
}

struct Scene {
    var primitives: [Primitive]
}


extension Plane: Primitive {
    func intersects(ray: Ray) -> (Float, float3)? {
        let denom = dot(normal, ray.direction)
        guard (denom) >= 0.00001 else { return nil }
        let t = dot((center - ray.origin), normal) / denom
        return (t, normal)
    }
}

extension Scene: Primitive {
    func intersects(ray: Ray) -> (Float, float3)? {
        let hits = primitives
            .flatMap { $0.intersects(ray: ray) }
            .sorted { lhs, rhs in lhs.0 < rhs.0 }
        return hits.first
    }
}

extension Sphere : Primitive {
    func intersects(ray: Ray) -> (Float, float3)? {
        let L = center - ray.origin
        let tca = dot(L, ray.direction)
        guard tca >= 0 else { return nil }
        let d2 = dot(L, L) - tca * tca
        let radius2 = radius * radius
        guard d2 <= radius2 else { return nil }
        let thc = sqrt(radius2 - d2)
        var t0 = tca - thc
        var t1 = tca + thc
        if t1 > t0 { swap(&t1, &t0) }

        if t0 < 0 { t0 = t1 }
        if t0 < 0 { return nil }

        let point = ray.origin + t0 * ray.direction
        let normal = (point - center).normalized
        return (t0, normal)
    }
}

let sphere = Sphere(center: float3(0, 0, 0), radius: 1)
let plane = Plane(center: [0,0, 0], normal: [0, 1, 0])

let scene = Scene(primitives: [sphere, plane])


let light: float3 = [10, -10, 20]

let start = mach_absolute_time()

let raysPerPixel = 4

func random() -> Float
{
    return Float(arc4random()) / Float(UInt32.max)
}

func random(_ min: Float, _ max: Float) -> Float {
    return min + random() * (max - min)
}

DispatchQueue.concurrentPerform(iterations: a.height) { y in
    for x in 0..<a.width {
        var color: float3 = [0, 0, 0]

        for _ in 0..<raysPerPixel {

            let i = Float(x) / Float(a.width) - 0.5
            let j = Float(y) / Float(a.height) - 0.5

            let r = camera.ray(x: i, y: j)
            if let (h, normal) = scene.intersects(ray: r) {
                let p = r.origin + h * r.direction
                let l = (p - light).normalized
                let ambient: float3 = [0.4, 0, 0]
                let diffuse: float3 = [0.5, 0.5, 0.5]
                let specular: float3 = [0.5, 0.5, 0.5]
                let roughness: Float = 2000
                let power = max(0, dot(l, normal))
                let b = (p - r.origin).normalized
                let h = (b + l).normalized
                let specularPower = max(0, dot(normal, h))

                let lightComponents = ambient + diffuse * power + specular * pow(specularPower, roughness)
                color += clamp(lightComponents, min: 0.0, max: 1.0)

            } else {
                color += [ 0.5, 0.5, 0.5 ]
            }
        }

        color *= 1.0 / Float(raysPerPixel)
        a.setPixel(x: x, y: y, r: UInt8(max(0,color.x) * 255), g: UInt8(max(0,color.y) * 255), b: UInt8(max(0,color.z) * 255))
        
    }
}

let duration = mach_absolute_time() - start
var timebase = mach_timebase_info()
mach_timebase_info(&timebase)
var time = Double(duration) * Double(timebase.numer) / Double(timebase.denom)
print("Took \(time / Double(NSEC_PER_MSEC)) ms for \(a.height * a.width) pixel.")
print("\(time / Double(a.height * a.width)) ns per Pixel")

let url = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/test.png")
a.savePNG(to: url)
NSWorkspace.shared().open(url)
