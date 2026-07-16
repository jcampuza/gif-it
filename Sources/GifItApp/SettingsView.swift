import GifItCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        Button {
          model.requestCapture()
        } label: {
          Label("Capture Window", systemImage: "viewfinder.rectangular")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canCapture)
      }

      Section("Output") {
        Picker(
          "Format",
          selection: Binding(
            get: { model.settings.format },
            set: { value in model.setFormat(value) }
          )
        ) {
          Text("GIF").tag(CaptureFormat.gif)
          Text("MP4").tag(CaptureFormat.mp4)
        }
        .pickerStyle(.segmented)

        if model.settings.format == .gif {
          Picker(
            "GIF quality",
            selection: Binding(
              get: { model.settings.gifQuality },
              set: { value in model.setGIFQuality(value) }
            )
          ) {
            ForEach(GIFQuality.allCases, id: \.self) { quality in
              Text(quality.displayName).tag(quality)
            }
          }
          .help("Higher quality produces smoother, larger GIF files.")

          Text(
            "\(Int(model.settings.gifQuality.framesPerSecond)) fps · "
              + "up to \(Int(model.settings.gifQuality.maximumPixelDimension)) px"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Picker(
          "Destination",
          selection: Binding(
            get: { model.settings.destination },
            set: { value in model.setDestination(value) }
          )
        ) {
          Text("Clipboard").tag(DestinationKind.clipboard)
          Text("Folder").tag(DestinationKind.folder)
        }
        .pickerStyle(.segmented)

        if model.settings.destination == .folder {
          HStack {
            Text(model.settings.folderPath ?? "No folder selected")
              .lineLimit(1)
              .truncationMode(.middle)
              .foregroundStyle(model.settings.folderPath == nil ? Color.secondary : Color.primary)
            Spacer()
            Button("Choose…", action: model.chooseFolder)
            Button("Reveal", action: model.revealDestinationFolder)
              .disabled(model.settings.folderPath == nil)
          }
        }
      }

      Section("Recording") {
        Toggle(
          "Include cursor",
          isOn: Binding(
            get: { model.settings.includesCursor },
            set: { value in model.setIncludesCursor(value) }
          ))
        Toggle(
          "Show mouse click rings",
          isOn: Binding(
            get: { model.settings.showsMouseClicks },
            set: { value in model.setShowsMouseClicks(value) }
          ))
        LabeledContent("Maximum duration", value: "30 seconds")
      }

      Section("Shortcut") {
        HStack {
          Text("Start or stop capture")
          Spacer()
          Button(model.isRecordingShortcut ? "Press keys…" : model.settings.shortcut.displayName) {
            model.beginShortcutRecording()
          }
          .frame(minWidth: 90)
        }
      }

      Section("Permission") {
        HStack {
          Label(
            model.screenRecordingGranted ? "Screen Recording allowed" : "Screen Recording required",
            systemImage: model.screenRecordingGranted
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(model.screenRecordingGranted ? Color.green : Color.orange)
          Spacer()
          Button("Request Access", action: model.requestScreenRecordingAccess)
        }
      }

      Text(model.statusMessage)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 520, height: 540)
  }
}
