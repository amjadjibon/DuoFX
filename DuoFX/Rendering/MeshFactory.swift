import simd

struct MeshVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

enum MeshFactory {
    static func fullScreenQuad() -> [MeshVertex] {
        let a = MeshVertex(position: [-1, -1], uv: [0, 1])
        let b = MeshVertex(position: [1, -1], uv: [1, 1])
        let c = MeshVertex(position: [-1, 1], uv: [0, 0])
        let d = MeshVertex(position: [1, 1], uv: [1, 0])
        return [a, b, c, b, d, c]
    }
}
