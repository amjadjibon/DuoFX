import simd

struct MeshVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

enum MeshFactory {
    static func grid(segments: Int = 64) -> [MeshVertex] {
        precondition(segments > 0)
        var vertices: [MeshVertex] = []
        for row in 0..<segments {
            let bottom = Float(row) / Float(segments)
            let top = Float(row + 1) / Float(segments)
            let a = MeshVertex(position: [-1, bottom * 2 - 1], uv: [0, 1 - bottom])
            let b = MeshVertex(position: [1, bottom * 2 - 1], uv: [1, 1 - bottom])
            let c = MeshVertex(position: [-1, top * 2 - 1], uv: [0, 1 - top])
            let d = MeshVertex(position: [1, top * 2 - 1], uv: [1, 1 - top])
            vertices.append(contentsOf: [a, b, c, b, d, c])
        }
        return vertices
    }
}
