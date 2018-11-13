import simd
import CoreGraphics
import Foundation

typealias Vector = vector_double3
typealias Point = vector_double3

struct Ray {
    let origin: Point
    let direction: Vector
    let length: Double

    init(from: Point, to: Point) {
        origin = from
        direction = normalize(to - from)
        self.length = simd.length(to - from)
    }

    init(origin: Point, direction: Vector) {
        self.origin = origin
        self.direction = direction
        self.length = .greatestFiniteMagnitude
    }

    func at(_ distance: Double) -> Point {
        return origin + direction * distance
    }
}

let offset = 0.000001

struct Intersection {
    let point: Point
    let normal: Vector
    let distance: Double
    let object: Object

    init(ray: Ray, distance: Double, normal: Vector, object: Object) {
        self.point = ray.at(distance) + offset * normal
        self.normal = normal
        self.distance = distance
        self.object = object
    }

    init(point: Point, distance: Double, normal: Vector, object: Object) {
        self.point = point + offset * normal
        self.distance = distance
        self.normal = normal
        self.object = object
    }
}

typealias Color = vector_double3

struct Material {
    let ambient: Color
    let diffuse: Color
    let specular: Color
    let shininess: Double

    let reflecting: Bool
    let reflectingPower: Color

    let checkboard: Bool

    let refracts: Bool
    let ior: Double
}

protocol Object: class {
    func intersect(ray: Ray) -> Intersection?
    var material: Material { get }
}

let sphereMaterial = Material(
    ambient: [3, 0, 0],
    diffuse: [1, 0, 0],
    specular: [1, 0, 1],
    shininess: 40,
    reflecting: true,
    reflectingPower: [1, 1, 1],
    checkboard: false,
    refracts: false,
    ior: 1
)

let lensMaterial = Material(
    ambient: [1, 1, 1] * 0.1,
    diffuse: [1, 1, 1] * 0.1,
    specular: [1, 1, 1] * 0.1,
    shininess: 100,
    reflecting: false,
    reflectingPower: [1, 1, 1],
    checkboard: false,
    refracts: true,
    ior: 1.5
)

let planeMaterial = Material(
    ambient: [1, 1, 1] * 0.1,
    diffuse: [1, 1, 1] * 1,
    specular: [1, 1, 1] * 1,
    shininess: 100,
    reflecting: false,
    reflectingPower: [1, 1, 1] * 2,
    checkboard: true,
    refracts: false,
    ior: 1
)

class Sphere: Object {
    let center: Point
    let radius: Double
    let material: Material

    init(center: Point, radius: Double, material: Material) {
        self.center = center
        self.radius = radius
        self.material = material
    }

    func intersect(ray: Ray) -> Intersection? {
        let m = ray.origin - center
        let b = dot(m, ray.direction)
        let c = dot(m, m) - radius * radius

        guard c <= 0 || b <= 0 else {
            return nil
        }

        let discr = b * b - c

        guard discr >= 0 else { return nil }

        let t = -b - sqrt(discr)

        guard t >= 0 else { return nil }

        let p = ray.at(t)
        let normal = normalize(p - center)

        return Intersection(point: p, distance: t, normal: normal, object: self)
    }
}

class Plane: Object {
    let point: Point
    let normal: Vector
    let material: Material

    init(point: Point, normal: Vector, material: Material) {
        self.point = point
        self.normal = normal
        self.material = material
    }

    func intersect(ray: Ray) -> Intersection? {
        let denom = dot(normal, ray.direction)
        guard denom != 0 else { return nil }

        let t = dot(point - ray.origin, normal) / denom
        guard t > 0 else { return nil }

        return Intersection(ray: ray, distance: t, normal: normal, object: self)
    }

}


let camera: Point = [0, 0, -10]
let up: Vector = [0, 1, 0]
let lookAt: Point = [0, 0, 0]
let forward: Vector = normalize(lookAt - camera)
let distance = length(lookAt - camera)
let right = cross(up, forward)

let sphere = Sphere(center: [2, 2, 0], radius: 2, material: sphereMaterial)
let sphere2 = Sphere(center: [4, -1, -1], radius: 1, material: sphereMaterial)
let sphere3 = Sphere(center: [-6, 2, 0], radius: 4, material: sphereMaterial)
let plane = Plane(point: [0, -5, 0], normal: up, material: planeMaterial)
let lens = Sphere(center: [0, 1.5, -4], radius: 1.2, material: lensMaterial)

let scene: [Object] = [
    sphere,
    sphere2,
    sphere3,
    lens,
    plane
]

func intersect(ray: Ray) -> Intersection? {
    var result: Intersection? = nil
    var minDistance = Double.greatestFiniteMagnitude

    for object in scene {
        guard let hit = object.intersect(ray: ray) else { continue }
        if hit.distance < minDistance {
            minDistance = hit.distance
            result = hit
        }
    }

    return result
}

let imageWidth = 800
let imageHeight = 600

