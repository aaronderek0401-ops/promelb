//
//  ContentView.swift
//  promelb
//
//  Created by Zijian DING on 22/5/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var bodyCount = 3
    @State private var bodySizes = [46.0, 46.0, 46.0, 46.0]
    @State private var seed = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GalaxyPreview(
                    bodyCount: bodyCount,
                    bodySizes: Array(bodySizes.prefix(bodyCount)),
                    seed: seed
                )
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .padding(.horizontal)

                controls
            }
            .padding(.vertical)
            .background(Color(red: 0.02, green: 0.02, blue: 0.05))
            .navigationTitle("Gravity Draft")
            .toolbar {
                Button {
                    seed = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Star bodies")
                        .font(.headline)

                    Picker("Star bodies", selection: $bodyCount) {
                        ForEach(1...4, id: \.self) { count in
                            Text("\(count)")
                                .tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(0..<bodyCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Body \(index + 1)", systemImage: "circle.hexagongrid.circle.fill")
                            Spacer()
                            Text("\(Int(bodySizes[index]))")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $bodySizes[index], in: 28...86, step: 1)
                            .tint(OrbitalBody.palette[index].base)
                    }
                }

                Text("Size maps to radius and mass. Bodies attract at a distance, repel on contact, and keep a soft orbital drift instead of settling into a static clump.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
        }
    }
}

private struct GalaxyPreview: View {
    let bodyCount: Int
    let bodySizes: [Double]
    let seed: UUID

    @State private var bodies: [OrbitalBody] = []
    @State private var lastUpdate = Date()
    @State private var camera = GalaxyCamera(center: .zero, scale: 1)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                drawBackground(in: rect, context: context)

