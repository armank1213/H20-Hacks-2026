import SwiftUI

struct DataInsightCard: View {
    @Binding var isExpanded: Bool
    @Binding var selectedPersona: String
    let currentData: WaterData?
    let locationName: String

    let personas = [
        (name: "Manager", icon: "building.2.fill"),
        (name: "Farmer", icon: "leaf.fill"),
        (name: "Citizen", icon: "person.fill")
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let data = currentData {
                // MARK: - Header (The "Handle")
                headerView(data: data)
                
                if isExpanded {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            
                            // MARK: - Persona Segmented Picker
                            personaPicker
                            
                            // MARK: - Awareness Grid
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("Current Awareness", icon: "eye.fill")
                                HStack(spacing: 12) {
                                    MetricTile(title: "Snowpack", value: "\(Int(data.snowpack))%", status: data.snowpackStatus.description, color: data.snowpackStatus.color, icon: "snowflake")
                                    MetricTile(title: "Precip", value: "\(Int(data.precip))%", status: data.precipitationStatus.description, color: data.precipitationStatus.color, icon: "cloud.rain.fill")
                                    MetricTile(title: "Reservoir", value: "\(Int(data.reservoir))%", status: data.reservoirStatus.description, color: data.reservoirStatus.color, icon: "drop.fill")
                                }
                            }
                            .padding(.horizontal, 20)

                            // MARK: - Predictive Outlook
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("Predictive Outlook", icon: "sparkles")
                                PredictiveListView(data: data, persona: selectedPersona)
                            }
                            .padding(.horizontal, 20)

                            // MARK: - Warnings/Alerts
                            if hasActiveAlerts(data) {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("Active Alerts", icon: "exclamationmark.triangle.fill", color: .orange)
                                    AlertCard(data: data)
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            Spacer(minLength: 40)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 36 : 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 36 : 30, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .padding(.horizontal, isExpanded ? 12 : 20)
        .frame(maxHeight: isExpanded ? 640 : 74) // Control expansion height
    }

    // MARK: - Subviews
    
    private func headerView(data: WaterData) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(locationName.isEmpty ? "Location Insights" : locationName)
                    .font(.system(.headline, design: .rounded)).fontWeight(.bold)
                Text(data.monthYear)
                    .font(.system(.caption, design: .rounded)).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary, .white.opacity(0.1))
        }
        .padding(.horizontal, 24)
        .frame(height: 74)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private var personaPicker: some View {
        HStack(spacing: 0) {
            ForEach(personas, id: \.name) { p in
                let isSelected = selectedPersona == p.name
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedPersona = p.name }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: p.icon)
                        Text(p.name).font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
                    .cornerRadius(12)
                    .foregroundColor(isSelected ? .cyan : .secondary)
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.2))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ text: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text.uppercased()).font(.system(size: 11, weight: .heavy))
        }
        .foregroundColor(color)
    }
    
    private func hasActiveAlerts(_ data: WaterData) -> Bool {
        data.snowpackStatus == .concerning || data.reservoirStatus == .concern
    }
}

// MARK: - Helper UI Components

struct MetricTile: View {
    let title: String, value: String, status: String, color: Color, icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundColor(color).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(title).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(18)
    }
}

struct PredictiveListView: View {
    let data: WaterData
    let persona: String
    var body: some View {
        VStack(spacing: 1) { // Divider effect
            PredictiveRow(title: "Snowpack Outlook", text: "Immediate action on water conservation is crucial.", color: data.snowpackStatus.color)
            PredictiveRow(title: "Precipitation Trend", text: "Normal rainfall. No immediate concerns.", color: data.precipitationStatus.color)
            PredictiveRow(title: "Reservoir Stability", text: "Water supply remains stable for now.", color: data.reservoirStatus.color)
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }
}

struct PredictiveRow: View {
    let title: String, text: String, color: Color
    var body: some View {
        HStack(spacing: 15) {
            Circle().fill(color.opacity(0.2)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(text).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlertCard: View {
    let data: WaterData
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").foregroundColor(.orange).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Required").font(.system(size: 14, weight: .bold)).foregroundColor(.orange)
                Text("Snowpack levels are critically low. Mandatory rationing may be implemented.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .cornerRadius(20)
    }
}
