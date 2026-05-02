import SwiftUI
import MapKit

enum DockMode {
    case idle, timeline, search
}

// MARK: - Main View
struct ContentView: View {
    @State private var dockMode: DockMode = .idle
    @State private var selectedDateID: UUID?
    @State private var waterData: [WaterData] = []
    @State private var selectedPersona: String = "Citizen"
    
    // Map State
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449), distance: 4_500_000)
    )
    @State private var locationSearch: String = ""
    @State private var showingLocationPicker = false
    @State private var isLocationSelected = false
    
    // Top Card State
    @State private var isTopCardExpanded = false

    // Map Consts
    private let californiaCenter = CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449)
    private let californiaZoomLevel: Double = 4_500_000
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // 1. MAP LAYER
            HomeMapView(position: $position)
                .mask(
                    Rectangle()
                        .padding(dockMode == .idle ? 0 : 30)
                        .blur(radius: dockMode == .idle ? 0 : 40)
                )
                .ignoresSafeArea()
            
            // OPTIONAL: Dimming background when card is expanded for premium look
            if isTopCardExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring()) { isTopCardExpanded = false }
                    }
                    .transition(.opacity)
            }
            
            // 2. DATA INSIGHT CARD (Top Center)
            VStack(spacing: 0) {
                if isLocationSelected {
                    DataInsightCard(
                        isExpanded: $isTopCardExpanded,
                        selectedPersona: $selectedPersona,
                        currentData: currentSelectedData,
                        locationName: locationSearch
                    )
                    .padding(.top, isTopCardExpanded ? 70 : 10) // Adjusts for Dynamic Island
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                Spacer()
            }
            // Logic to let card cover top safe area only when expanded
            .ignoresSafeArea(edges: isTopCardExpanded ? .top : [])
            .zIndex(isTopCardExpanded ? 10 : 1) // Ensures it stays above the dock when expanded

            // 3. THE FLUID GLASS DOCK
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    TimelineDockSegment(
                        mode: $dockMode,
                        selectedDateID: $selectedDateID,
                        data: waterData
                    )
                    
                    SearchDockSegment(
                        mode: $dockMode,
                        locationSearch: $locationSearch,
                        onSearchTap: { showingLocationPicker = true },
                        onResetTap: resetToCalifornia
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                // Hide dock smoothly when the top card is taking up the whole screen
                .opacity(isTopCardExpanded ? 0 : 1)
                .offset(y: isTopCardExpanded ? 100 : 0)
            }
            .zIndex(5)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationSearchView(searchText: $locationSearch) { coordinate, name in
                withAnimation(.easeInOut(duration: 2.0)) {
                    position = .camera(MapCamera(centerCoordinate: coordinate, distance: 50_000))
                }
                locationSearch = name
                withAnimation(.spring()) { dockMode = .idle }
                isLocationSelected = true
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            waterData = loadCSVData()
            if selectedDateID == nil { selectedDateID = waterData.last?.id }
        }
    }
    
    var currentSelectedData: WaterData? {
        waterData.first(where: { $0.id == selectedDateID })
    }

    private func resetToCalifornia() {
        locationSearch = ""
        withAnimation(.easeInOut(duration: 2.0)) {
            position = .camera(MapCamera(centerCoordinate: californiaCenter, distance: californiaZoomLevel))
        }
        isLocationSelected = false
        isTopCardExpanded = false
    }

    // MARK: - CSV Loading
    func loadCSVData() -> [WaterData] {
        guard let url = Bundle.main.url(forResource: "H2O Hackathon Challenge", withExtension: "csv"),
              let rawCSV = try? String(contentsOf: url) else { return [] }
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "M/d/yy"
        let outputFormatter = DateFormatter(); outputFormatter.dateFormat = "MMM ''yy"
        var lines = rawCSV.components(separatedBy: .newlines)
        if lines.first?.lowercased().contains("date") == true { lines.removeFirst() }
        return lines.compactMap { line -> WaterData? in
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 4, let date = dateFormatter.date(from: cols[0]),
                  let snow = Double(cols[1]), let precip = Double(cols[2]), let res = Double(cols[3]) else { return nil }
            return WaterData(dateString: cols[0], monthYear: outputFormatter.string(from: date), snowpack: snow, precip: precip, reservoir: res)
        }.reversed()
    }
}

// MARK: - Dock Components

struct TimelineDockSegment: View {
    @Binding var mode: DockMode
    @Binding var selectedDateID: UUID?
    let data: [WaterData]
    
    var isExpanded: Bool { mode == .timeline }

    var body: some View {
        ZStack {
            if isExpanded {
                VStack(spacing: 0) {
                    Text(data.first(where: { $0.id == selectedDateID })?.monthYear ?? "")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .bottom, spacing: 6) {
                            ForEach(data) { item in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(selectedDateID == item.id ? Color.cyan : Color.white.opacity(0.35))
                                    .frame(width: 4, height: item.normalizedTickHeight)
                                    .id(item.id)
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedDateID = item.id
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $selectedDateID)
                    .contentMargins(.horizontal, 120, for: .scrollContent)
                    .frame(height: 40)
                }
                .transition(.opacity.combined(with: .scale(0.95)))
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: isExpanded ? 280 : 70, height: 60)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                mode = (mode == .timeline) ? .idle : .timeline
            }
        }
    }
}

struct SearchDockSegment: View {
    @Binding var mode: DockMode
    @Binding var locationSearch: String
    var onSearchTap: () -> Void
    var onResetTap: () -> Void
    
    var isExpanded: Bool { mode == .search }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, isExpanded ? 20 : 0)
            
            if isExpanded {
                Text(locationSearch.isEmpty ? "Search California..." : locationSearch)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .onTapGesture { onSearchTap() }
                
                HStack(spacing: 16) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onResetTap()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.spring()) { mode = .idle }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : 70)
        .frame(height: 60)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        )
        .onTapGesture {
            if !isExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    mode = .search
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
