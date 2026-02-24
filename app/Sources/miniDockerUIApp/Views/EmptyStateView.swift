import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Container",
            systemImage: "shippingbox",
            description: Text("Choose a container from the sidebar to view details and logs.")
        )
    }
}
