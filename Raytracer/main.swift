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

struct Intersection {
    let point: Point
    let normal: Vector
    let distance: Double
    let object: Object

    init(ray: Ray, distance: Double, normal: Vector, object: Object) {
        self.point = ray.at(distance)
        self.normal = normal
        self.distance = distance
        self.object = object
    }

    init(point: Point, distance: Double, normal: Vector, object: Object) {
        self.point = point
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
}

protocol Object: class {
    func intersect(ray: Ray) -> Intersection?
    var material: Material { get }
}

class Sphere: Object {
    let center: Point
    let radius: Double

    init(center: Point, radius: Double) {
        self.center = center
        self.radius = radius
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

    var material: Material {
        return Material(
            ambient: [3, 0, 0],
            diffuse: [1, 0, 0],
            specular: [1, 0, 1],
            shininess: 40,
            reflecting: true,
            reflectingPower: [1, 1, 1]
        )
    }
}

class Plane: Object {
    let point: Point
    let normal: Vector

    init(point: Point, normal: Vector) {
        self.point = point
        self.normal = normal
    }

    func intersect(ray: Ray) -> Intersection? {
        let denom = dot(normal, ray.direction)
        guard denom != 0 else { return nil }

        let t = dot(point - ray.origin, normal) / denom
        guard t > 0 else { return nil }

        return Intersection(ray: ray, distance: t, normal: normal, object: self)
    }

    var material: Material {
        return Material(
            ambient: [1, 1, 1] * 0.1,
            diffuse: [1, 1, 1] * 0,
            specular: [1, 1, 1] * 0,
            shininess: 100,
            reflecting: true,
            reflectingPower: [1, 1, 1] * 0.5
        )
    }
}


let camera: Point = [0, 0, -10]
let up: Vector = [0, 1, 0]
let lookAt: Point = [0, 0, 0]
let forward: Vector = normalize(lookAt - camera)
let distance = length(lookAt - camera)
let right = cross(up, forward)

let sphere = Sphere(center: [0, 0, 0], radius: 2)
let plane = Plane(point: [0, -5, 0], normal: up)

let scene: [Object] = [
    sphere,
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

let imageWidth = 2880
let imageHeight = 1800

let aspect = Double(imageHeight) / Double(imageWidth)
let fieldOfView = 90 * .pi / 180.0

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

func shade(intersection: Intersection, material: Material, traceSecondary: (Ray) -> Color) -> Color {
    let ambientColor = material.ambient * ambient

    let lightRay = Ray(from: intersection.point, to: light)
    if let lightHit = intersect(ray: lightRay), lightHit.distance < lightRay.length {
        return ambientColor
    }

    let l = lightRay.direction
    let r = 2 * dot(l, intersection.normal) * intersection.normal - l
    let v = normalize(camera - intersection.point)

    var reflected: Color = [0, 0, 0]
    if material.reflecting {
        let r = 2 * dot(v, intersection.normal) * intersection.normal - v
        let reflectedRay = Ray(origin: intersection.point, direction: r)
        reflected = material.reflectingPower * traceSecondary(reflectedRay)
    }

    return ambientColor
        + material.diffuse * max(0, dot(l, intersection.normal)) * diffuse
        + material.specular * pow(max(0, dot(r, v)), material.shininess) * specular
        + reflected
}

let background: Color = [0, 0, 0]
let maxDepth = 10

var firedRays = 0

func trace(ray: Ray, depth: Int = 0) -> Color {
    guard depth < maxDepth else { return background }

    firedRays += 1
    guard let intersection = intersect(ray: ray) else { return background }

    return shade(intersection: intersection, material: intersection.object.material, traceSecondary: { trace(ray: $0, depth: depth + 1) })
}


DispatchQueue.concurrentPerform(iterations: imageHeight) { y in
    let yScreen = height * (0.5 - Double(y) / Double(imageHeight))

    var offset = y * imageWidth

    for x in 0..<imageWidth {
        let xScreen = width * (Double(x) / Double(imageWidth) - 0.5)

        let screenPoint = camera + distance * forward + xScreen * right + yScreen * up

        let ray = Ray(from: camera, to: screenPoint)
        pixels[offset] = trace(ray: ray).pixelValue

        offset += 1
    }
}

print("Fired", firedRays, "rays")

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

if !success {
    print("Error writing output file: ", error)
}