let aspect = Double(imageHeight) / Double(imageWidth)
let fieldOfView = 75 * .pi / 180.0

let width = 2 * distance * tan( fieldOfView / 2)
let height = width * aspect

let bytesPerLine = imageWidth * 4

let pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: imageWidth * imageHeight)
pixels.initialize(repeating: 0, count: imageHeight * imageWidth)


extension Color {
    var pixelValue: UInt32 {
        let clamped = clamp(self, min: [0, 0, 0], max: [1, 1, 1])
        let exponent = 1 / 2.2
        return UInt32(pow(clamped.x, exponent) * 0xFF) << 0 | UInt32(pow(clamped.y, exponent) * 0xFF) << 8 | UInt32(pow(clamped.z, exponent) * 0xFF) << 16 | 0xFF << 24
    }
}


let light: Point = [5, 10, -5]
let ambient: Color = [1, 1, 1] * 0.1
let diffuse: Color = [1, 1, 1] * 0.4
let specular: Color = [1, 1, 1] * 0.8
let ambientIoR: Double = 1 // Air


func shade(ray: Ray, intersection: Intersection, object: Object, material: Material, traceSecondary: (Ray) -> Color) -> Color {
    var ambientColor = material.ambient * ambient

    if material.checkboard {
        let u = Int(floor(intersection.point.x / 10))
        let v = Int(floor(intersection.point.z / 10))

        let evenU = u % 2 == 0
        let evenV = v % 2 == 0

        if evenU == evenV {
            ambientColor = [1, 0, 0] * ambient
        } else {
            ambientColor = [0, 0, 1] * ambient
        }
    }

    let v = -ray.direction

    if material.reflecting {
        let r = 2 * dot(v, intersection.normal) * intersection.normal - v
        let reflectedRay = Ray(origin: intersection.point, direction: r)
        let reflected = material.reflectingPower * traceSecondary(reflectedRay)
        ambientColor += reflected
    }

    let lightRay = Ray(from: intersection.point, to: light)
    if let lightHit = intersect(ray: lightRay), lightHit.distance < lightRay.length {
        return ambientColor
    }

    let l = lightRay.direction
    let r = 2 * dot(l, intersection.normal) * intersection.normal - l

    return ambientColor
        + material.diffuse * max(0, dot(l, intersection.normal)) * diffuse
        + material.specular * pow(max(0, dot(r, v)), material.shininess) * specular
}

let background: Color = [0, 0, 0]
let maxDepth = 10

var firedRays = 0

func trace(ray: Ray, depth: Int = 0) -> Color {
    guard depth < maxDepth else { return background }

    firedRays += 1
    guard let intersection = intersect(ray: ray) else { return background }

    return shade(ray: ray, intersection: intersection, object: intersection.object, material: intersection.object.material, traceSecondary: { trace(ray: $0, depth: depth + 1) })
}

let supersample = 4

let start = DispatchTime.now()
DispatchQueue.concurrentPerform(iterations: imageHeight) { y in

    var offset = y * imageWidth

    for x in 0..<imageWidth {

        var color: Color = [0, 0, 0]
        for _ in 0..<supersample {
            let offsetY = Double.random(in: -0.5..<0.5)
            let offsetX = Double.random(in: -0.5..<0.5)
            let yScreen = height * (0.5 - (Double(y) + offsetY) / Double(imageHeight))
            let xScreen = width * ((Double(x) + offsetX) / Double(imageWidth) - 0.5)

            let screenPoint = camera + distance * forward + xScreen * right + yScreen * up
            let ray = Ray(from: camera, to: screenPoint)

            color += trace(ray: ray)
        }

        pixels[offset] = (color / Double(supersample)).pixelValue

        offset += 1
    }
}
let end = DispatchTime.now()
let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) * 1e-9
let pixelCount = imageWidth * imageHeight

print("Time elapsed", duration, "s")
print("Fired", firedRays, "rays")
print("Time per pixel", duration / Double(pixelCount) * 1e6, "µs" )
print("Time per ray", duration / Double(firedRays) * 1e6, "µs")
print("Rays per pixel", Double(firedRays) / Double(pixelCount))

let data = UnsafeMutableRawPointer(pixels)

let context = CGContext(data: data, width: imageWidth, height: imageHeight, bitsPerComponent: 8, bytesPerRow: bytesPerLine, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)

let image = context?.makeImage()

let url = URL(fileURLWithPath: "/Users/sven/Desktop/test.png")

var success = false
var error: NSError? = nil

let coordinator = NSFileCoordinator(filePresenter: nil)
coordinator.coordinate(writingItemAt: url, options: [], error: &error) { newUrl in
    let dest = CGImageDestinationCreateWithURL(newUrl as CFURL, kUTTypePNG, 1, nil)!
    CGImageDestinationAddImage(dest, image!, nil)
    CGImageDestinationFinalize(dest)
    success = true
}

if !success, let error = error {
    print("Error writing output file: ", error)
}
