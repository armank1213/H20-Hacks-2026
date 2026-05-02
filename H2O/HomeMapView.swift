import SwiftUI
import MapKit

// MARK: - Recent Location Model

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

// MARK: - Home Map View

struct HomeMapView: View {
    @Binding var position: MapCameraPosition

    // Restrict panning to a region that covers California with some breathing room
    @State private var mapBounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449),
            span: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 14.0)
        ),
        minimumDistance: 1_000,
        maximumDistance: 6_000_000
    )

    var body: some View {
        Map(position: $position, bounds: mapBounds)
            .mapStyle(.hybrid(elevation: .realistic))
            .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Location Search View

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
                                Text("No recent searches")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(recentPlaces) { place in
                                    Button {
                                        onLocationSelected(place.coordinate, place.name)
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .foregroundColor(.secondary)
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

// MARK: - Preview

#Preview {
    HomeMapView(position: .constant(.camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.166, longitude: -119.449),
            distance: 4_500_000
        )
    )))
}
