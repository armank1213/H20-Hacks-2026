import SwiftUI
import MapKit

// 1. Simple model to store recent locations in AppStorage
struct RecentLocation: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let title: String
    let latitude: Double
    let longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct HomeMapView: View {
    let californiaCenter = CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449)
    let californiaZoomLevel: Double = 4_500_000
    
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449), distance: 4_500_000)
    )
    
    @State private var mapBounds = MapCameraBounds(
        minimumDistance: 1_000,
        maximumDistance: 6_000_000
    )
    
    @State private var showingLocationPicker = false
    @State private var locationSearch: String = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Hybrid Map Layer
            Map(position: $position, bounds: mapBounds)
                .mapStyle(.hybrid(elevation: .realistic))
                .edgesIgnoringSafeArea(.all)
            
            // 2. Glass UI Bottom Overlay
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Reset Button (Returns to CA view)
                    Button(action: resetToCalifornia) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(width: 50, height: 50)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(12)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: locationSearch)

                    // Choose Location Button
                    Button(action: {
                        showingLocationPicker = true
                    }) {
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 30) // Bottom safe area padding
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: -5)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationSearchView(searchText: $locationSearch) { coordinate, name in
                updateMapPosition(to: coordinate, distance: 50_000)
                locationSearch = name
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func updateMapPosition(to coordinate: CLLocationCoordinate2D, distance: Double) {
        withAnimation(.easeInOut(duration: 2.0)) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: distance))
        }
    }

    private func resetToCalifornia() {
        locationSearch = ""
        updateMapPosition(to: californiaCenter, distance: californiaZoomLevel)
    }
}

// MARK: - Search View Component
struct LocationSearchView: View {
    @Binding var searchText: String
    @Environment(\.dismiss) var dismiss
    var onLocationSelected: (CLLocationCoordinate2D, String) -> Void
    
    @State private var searchResults: [MKMapItem] = []
    
    @AppStorage("recent_places_data") private var recentPlacesData: Data = Data()
    
    private var recentPlaces: [RecentLocation] {
        get {
            (try? JSONDecoder().decode([RecentLocation].self, from: recentPlacesData)) ?? []
        }
        nonmutating set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                recentPlacesData = encoded
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Zipcode, City, or Address", text: $searchText)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _ in
                        performSearch()
                    }
                
                List {
                    if !searchText.isEmpty {
                        Section("Search Results") {
                            ForEach(searchResults, id: \.self) { item in
                                Button {
                                    saveToRecents(item)
                                    onLocationSelected(item.placemark.coordinate, item.name ?? "Selected Location")
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(item.name ?? "Unknown Location").font(.headline)
                                        Text(item.placemark.title ?? "").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Section {
                            if recentPlaces.isEmpty {
                                Text("No recent searches").foregroundColor(.secondary).font(.subheadline)
                            } else {
                                ForEach(recentPlaces) { place in
                                    Button {
                                        onLocationSelected(place.coordinate, place.name)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                                            VStack(alignment: .leading) {
                                                Text(place.name).font(.headline)
                                                Text(place.title).font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .onDelete(perform: deleteRecent)
                            }
                        } header: {
                            Text("Recently Viewed")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let response = response else { return }
            self.searchResults = response.mapItems
        }
    }
    
    private func saveToRecents(_ item: MKMapItem) {
        let newPlace = RecentLocation(
            name: item.name ?? "Unknown",
            title: item.placemark.title ?? "",
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        
        var current = recentPlaces
        current.removeAll { $0.name == newPlace.name && $0.title == newPlace.title }
        current.insert(newPlace, at: 0)
        if current.count > 5 { current.removeLast() }
        
        recentPlaces = current
    }
    
    private func deleteRecent(at offsets: IndexSet) {
        var current = recentPlaces
        current.remove(atOffsets: offsets)
        recentPlaces = current
    }
}

#Preview {
    HomeMapView()
}
