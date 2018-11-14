

import simd
import Dispatch

typealias Vec = double3

extension Vec {
    var normalized : Vec {
        return normalize(self)
    }

    var squaredLength : Double {
        return length_squared(self)
    }

    var length : Double {
        return simd.length(self)
    }
}

struct Material {
    let color : Vec
}

struct HitRecord {
    let t : Double
    let p : Vec
    let normal : Vec
    let material : Material
}

protocol Primitive {
    func intersect(_ r : Ray) -> HitRecord?
}

struct Sphere : Primitive {
    let center : Vec
    let radius : Double
    let material : Material

    func intersect(_ r : Ray) -> HitRecord? {
        let a = r.start - center
        let q = dot(a,a) - pow(radius, 2)
        let p2 = dot(a,r.dir)

        let det = pow(p2,2) - q

        guard det >= 0 else {
            return nil;
        }
        let root = sqrt(det)

        let t = min(-p2 + root, -p2 - root);
        guard t >= 0 else {
            return nil
        }
        let p = r.p(t)
        let n = (p - center).normalized

        return HitRecord(t: t, p: p, normal: n, material: material)
    }
}

struct Plane : Primitive {
    let point : Vec
    let normal : Vec
    let material : Material

    func intersect(_ r : Ray) -> HitRecord? {

        let bottom = dot(normal,r.dir)
        guard bottom != 0 else {
            return nil
        }

        let t = dot(normal,point - r.start) / bottom
        guard t >= 0 else {
            return nil
        }

        return HitRecord(t: t, p: r.p(t), normal: normal, material: material)
    }
}

struct Ray {
    let start : Vec
    let dir : Vec

    func p(_ t : Double) -> Vec {
        return start + t * dir
    }
}

let π = M_PI

func rnd() -> Double {
    return Double(arc4random()) / Double(UInt32.max) - 0.5
}

struct Viewport {
    let origin : Vec
    let width : Double
    let height : Double

    let fov_x = 45.0 * π / 180.0
    let fov_y = 45.0 * π / 180.0
    let distance = 10.0;


    func ray(x : Double, y : Double) -> Ray {
        let w = distance * tan(fov_x / 2.0) * 2.0
        let h = distance * tan(fov_y / 2.0) * 2.0

        let screenPoint = Vec(w*(x - width / 2) / width, h * (y - height / 2) / height, 0) + origin + Vec(0,0,1)*distance
        return Ray(start: origin, dir: (screenPoint - origin).normalized)
    }
}

class Image {
    let width : Int
    let height : Int
    var data : [UInt8]

    static let BytesPerPixel = 3

    init(width w : Int, height h : Int) {
        width = w
        height = h
        data = Array(repeating: 0, count: Image.BytesPerPixel * width * height)

    }

    func setPixel(x : Int, y : Int, color : Vec) {
        let c = clamp(color * Double(UInt8.max), min: 0, max: Double(UInt8.max))

        let start = (x + y * width) * Image.BytesPerPixel
        data[start + 0] = UInt8(c.z)
        data[start + 1] = UInt8(c.y)
        data[start + 2] = UInt8(c.x)
    }

    func write(file : String) {
        func lo(_ x : Int) -> UInt8 {
            let v = UInt16(x)
            return UInt8(v & 0xFF)
        }

        func hi(_ x : Int) -> UInt8 {
            let v = UInt16(x)
            return UInt8((v >> 8) & 0xFF)
        }

        var header : [UInt8] = [
            0,
            0,
            2,
            0, 0, 0, 0, 0,
            0, 0, 0, 0,
            lo(width), hi(width), lo(height), hi(height),
            24, 0,
        ]

        let f = file.withCString {
            return open($0, O_CREAT|O_WRONLY|O_TRUNC, S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH);
        }

        _ = Darwin.write(f, &header, header.count)
        _ = Darwin.write(f,&data,data.count)

        close(f)
    }
}


let image = Image(width: 500, height: 500)
let viewport = Viewport(origin: Vec(0,0,-10), width: Double(image.width), height: Double(image.height))

let light = Vec(0, 20, 5)
let diffuseColor = Vec(1, 1, 0)
let diffusePower = 0.9
let specularHardness = 20.0
let specularPower = 0.8
let specularColor = Vec(1, 0, 0)
let ambientColor = Vec(1) * 0.5

func clamp(x : Double, _ min : Double, _ max : Double) -> Double {
    if (x < min) {
        return min
    }
    else if (x > max) {
        return max
    }
    else {
        return x
    }
}

struct Scene {
    var primitives : [Primitive]

    func intersect(_ r : Ray) -> HitRecord? {
        let hits = primitives.flatMap { $0.intersect(r) }
        return hits.min { $0.t < $1.t }
    }
}


let scene = Scene(primitives: [
    Sphere(center: Vec(0, 0, 5), radius: 4, material: Material(color: Vec(1, 0, 0))),
    Plane(point: Vec(0,0,5), normal: Vec(0,1,0), material: Material(color: Vec(0, 1, 0))),
])


func colorAt(x : Int, y : Int) -> Vec {
    let ray = viewport.ray(x: Double(x), y: Double(y))
    if let hit = scene.intersect(ray) {
//        let distance = 1.0 / (light - hit.p).length
//        let lightdir = (light - hit.p).normalized
//        let intensity = clamp(dot(hit.normal, lightdir), 0, 1)
//        let diffuse = intensity * hit.material.color * diffusePower * distance
//
//        let H = (lightdir + ray.dir).normalized
//        let specularIntensity = pow(clamp(dot(hit.normal,H), 0, 1), specularHardness)
//        let specular = specularIntensity * specularColor * specularPower * distance

        let shadowRay = Ray(start: ray.p(hit.t - 0.1), dir: (light - hit.p).normalized)
        var colorMultiplier = 1.0
        if let _ = scene.intersect(shadowRay) {
            colorMultiplier = 0.5
        }

        return clamp( colorMultiplier * hit.material.color, min: 0, max: 1)
    }

    return Vec(0.0)
}

DispatchQueue.concurrentPerform(iterations: image.height) { y in
    for x in 0..<image.width {
        let ray = viewport.ray(x: Double(x), y: Double(y))
        image.setPixel(x: x, y: y, color: colorAt(x: x,y:y))
    }
}

image.write(file: "/Users/sven/test.tga")
