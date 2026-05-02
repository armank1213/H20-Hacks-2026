import SwiftUI

struct TimelinePillView: View {
    @Binding var selectedDateID: UUID?
    let data: [WaterData]

    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var selectedItem: WaterData?

    var body: some View {
        ZStack {
            // 1. Liquid Glass Background
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .clear, .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

            // 2. Scrollable Timeline
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(data) { item in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selectedDateID == item.id ? Color.white : Color.gray.opacity(0.5))
                                .frame(width: 3, height: item.normalizedTickHeight)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedDateID)
                // Fix: contentMargins correctly reserves space around the center label
                .contentMargins(.horizontal, 120, for: .scrollContent)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.2),
                            .init(color: .black, location: 0.8),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }

            // 3. Center Target Line / Text Readout
            // Fix: Placed last in ZStack so it draws above the ScrollView
            ZStack {
                Capsule()
                    .fill(.regularMaterial)
                    .frame(width: 80, height: 36)
                    .opacity(isExpanded ? 1 : 0)

                Text(selectedItem?.monthYear ?? "Loading")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    // Fix: Text always visible; scale grows in on expand (was inverted before)
                    .scaleEffect(isExpanded ? 1.0 : 0.85)
            }
        }
        .frame(width: isExpanded ? 320 : 140, height: 60)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isExpanded)

        // MARK: Interactions
        .onLongPressGesture(minimumDuration: 0.2) {
            withAnimation {
                isExpanded = true
                resetCollapseTimer()
            }
        }
        .onChange(of: selectedDateID) { _, newID in
            if let newID, let item = data.first(where: { $0.id == newID }) {
                selectedItem = item
            }
            if isExpanded { resetCollapseTimer() }
        }
        .onChange(of: data) { _, newData in
            if let id = selectedDateID, let item = newData.first(where: { $0.id == id }) {
                selectedItem = item
            }
        }
        // Fix: Cancel the timer when the view disappears to avoid animating a dead view
        .onDisappear {
            collapseTask?.cancel()
        }
    }

    // Auto-collapses the pill after 2.5 seconds of inactivity
    private func resetCollapseTimer() {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                withAnimation { isExpanded = false }
            }
        }
    }
}