                let updatedBodies = updateBodies(for: timeline.date, in: size)
                let view = cameraView(for: updatedBodies, in: size)
                drawOrbits(for: updatedBodies, view: view, size: size, in: &context)
                drawBodies(updatedBodies, view: view, size: size, in: &context)
            }
        }
        .onAppear {
            resetBodies(in: CGSize(width: 360, height: 430))
        }
        .onChange(of: bodyCount) { _ in
            resetBodies(in: CGSize(width: 360, height: 430))
        }
        .onChange(of: bodySizes) { _ in
            applySizes()
        }
        .onChange(of: seed) { _ in
            resetBodies(in: CGSize(width: 360, height: 430))
        }
    }

    private func updateBodies(for date: Date, in size: CGSize) -> [OrbitalBody] {
        DispatchQueue.main.async {
            if bodies.count != bodyCount {
                resetBodies(in: size)
                return
            }

            let elapsed = min(max(date.timeIntervalSince(lastUpdate), 1.0 / 120.0), 1.0 / 24.0)
            stepSimulation(deltaTime: elapsed, in: size)
            lastUpdate = date
        }

        return bodies
    }

    private func resetBodies(in size: CGSize) {
        lastUpdate = .now
        camera = GalaxyCamera(center: .zero, scale: 1)
        bodies = (0..<bodyCount).map { index in
            let angle = Double(index) / Double(max(bodyCount, 1)) * Double.pi * 2 + Double(seed.uuidString.hashValue % 100) / 300
            let distance = 90 + Double(index % 2) * 46
            let position = CGPoint(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            let tangent = CGVector(dx: -sin(angle), dy: cos(angle))
            let speed = 48 + Double(index) * 7

            return OrbitalBody(
                id: index,
                position: position,
                velocity: CGVector(dx: tangent.dx * speed, dy: tangent.dy * speed),
                radius: bodySizes[index],
                mass: mass(for: bodySizes[index]),
                color: OrbitalBody.palette[index],
                trail: [position]
            )
        }
    }

    private func applySizes() {
        for index in bodies.indices {
            guard index < bodySizes.count else { continue }
            bodies[index].radius = bodySizes[index]
            bodies[index].mass = mass(for: bodySizes[index])
        }
    }

    private func mass(for radius: Double) -> Double {
        pow(radius / 36, 2.15) * 14
    }

    private func stepSimulation(deltaTime: TimeInterval, in size: CGSize) {
        guard !bodies.isEmpty else { return }

        var accelerations = Array(repeating: CGVector.zero, count: bodies.count)
        let springStrength = 1.05
        let repulsionStrength = 980.0
        let centerStrength = 0.018

        for i in bodies.indices {
            for j in bodies.indices where i != j {
                let dx = bodies[j].position.x - bodies[i].position.x
                let dy = bodies[j].position.y - bodies[i].position.y
                let distance = max(0.001, hypot(dx, dy))
                let directionX = dx / distance
                let directionY = dy / distance
                let comfortableDistance = (bodies[i].radius + bodies[j].radius) * 1.65 + 72
                let stretch = distance - comfortableDistance
                let pull = springStrength * stretch * bodies[j].mass / (bodies[i].mass + bodies[j].mass)

                accelerations[i].dx += directionX * pull
                accelerations[i].dy += directionY * pull

                if stretch < 0 {
                    let compression = -stretch / comfortableDistance
                    let push = repulsionStrength * compression * compression
                    accelerations[i].dx -= directionX * push
                    accelerations[i].dy -= directionY * push
                }
            }

            let centerDx = -bodies[i].position.x
            let centerDy = -bodies[i].position.y
            let centerDistance = max(1, hypot(centerDx, centerDy))
            let orbitalDirection = CGVector(dx: -centerDy / centerDistance, dy: centerDx / centerDistance)
            accelerations[i].dx += centerDx * centerStrength + orbitalDirection.dx * 6
            accelerations[i].dy += centerDy * centerStrength + orbitalDirection.dy * 6
        }

        for index in bodies.indices {
            bodies[index].velocity.dx += accelerations[index].dx * deltaTime
            bodies[index].velocity.dy += accelerations[index].dy * deltaTime

            bodies[index].velocity.dx *= 0.9995
            bodies[index].velocity.dy *= 0.9995

            let minSpeed = 42.0
            let currentSpeed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            if currentSpeed < minSpeed {
                let dx = bodies[index].position.x
                let dy = bodies[index].position.y
                let distance = max(1, hypot(dx, dy))
                bodies[index].velocity.dx += -dy / distance * 24 * deltaTime
                bodies[index].velocity.dy += dx / distance * 24 * deltaTime
            }

            let maxSpeed = 190.0
            let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            if speed > maxSpeed {
                bodies[index].velocity.dx = bodies[index].velocity.dx / speed * maxSpeed
                bodies[index].velocity.dy = bodies[index].velocity.dy / speed * maxSpeed
            }

            bodies[index].position.x += bodies[index].velocity.dx * deltaTime
            bodies[index].position.y += bodies[index].velocity.dy * deltaTime

            keepBodyNearSystem(index)
        }

        resolveOverlaps()

        for index in bodies.indices {
            bodies[index].trail.append(bodies[index].position)
            if bodies[index].trail.count > 90 {
                bodies[index].trail.removeFirst()
            }
        }
    }

    private func resolveOverlaps() {
        guard bodies.count > 1 else { return }

        for i in bodies.indices {
            for j in bodies.indices where j > i {
                var dx = bodies[j].position.x - bodies[i].position.x
                var dy = bodies[j].position.y - bodies[i].position.y
                var distance = hypot(dx, dy)

                if distance < 0.001 {
                    dx = 1
                    dy = 0
                    distance = 1
                }

                let minDistance = (bodies[i].radius + bodies[j].radius) * 1.02
                guard distance < minDistance else { continue }

                let normalX = dx / distance
                let normalY = dy / distance
                let overlap = minDistance - distance
                let totalMass = bodies[i].mass + bodies[j].mass
                let iShare = bodies[j].mass / totalMass
                let jShare = bodies[i].mass / totalMass

                bodies[i].position.x -= normalX * overlap * iShare
                bodies[i].position.y -= normalY * overlap * iShare
                bodies[j].position.x += normalX * overlap * jShare
                bodies[j].position.y += normalY * overlap * jShare

                let relativeVelocityX = bodies[j].velocity.dx - bodies[i].velocity.dx
                let relativeVelocityY = bodies[j].velocity.dy - bodies[i].velocity.dy
                let separatingVelocity = relativeVelocityX * normalX + relativeVelocityY * normalY

                if separatingVelocity < 0 {
                    let bounce = 0.18
                    let impulse = -(1 + bounce) * separatingVelocity / (1 / bodies[i].mass + 1 / bodies[j].mass)
                    bodies[i].velocity.dx -= impulse * normalX / bodies[i].mass
                    bodies[i].velocity.dy -= impulse * normalY / bodies[i].mass
                    bodies[j].velocity.dx += impulse * normalX / bodies[j].mass
                    bodies[j].velocity.dy += impulse * normalY / bodies[j].mass

                    let tangentX = -normalY
                    let tangentY = normalX
                    let swirl = 7.0
                    bodies[i].velocity.dx -= tangentX * swirl * jShare
                    bodies[i].velocity.dy -= tangentY * swirl * jShare
                    bodies[j].velocity.dx += tangentX * swirl * iShare
                    bodies[j].velocity.dy += tangentY * swirl * iShare
                }

                keepBodyNearSystem(i)
                keepBodyNearSystem(j)
            }
        }
    }

    private func keepBodyNearSystem(_ index: Int) {
        let distance = hypot(bodies[index].position.x, bodies[index].position.y)
        let limit = 680.0
        guard distance > limit else { return }

        let normalX = bodies[index].position.x / distance
        let normalY = bodies[index].position.y / distance
        bodies[index].position.x = normalX * limit
        bodies[index].position.y = normalY * limit
        let outwardVelocity = bodies[index].velocity.dx * normalX + bodies[index].velocity.dy * normalY
        if outwardVelocity > 0 {
            bodies[index].velocity.dx -= normalX * outwardVelocity * 1.25
            bodies[index].velocity.dy -= normalY * outwardVelocity * 1.25
        }
    }

    private func cameraView(for bodies: [OrbitalBody], in size: CGSize) -> GalaxyCamera {
        guard let first = bodies.first else {
            return GalaxyCamera(center: .zero, scale: 1)
        }

        var minX = first.position.x - first.radius
        var maxX = first.position.x + first.radius
        var minY = first.position.y - first.radius
        var maxY = first.position.y + first.radius

        for body in bodies {
            minX = min(minX, body.position.x - body.radius * 1.7)
            maxX = max(maxX, body.position.x + body.radius * 1.7)
            minY = min(minY, body.position.y - body.radius * 1.7)
            maxY = max(maxY, body.position.y + body.radius * 1.7)
        }

        let width = max(220, maxX - minX)
        let height = max(220, maxY - minY)
        let targetCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let targetScale = min(size.width * 0.72 / width, size.height * 0.72 / height, 1.25)
        let smoothed = GalaxyCamera(
            center: CGPoint(
                x: camera.center.x * 0.92 + targetCenter.x * 0.08,
                y: camera.center.y * 0.92 + targetCenter.y * 0.08
            ),
            scale: camera.scale * 0.90 + targetScale * 0.10
        )

        DispatchQueue.main.async {
            camera = smoothed
        }

        return smoothed
    }

    private func screenPoint(_ point: CGPoint, view: GalaxyCamera, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (point.x - view.center.x) * view.scale,
            y: size.height / 2 + (point.y - view.center.y) * view.scale
        )
    }

    private func drawBackground(in rect: CGRect, context: GraphicsContext) {
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.015, green: 0.016, blue: 0.04),
                    Color(red: 0.04, green: 0.025, blue: 0.08),
                    Color(red: 0.01, green: 0.014, blue: 0.030)
                ]),
                startPoint: rect.origin,
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )

        for index in 0..<48 {
            let x = rect.width * pseudoRandom(index, salt: 11)
            let y = rect.height * pseudoRandom(index, salt: 23)
            let opacity = 0.12 + pseudoRandom(index, salt: 41) * 0.28
            let radius = 0.6 + pseudoRandom(index, salt: 67) * 1.4
            let starRect = CGRect(x: x, y: y, width: radius, height: radius)
            context.fill(Path(ellipseIn: starRect), with: .color(.white.opacity(opacity)))
        }
    }

    private func drawOrbits(for bodies: [OrbitalBody], view: GalaxyCamera, size: CGSize, in context: inout GraphicsContext) {
        for body in bodies {
            guard body.trail.count > 2 else { continue }

            var path = Path()
            path.move(to: screenPoint(body.trail[0], view: view, size: size))
            for point in body.trail.dropFirst() {
                path.addLine(to: screenPoint(point, view: view, size: size))
            }

            context.stroke(
                path,
                with: .color(body.color.base.opacity(0.22)),
                style: StrokeStyle(lineWidth: max(0.8, body.radius * view.scale / 24), lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawBodies(_ bodies: [OrbitalBody], view: GalaxyCamera, size: CGSize, in context: inout GraphicsContext) {
        for body in bodies {
            let position = screenPoint(body.position, view: view, size: size)
            let radius = body.radius * view.scale
            let glowRect = CGRect(
                x: position.x - radius * 1.6,
                y: position.y - radius * 1.6,
                width: radius * 3.2,
                height: radius * 3.2
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [
                        body.color.base.opacity(0.35),
                        body.color.base.opacity(0.10),
                        .clear
                    ]),
                    center: position,
                    startRadius: radius * 0.15,
                    endRadius: radius * 1.65
                )
            )

            let bodyRect = CGRect(
                x: position.x - radius,
                y: position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: bodyRect),
                with: .radialGradient(
                    Gradient(colors: [
                        .white.opacity(0.95),
                        body.color.highlight.opacity(0.92),
                        body.color.base.opacity(0.86),
                        body.color.shadow.opacity(0.92)
                    ]),
                    center: CGPoint(
                        x: position.x - radius * 0.32,
                        y: position.y - radius * 0.38
                    ),
                    startRadius: radius * 0.05,
                    endRadius: radius * 1.25
                )
            )

            var rimContext = context
            rimContext.blendMode = .plusLighter
            rimContext.stroke(
                Path(ellipseIn: bodyRect.insetBy(dx: radius * 0.08, dy: radius * 0.08)),
                with: .color(.white.opacity(0.28)),
                lineWidth: max(1, radius / 18)
            )

            if radius > 58 {
                let ringRect = bodyRect.insetBy(dx: -radius * 0.28, dy: radius * 0.18)
                context.stroke(
                    Path(ellipseIn: ringRect),
                    with: .color(body.color.highlight.opacity(0.34)),
                    style: StrokeStyle(lineWidth: max(1.3, radius / 26))
                )
            }
        }
    }

    private func pseudoRandom(_ value: Int, salt: Int) -> Double {
        let raw = sin(Double(value * 97 + salt * 31)) * 10000
        return raw - floor(raw)
    }
}

