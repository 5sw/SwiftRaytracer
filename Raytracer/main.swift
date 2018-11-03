import simd
import CoreGraphics
import Foundation

typealias Vector = vector_double3
typealias Point = vector_double3

struct Ray {
    let origin: Point
    let direction: Vector

    init(from: Point, to: Point) {
        origin = from
        direction = normalize(to - from)
    }

    func at(_ distance: Double) -> Point {
        return origin + direction * distance
    }
}

struct Intersection {
    let point: Point
    let normal: Vector
    let distance: Double

    init(ray: Ray, distance: Double, normal: Vector) {
        self.point = ray.at(distance)
        self.normal = normal
        self.distance = distance
    }

    init(point: Point, distance: Double, normal: Vector) {
        self.point = point
        self.distance = distance
        self.normal = normal
    }
}

protocol Object {
    func intersect(ray: Ray) -> Intersection?
}

struct Sphere: Object {
    let center: Point
    let radius: Double


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

        return Intersection(point: p, distance: t, normal: normal)
    }
}

struct Plane: Object {
    let point: Point
    let normal: Vector

    func intersect(ray: Ray) -> Intersection? {
        let denom = dot(normal, ray.direction)
        guard denom != 0 else { return nil }

        let t = dot(point - ray.origin, normal) / denom
        guard t > 0 else { return nil }

        return Intersection(ray: ray, distance: t, normal: normal)
    }
}


let camera: Point = [0, 0, -10]
let up: Vector = [0, 1, 0]
let lookAt: Point = [0, 0, 0]
let forward: Vector = normalize(lookAt - camera)
let distance = length(lookAt - camera)
let right = cross(up, forward)

let sphere = Sphere(center: [0, 0, 0], radius: 2)
let plane = Plane(point: [0, -0.2, 0], normal: up)

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

let imageHeight = 240
let imageWidth = 320

let aspect = Double(imageHeight) / Double(imageWidth)
let fieldOfView = 90 * .pi / 180.0

let width = 2 * distance * tan( fieldOfView / 2)
let height = width * aspect

let bytesPerLine = imageWidth * 4

let pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: imageWidth * imageHeight)
pixels.initialize(repeating: 0, count: imageHeight * imageWidth)

typealias Color = vector_double3

extension Color {
    var pixelValue: UInt32 {
        let clamped = clamp(self, min: [0, 0, 0], max: [1, 1, 1])
        let exponent = 1 / 2.2
        return UInt32(pow(clamped.x, exponent) * 0xFF) << 0 | UInt32(pow(clamped.y, exponent) * 0xFF) << 8 | UInt32(pow(clamped.z, exponent) * 0xFF) << 16 | 0xFF << 24
    }
}


let light: Point = [0, 10, -5]
let ambient: Color = [1, 1, 1] * 0.1
let diffuse: Color = [1, 1, 1] * 0.4
let specular: Color = [1, 1, 1] * 0.8

struct Material {
    let ambient: Color
    let diffuse: Color
    let specular: Color
    let shininess: Double
}

let material = Material(
    ambient: [1, 0, 0],
    diffuse: [1, 0, 0],
    specular: [1, 0, 1],
    shininess: 40
)

func shade(intersection: Intersection, material: Material) -> Color {
    let l = normalize(light - intersection.point)
    let r = 2 * dot(l, intersection.normal) * intersection.normal - l
    let v = normalize(camera - intersection.point)

    return material.ambient * ambient
        + material.diffuse * max(0, dot(l, intersection.normal)) * diffuse
        + material.specular * pow(max(0, dot(r, v)), material.shininess) * specular
}


DispatchQueue.concurrentPerform(iterations: imageHeight) { y in
    //for y in 0..<imageHeight {
    let yScreen = height * (0.5 - Double(y) / Double(imageHeight))

    var offset = y * imageWidth

    for x in 0..<imageWidth {
        let xScreen = width * (Double(x) / Double(imageWidth) - 0.5)

        let screenPoint = camera + distance * forward + xScreen * right + yScreen * up

        let ray = Ray(from: camera, to: screenPoint)

        if let intersection = intersect(ray: ray) {
            pixels[offset] = shade(intersection: intersection, material: material).pixelValue
        }

        offset += 1
    }

}

let data = UnsafeMutableRawPointer(pixels)

let context = CGContext(data: data, width: imageWidth, height: imageHeight, bitsPerComponent: 8, bytesPerRow: bytesPerLine, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)

let image = context?.makeImage()

let url = URL(fileURLWithPath: "/Users/sven/Desktop/test.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil)!
CGImageDestinationAddImage(dest, image!, nil)
CGImageDestinationFinalize(dest)

