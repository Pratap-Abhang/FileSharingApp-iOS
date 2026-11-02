import SwiftUI

/// App entry point: a home screen with Send and Receive.
@main
struct PhotoShareApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Spacer()
                Text("FileSharingApp")
                    .font(.largeTitle.bold())
                Text("Send photos to another phone through the screen and camera. No Wi-Fi, Bluetooth or internet needed.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                Spacer()
                NavigationLink(destination: SendView()) {
                    Label("Send photos", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                NavigationLink(destination: ReceiveView()) {
                    Label("Receive photos", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(24)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}
