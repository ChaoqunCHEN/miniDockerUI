import SwiftUI

struct ContentView: View {
    @Binding var status: String

    var body: some View {
        NavigationSplitView {
            List {
                Section("Containers") {
                    Label("No containers yet", systemImage: "shippingbox")
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text("miniDockerUI")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(status)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
        }
    }
}
