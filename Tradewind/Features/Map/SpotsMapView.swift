import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Every spot at once, with range rings and a line to whichever one you tap.
///
/// The map is the answer to "which of these is actually near me" in a way a list of distances
/// is not. It stays themed — a tinted overlay and themed annotations — so it does not feel like
/// a different app bolted on.
struct SpotsMapView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme

    @Query(
        filter: #Predicate<Spot> { $0.deletedAt == nil },
        sort: \Spot.capturedAt,
        order: .reverse
    ) private var spots: [Spot]

    @State private var location = LocationService.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedSpotID: UUID?
    @State private var showsRangeRings = true

    private var ranked: [RankedSpot] {
        SpotRanking.rank(spots, from: location.coordinate)
    }

    private var selected: RankedSpot? {
        guard let selectedSpotID else { return ranked.first }
        return ranked.first { $0.id == selectedSpotID }
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
            header
            if let selected { selectionBar(selected) }
        }
    }

    private func selectionBar(_ selected: RankedSpot) -> some View {
        VStack {
            Spacer()
            SelectedSpotBar(
                ranked: selected,
                unitPreference: settings.unitPreference,
                onOpen: { router.openSpot(id: selected.spot.id) }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera, selection: $selectedSpotID) {
            UserAnnotation()
            rangeRings
            routeLine
            pins
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        // Empty on purpose: the header's glass cluster already carries locate, and the
        // system compass lands under the status bar on an edge-to-edge map.
        .mapControls {}
        .overlay {
            // Pulls the map into the app's palette without hiding the geography.
            theme.canvas.opacity(0.18)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .ignoresSafeArea(edges: .top)
    }

    @MapContentBuilder
    private var rangeRings: some MapContent {
        if showsRangeRings, let origin = location.coordinate {
            let centre = CLLocationCoordinate2D(
                latitude: origin.latitude,
                longitude: origin.longitude
            )
            ForEach([100.0, 500.0, 1_000.0], id: \.self) { radius in
                MapCircle(center: centre, radius: radius)
                    .foregroundStyle(.clear)
                    .stroke(theme.accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    /// A great-circle line rather than a straight one on the projection: over short distances they
    /// agree, and over long ones only the great circle is the truth.
    @MapContentBuilder
    private var routeLine: some MapContent {
        if let origin = location.coordinate, let selected {
            MapPolyline(coordinates: Self.arcPoints(from: origin, to: selected.spot.coordinate))
                .stroke(
                    theme.accent.opacity(0.85),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 8])
                )
        }
    }

    @MapContentBuilder
    private var pins: some MapContent {
        ForEach(ranked) { item in
            Annotation(
                item.spot.displayName,
                coordinate: CLLocationCoordinate2D(
                    latitude: item.spot.latitude,
                    longitude: item.spot.longitude
                ),
                anchor: .bottom
            ) {
                SpotMapPin(
                    spot: item.spot,
                    isSelected: item.id == selectedSpotID,
                    isPinned: item.spot.isPinned
                )
            }
            .tag(item.id)
        }
    }

    /// All four controls share one `GlassEffectContainer` over the edge-to-edge map — one
    /// cluster of glass, not four separate discs, so the system can blend and morph them as
    /// a unit. Active states carry the accent as a glass tint.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(spots.count) saved").eyebrowStyle(theme: theme)
                Text("The map")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                    .accessibilityIdentifier("map-screen")
            }
            Spacer()
            GlassEffectContainer {
                HStack(spacing: 10) {
                    glassControl("slider.horizontal.3", label: "Settings") {
                        router.isShowingSettings = true
                    }
                    .accessibilityIdentifier("settings-button")
                    glassControl("mappin.and.ellipse", tinted: true, label: "Save this location") {
                        router.isShowingSaveHere = true
                    }
                    glassControl(
                        showsRangeRings ? "dot.circle.and.hand.point.up.left.fill" : "dot.circle",
                        tinted: showsRangeRings,
                        label: showsRangeRings ? "Hide range rings" : "Show range rings"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { showsRangeRings.toggle() }
                    }
                    glassControl("scope", label: "Centre on me", action: recentre)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .background { headerScrim }
    }

    private func glassControl(
        _ symbol: String,
        tinted: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tinted ? theme.onAccent : theme.text)
                .frame(width: 40, height: 40)
        }
        .glassEffect(
            tinted ? .regular.tint(theme.accent).interactive() : .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel(label)
    }

    /// Keeps the title legible over whatever geography happens to be underneath it.
    private var headerScrim: some View {
        LinearGradient(
            colors: [theme.canvas.opacity(0.85), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 160)
        .offset(y: -30)
        .allowsHitTesting(false)
    }

    private func recentre() {
        guard let origin = location.coordinate else {
            location.requestOneShotLocation()
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: origin.latitude,
                    longitude: origin.longitude
                ),
                latitudinalMeters: 1_600,
                longitudinalMeters: 1_600
            ))
        }
    }

    /// Samples the great circle so `MapPolyline` draws a curve rather than a chord.
    static func arcPoints(from origin: Coordinate, to destination: Coordinate) -> [CLLocationCoordinate2D] {
        let steps = 48
        return (0...steps).map { step in
            let point = BearingMath.interpolate(
                from: origin,
                to: destination,
                fraction: Double(step) / Double(steps)
            )
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
    }
}

// MARK: - Pin

private struct SpotMapPin: View {
    @Environment(\.theme) private var theme

    var spot: Spot
    var isSelected: Bool
    var isPinned: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(theme.accent)
                    .frame(width: isSelected ? 56 : 44, height: isSelected ? 56 : 44)
                    .shadow(color: theme.glow.opacity(0.6), radius: isSelected ? 12 : 5)

                SpotPhotoView(spot: spot, sizeClass: .pin)
                    .frame(width: isSelected ? 50 : 38, height: isSelected ? 50 : 38)
                    .clipShape(Circle())

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.canvas)
                        .padding(3)
                        .background { Circle().fill(theme.secondary) }
                        .offset(x: 16, y: -16)
                }
            }

            // Little stem so the circle reads as pinned to a point on the ground.
            Triangle()
                .fill(theme.accent)
                .frame(width: 12, height: 8)
                .offset(y: -1)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Selected spot bar

private struct SelectedSpotBar: View {
    @Environment(\.theme) private var theme

    var ranked: RankedSpot
    var unitPreference: UnitPreference
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Surface(cornerRadius: 22, padding: 14) {
                HStack(spacing: 14) {
                    SpotPhotoView(spot: ranked.spot, sizeClass: .pin)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radii.avatar, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ranked.spot.displayName)
                            .font(theme.cardTitleFont)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Text(ranked.spot.subtitle)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        if let metres = ranked.metres {
                            let readout = DistanceFormatting.readout(
                                metres: metres,
                                preference: unitPreference
                            )
                            Text(readout.combined)
                                .font(theme.cardNumberFont)
                                .monospacedDigit()
                                .foregroundStyle(theme.text)
                        }
                        Text("Point me there")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}
