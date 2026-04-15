import SwiftUI

struct NativeRootView: View {
    @State private var selectedRole: UserRole = .employer
    @State private var isSignedIn = false
    @State private var email = ""
    @State private var fullName = ""
    @State private var showingNotifications = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [PassportTheme.background, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isSignedIn {
                    signedInView
                } else {
                    onboardingView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingNotifications) {
                NotificationsSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var onboardingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Passport")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(PassportTheme.textPrimary)

                Text("A native iOS shell for the short-form recruiting app.")
                    .font(.headline)
                    .foregroundStyle(PassportTheme.textSecondary)

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Full name", text: $fullName)
                        .textFieldStyle(PassportTextFieldStyle())

                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(PassportTextFieldStyle())

                    Picker("Role", selection: $selectedRole) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(20)
                .background(PassportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PassportTheme.border, lineWidth: 1)
                )

                Button {
                    isSignedIn = true
                } label: {
                    Text("Enter native iOS app")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PassportTheme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                configCard
            }
            .padding(24)
        }
    }

    private var signedInView: some View {
        Group {
            if selectedRole == .employer {
                EmployerHomeView(
                    fullName: fullName.isEmpty ? "Hiring Manager" : fullName,
                    onShowNotifications: { showingNotifications = true },
                    onSignOut: { isSignedIn = false }
                )
            } else {
                JobSeekerHomeView(
                    fullName: fullName.isEmpty ? "Candidate" : fullName,
                    onShowNotifications: { showingNotifications = true },
                    onSignOut: { isSignedIn = false }
                )
            }
        }
    }

    private var configCard: some View {
        let config = PassportConfig.load()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Backend wiring")
                .font(.headline)
                .foregroundStyle(PassportTheme.textPrimary)

            Text("This native app is scaffolded with local state so it runs immediately in Xcode. Supabase values can be added later in target build settings.")
                .foregroundStyle(PassportTheme.textSecondary)

            Text("SUPABASE_URL: \(config.supabaseURL)")
                .font(.footnote.monospaced())
                .foregroundStyle(PassportTheme.textSecondary)

            Text("SUPABASE_ANON_KEY: \(config.supabaseAnonKey)")
                .font(.footnote.monospaced())
                .foregroundStyle(PassportTheme.textSecondary)
        }
        .padding(20)
        .background(PassportTheme.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PassportTheme.border, lineWidth: 1)
        )
    }
}

struct PassportTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(PassportTheme.card)
            .foregroundStyle(PassportTheme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NotificationsSheet: View {
    var body: some View {
        NavigationStack {
            List(DemoData.notifications) { notification in
                VStack(alignment: .leading, spacing: 6) {
                    Text(notification.title)
                        .font(.headline)
                    Text(notification.body)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(PassportTheme.background)
            .navigationTitle("Notifications")
        }
    }
}

#Preview {
    NativeRootView()
}