private struct OrbitalBody: Identifiable {
    let id: Int
    var position: CGPoint
    var velocity: CGVector
    var radius: Double
    var mass: Double
    let color: OrbitalPalette
    var trail: [CGPoint]

    static let palette = [
        OrbitalPalette(
            base: Color(red: 0.35, green: 0.70, blue: 1.00),
            highlight: Color(red: 0.78, green: 0.94, blue: 1.00),
            shadow: Color(red: 0.07, green: 0.19, blue: 0.45)
        ),
        OrbitalPalette(
            base: Color(red: 0.92, green: 0.54, blue: 1.00),
            highlight: Color(red: 1.00, green: 0.83, blue: 1.00),
            shadow: Color(red: 0.34, green: 0.08, blue: 0.50)
        ),
        OrbitalPalette(
            base: Color(red: 0.38, green: 0.95, blue: 0.66),
            highlight: Color(red: 0.78, green: 1.00, blue: 0.83),
            shadow: Color(red: 0.05, green: 0.35, blue: 0.20)
        ),
        OrbitalPalette(
            base: Color(red: 1.00, green: 0.64, blue: 0.28),
            highlight: Color(red: 1.00, green: 0.88, blue: 0.55),
            shadow: Color(red: 0.52, green: 0.16, blue: 0.04)
        )
    ]
}

private struct OrbitalPalette {
    let base: Color
    let highlight: Color
    let shadow: Color
}

private struct GalaxyCamera {
    var center: CGPoint
    var scale: Double
}

#Preview {
    ContentView()
}
