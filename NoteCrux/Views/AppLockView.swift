import SwiftUI

struct AppLockView: View {
    let useBiometrics: Bool
    let pinHash: String
    let unlock: () -> Void

    @State private var pin = ""
    @State private var message: String?

    var body: some View {
        ZStack {
            Color.ncBackground.ignoresSafeArea()

            VStack(spacing: NCSpacing.xxl) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Color.ncPurple)

                Text("NoteCrux Locked")
                    .font(.ncLargeTitle)

                Text("Unlock to access your private meeting data.")
                    .font(.ncBody)
                    .foregroundStyle(Color.ncMuted)
                    .multilineTextAlignment(.center)

                if !pinHash.isEmpty {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(NCSpacing.md)
                        .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: NCRadius.small))
                        .frame(maxWidth: 260)

                    Button("Unlock with PIN") {
                        if AppSecurity.validatePIN(pin, storedHash: pinHash) {
                            unlock()
                        } else {
                            message = "Incorrect PIN."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ncPurple)
                }

                if useBiometrics {
                    Button("Unlock with Face ID") {
                        Task { await biometricUnlock() }
                    }
                    .buttonStyle(.bordered)
                }

                if let message {
                    Text(message)
                        .font(.ncCaption1)
                        .foregroundStyle(Color.ncDanger)
                }
            }
            .padding(NCSpacing.xxxl)
        }
        .task {
            if useBiometrics {
                await biometricUnlock()
            }
        }
    }

    private func biometricUnlock() async {
        let success = await AppSecurity.unlockWithBiometrics(reason: "Unlock NoteCrux.")
        if success {
            unlock()
        } else if pinHash.isEmpty {
            message = "Biometric unlock failed. Set a PIN in Settings for fallback access."
        }
    }
}
