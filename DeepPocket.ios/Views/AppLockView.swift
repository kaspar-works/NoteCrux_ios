import SwiftUI

struct AppLockView: View {
    @Environment(\.colorScheme) private var colorScheme
    let useBiometrics: Bool
    let pinHash: String
    let unlock: () -> Void

    @State private var pin = ""
    @State private var message: String?

    var body: some View {
        ZStack {
            DeepPocketTheme.background(for: colorScheme).ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(.green)

                Text("DeepPocket Locked")
                    .font(.largeTitle.bold())

                Text("Unlock to access your private meeting data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !pinHash.isEmpty {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: 260)

                    Button("Unlock with PIN") {
                        if AppSecurity.validatePIN(pin, storedHash: pinHash) {
                            unlock()
                        } else {
                            message = "Incorrect PIN."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                if useBiometrics {
                    Button("Unlock with Face ID") {
                        Task { await biometricUnlock() }
                    }
                    .buttonStyle(.bordered)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(28)
        }
        .task {
            if useBiometrics {
                await biometricUnlock()
            }
        }
    }

    private func biometricUnlock() async {
        let success = await AppSecurity.unlockWithBiometrics(reason: "Unlock DeepPocket.")
        if success {
            unlock()
        } else if pinHash.isEmpty {
            message = "Biometric unlock failed. Set a PIN in Settings for fallback access."
        }
    }
}
