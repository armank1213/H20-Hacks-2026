import SwiftUI
import MapKit

struct ContentView: View {
    @State private var selectedDateID: UUID?
    @State private var waterData: [WaterData] = []

    // Map state lifted up from HomeMapView
    @State private var position: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449),
            distance: 4_500_000
        )
    )
    @State private var showingLocationPicker = false
    @State private var locationSearch: String = ""

    private let californiaCenter = CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449)
    private let californiaZoomLevel: Double = 4_500_000

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Black base
            Color.black
                .ignoresSafeArea()

            // 2. Map — masked, knows nothing about controls
            HomeMapView(position: $position)
                .mask(
                    Rectangle()
                        .padding(40)
                        .blur(radius: 40)
                )
                .ignoresSafeArea()

            // 3. Glass control bar — above the mask, below the pill
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: resetToCalifornia) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 50, height: 50)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: locationSearch)

                    Button(action: { showingLocationPicker = true }) {
                        HStack {
                            Image(systemName: "location.magnifyingglass")
                            Text(locationSearch.isEmpty ? "Choose Location" : locationSearch)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sensoryFeedback(.impact(weight: .medium), trigger: showingLocationPicker)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 30)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: -5)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // 4. Timeline Pill — topmost layer
            VStack {
                Spacer()
                TimelinePillView(selectedDateID: $selectedDateID, data: waterData)
                    .padding(.bottom, 130) // Sits above the glass bar
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationSearchView(searchText: $locationSearch) { coordinate, name in
                updateMapPosition(to: coordinate, distance: 50_000)
                locationSearch = name
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            waterData = loadCSVData()
            if selectedDateID == nil {
                selectedDateID = waterData.last?.id
            }
        }
    }

    // MARK: - Map Helpers

    private func updateMapPosition(to coordinate: CLLocationCoordinate2D, distance: Double) {
        withAnimation(.easeInOut(duration: 2.0)) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: distance))
        }
    }

    private func resetToCalifornia() {
        locationSearch = ""
        updateMapPosition(to: californiaCenter, distance: californiaZoomLevel)
    }

    // MARK: - CSV Parser

    func loadCSVData() -> [WaterData] {
        guard let url = Bundle.main.url(forResource: "H2O Hackathon Challenge", withExtension: "csv"),
              let rawCSV = try? String(contentsOf: url) else {
            print("❌ Error: Could not find or read 'H2O Hackathon Challenge.csv'. Ensure Target Membership is checked.")
            return []
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yy"

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM ''yy"

        var lines = rawCSV.components(separatedBy: .newlines)
        if lines.first?.lowercased().contains("date") == true {
            lines.removeFirst()
        }

        let parsedData = lines.compactMap { line -> WaterData? in
            let columns = line.components(separatedBy: ",")
            guard columns.count >= 4,
                  let date = dateFormatter.date(from: columns[0]),
                  let snow = Double(columns[1]),
                  let precip = Double(columns[2]),
                  let res = Double(columns[3]) else { return nil }

            return WaterData(
                dateString: columns[0],
                monthYear: outputFormatter.string(from: date),
                snowpack: snow,
                precip: precip,
                reservoir: res
            )
        }

        return parsedData.reversed()
    }
}

#Preview {
    ContentView()
}
