import SwiftUI
import UniformTypeIdentifiers
import VirtLiteCore

/// The four-step wizard (VM-01).
///
/// Four steps, not five: shared folders are configured afterwards in the inspector. That is the
/// difference between meeting the acceptance criterion and missing it.
struct CreateMachineView: View {
    @Environment(MachineStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let onCreated: (MachineEntry) -> Void

    private enum Step: Int, CaseIterable {
        case guest, image, hardware, name

        var title: String {
            switch self {
            case .guest:    return "System"
            case .image:    return "Image"
            case .hardware: return "Hardware"
            case .name:     return "Name"
            }
        }
    }

    @State private var step: Step = .guest
    @State private var guest: GuestType = .linux
    @State private var isoURL: URL?
    @State private var cpuCount = 4
    @State private var memoryGB = 4.0
    @State private var diskGB = 32.0
    @State private var name = "Linux"
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            steps
            Divider()

            Group {
                switch step {
                case .guest:    guestStep
                case .image:    imageStep
                case .hardware: hardwareStep
                case .name:     nameStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)

            Divider()
            footer
        }
        .frame(width: 540, height: 420)
    }

    // MARK: - Steps

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Text(item.title)
                    .font(.caption)
                    .fontWeight(item == step ? .semibold : .regular)
                    .foregroundStyle(item == step ? .primary : .secondary)

                if item != Step.allCases.last {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var guestStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you installing?").font(.headline)

            Picker("", selection: $guest) {
                Text("Linux").tag(GuestType.linux)
                Text("macOS").tag(GuestType.macOS)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if guest == .macOS {
                Label(
                    "macOS guests are not supported yet. They need an .ipsw restore image and arrive in a later release.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var imageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose an installer image").font(.headline)

            HStack {
                Text(isoURL?.lastPathComponent ?? "No image selected")
                    .foregroundStyle(isoURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…", action: chooseISO)
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))

            Label(
                "The image must be built for ARM64. Apple Silicon cannot run x86_64 systems — Rosetta translates individual binaries inside an ARM guest, not a whole operating system.",
                systemImage: "cpu"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private var hardwareStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hardware").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                // Ranges come from the framework, so they are right for this Mac (HW-01).
                Stepper(
                    "CPU cores: \(cpuCount)",
                    value: $cpuCount,
                    in: store.hardwareLimits.minimumCPUCount...store.hardwareLimits.maximumCPUCount
                )
                Text("This Mac supports \(store.hardwareLimits.minimumCPUCount) to \(store.hardwareLimits.maximumCPUCount).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $memoryGB, in: memoryRange, step: 1) {
                    Text("Memory: \(Int(memoryGB)) GB")
                }
                Text("Leave the host enough to work with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $diskGB, in: 8...256, step: 8) {
                    Text("Disk: \(Int(diskGB)) GB")
                }
                Text("The image is sparse — it only occupies what the guest writes. The size cannot be reduced later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name this machine").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }

            Spacer()

            if step != .guest {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .guest
                }
            }

            if step == .name {
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Next") {
                    step = Step(rawValue: step.rawValue + 1) ?? .name
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
        }
        .padding(16)
    }

    private var canAdvance: Bool {
        switch step {
        case .guest:    return guest == .linux
        case .image:    return isoURL != nil
        case .hardware: return true
        case .name:     return true
        }
    }

    private var memoryRange: ClosedRange<Double> {
        let gigabyte = 1024.0 * 1024.0 * 1024.0
        let minimum = max(1, Double(store.hardwareLimits.minimumMemoryInBytes) / gigabyte)
        let maximum = Double(store.hardwareLimits.maximumMemoryInBytes) / gigabyte
        return minimum...max(minimum + 1, maximum)
    }

    // MARK: - Actions

    private func chooseISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .diskImage]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            isoURL = panel.url
            if let url = panel.url {
                name = suggestedName(from: url)
            }
        }
    }

    /// "ubuntu-24.04.4-live-server-arm64.iso" becomes "Ubuntu" — enough to be recognisable
    /// without making the user type it.
    private func suggestedName(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let firstWord = stem.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        return firstWord.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Linux"
    }

    private func create() {
        let gigabyte = UInt64(1024 * 1024 * 1024)
        do {
            let entry = try store.create(
                name: name,
                cpuCount: cpuCount,
                memoryInBytes: UInt64(memoryGB) * gigabyte,
                diskSizeInBytes: UInt64(diskGB) * gigabyte,
                installerISO: isoURL
            )
            onCreated(entry)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
