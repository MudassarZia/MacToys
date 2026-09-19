import SwiftUI
import AppKit
import Vision
import ScreenCaptureKit
import CoreMedia
import MacToysCore

@MainActor enum Capture {
    static func region() async throws -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacToys-\(UUID().uuidString).png")
        NSApp.hide(nil)
        defer { NSApp.unhide(nil); NSApp.activate(ignoringOtherApps: true) }
        do {
            let result = try await Runner.run("/usr/sbin/screencapture", ["-i", "-r", "-x", "-t", "png", url.path], timeout: 120)
            guard FileManager.default.fileExists(atPath: url.path) else {
                if result.status != 0 && !result.output.isEmpty { throw ToyError.message(result.output) }
                return nil
            }
            return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
}
struct OCRView: View {
    @State private var text = ""
    @State private var message = "Select an area, or open an image. Recognition runs locally using Apple Vision. Escape cancels selection."
    @State private var busy = false
    var body: some View {
        ToolPage(title: "Text Extractor", subtitle: "Copy text from any screen region—even when it is not selectable.") {
            HStack { Button("Capture region…", systemImage: "viewfinder") { Task { await recognize(capture: true) } }.buttonStyle(.borderedProminent); Button("Open image…") { Task { await recognize(capture: false) } }; if busy { ProgressView().controlSize(.small) }; Spacer(); Button("Copy text") { Files.copy(text); message = "Copied." }.disabled(text.isEmpty) }.disabled(busy)
            Editor(text: $text, height: 400)
            Notice(text: message)
        }
    }
    func recognize(capture: Bool) async {
        busy = true; defer { busy = false }
        do {
            guard let url = capture ? try await Capture.region() : Files.choose(types: ["png", "jpg", "jpeg", "heic", "tiff"]).first else { message = "Cancelled."; return }
            defer { if capture { try? FileManager.default.removeItem(at: url) } }
            text = try await Task.detached {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(url: url).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            message = text.isEmpty ? "No text found in this image." : "Recognized \(text.count) characters. Review before copying."
        } catch { message = error.localizedDescription }
    }
}

@MainActor final class MirrorManager: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, NSWindowDelegate {
    static let shared = MirrorManager()
    @Published var active = false
    @Published var message = "Select a window using the macOS sharing picker. The mirror stays above normal windows and does not accept clicks into the source app."
    @Published var left = 0.0
    @Published var top = 0.0
    @Published var width = 100.0
    @Published var height = 100.0
    private var stream: SCStream?
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private let queue = DispatchQueue(label: "app.mactoys.mirror", qos: .userInitiated)
    private let imageContext = CIContext()
    func choose() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration(); configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.MacToys"]
        picker.defaultConfiguration = configuration; picker.remove(self); picker.add(self); picker.isActive = true; picker.present(using: .window)
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) { Task { @MainActor in message = "Selection cancelled." } }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) { Task { @MainActor in message = error.localizedDescription } }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in await self.start(filter) }
    }
    func start(_ filter: SCContentFilter) async {
        await stop()
        SCContentSharingPicker.shared.isActive = true
        do {
            let configuration = SCStreamConfiguration()
            let ratio = min(1, 1920 / max(1, filter.contentRect.width * CGFloat(filter.pointPixelScale)))
            configuration.width = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale) * ratio))
            configuration.height = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale) * ratio))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15); configuration.queueDepth = 3; configuration.showsCursor = false
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            self.stream = stream
            let panel = NSPanel(contentRect: CGRect(x: 160, y: 160, width: 640, height: 400), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "MacToys · Floating Mirror"; panel.level = .floating; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self
            let image = NSImageView(frame: panel.contentView!.bounds); image.imageScaling = .scaleProportionallyUpOrDown; image.autoresizingMask = [.width, .height]; panel.contentView = image
            self.panel = panel; imageView = image; panel.orderFrontRegardless()
            try await stream.startCapture(); active = true; message = "Live mirror running at up to 15 fps. Adjust crop percentages below or close the mirror to stop capture."
        } catch { await stop(); message = error.localizedDescription }
    }
    func stop() async {
        let old = stream; stream = nil; active = false
        try? await old?.stopCapture()
        panel?.delegate = nil; panel?.close(); panel = nil; imageView = nil
        SCContentSharingPicker.shared.isActive = false
        message = "Mirror stopped."
    }
    func windowWillClose(_ notification: Notification) { Task { await stop() } }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) { Task { @MainActor in guard self.stream === stream else { return }; await stop(); message = error.localizedDescription } }
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let buffer = sampleBuffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = imageContext.createCGImage(ci, from: ci.extent) else { return }
        Task { @MainActor in
            guard self.stream === stream, active else { return }
            let x = min(max(left, 0), 99) / 100, y = min(max(top, 0), 99) / 100
            let w = min(max(width / 100, 0.01), 1 - x), h = min(max(height / 100, 0.01), 1 - y)
            let crop = CGRect(x: Double(cg.width) * x, y: Double(cg.height) * y, width: Double(cg.width) * w, height: Double(cg.height) * h).integral
            if let cropped = cg.cropping(to: crop) { imageView?.image = NSImage(cgImage: cropped, size: .zero) }
        }
    }
}
struct MirrorView: View {
    @ObservedObject private var manager = MirrorManager.shared
    var body: some View {
        ToolPage(title: "Floating Mirror", subtitle: "Keep a live window—or just part of it—in view while you work.") {
            HStack { Button("Choose window…", systemImage: "rectangle.on.rectangle") { manager.choose() }.buttonStyle(.borderedProminent); Button("Stop") { Task { await manager.stop() } }.disabled(!manager.active) }
            cropSlider("Left", value: $manager.left, range: 0...95)
            cropSlider("Top", value: $manager.top, range: 0...95)
            cropSlider("Width", value: $manager.width, range: 5...100)
            cropSlider("Height", value: $manager.height, range: 5...100)
            Notice(text: manager.message)
            Notice(text: "Combines the thumbnail idea from Crop And Lock with an always-on-top panel. macOS public APIs cannot elevate or reparent another app’s actual window. Protected content may appear blank. This is a view-only mirror, not an interactive replacement.")
        }
    }
    func cropSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { HStack { Text(title).frame(width: 55, alignment: .leading); Slider(value: value, in: range, step: 1); Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 50) } }
}

struct InkStroke { var points: [CGPoint]; var color: Color }
struct ScreenStudioView: View {
    @State private var image: NSImage?
    @State private var pixels = CGSize.zero
    @State private var strokes: [InkStroke] = []
    @State private var drawing = false
    @State private var zoom = 1.0
    @State private var mode = "Draw"
    @State private var measureStart: CGPoint?
    @State private var measureEnd: CGPoint?
    @State private var message = "Capture an area to annotate or measure it. Escape cancels selection."
    @State private var busy = false
    var body: some View {
        ToolPage(title: "Screen Studio", subtitle: "Freeze a screen region, zoom in, draw, and measure pixel distances.") {
            HStack {
                Button("Capture region…", systemImage: "camera.viewfinder") { capture() }.buttonStyle(.borderedProminent).disabled(busy)
                Picker("Mode", selection: $mode) { Text("Draw").tag("Draw"); Text("Ruler").tag("Ruler") }.pickerStyle(.segmented).frame(width: 160)
                Button("Undo stroke") { if !strokes.isEmpty { strokes.removeLast() } }.disabled(strokes.isEmpty)
                Button("Export PNG…") { export() }.disabled(image == nil)
            }
            if let image {
                HStack { Text("Zoom"); Slider(value: $zoom, in: 0.25...3); Text("\(Int(zoom * 100))%").monospacedDigit(); Text("\(Int(pixels.width)) × \(Int(pixels.height)) px").foregroundStyle(.secondary) }
                ScrollView([.horizontal, .vertical]) {
                    canvas(image: image).frame(width: pixels.width * zoom, height: pixels.height * zoom)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let p = CGPoint(x: value.location.x / zoom, y: value.location.y / zoom)
                            if mode == "Draw" {
                                if !drawing { strokes.append(InkStroke(points: [p], color: .orange)); drawing = true }
                                else { strokes[strokes.count - 1].points.append(p) }
                            } else { measureStart = CGPoint(x: value.startLocation.x / zoom, y: value.startLocation.y / zoom); measureEnd = p }
                        }.onEnded { _ in
                            drawing = false
                            if mode == "Ruler", let a = measureStart, let b = measureEnd { message = "Width \(Int(abs(b.x-a.x))) px · Height \(Int(abs(b.y-a.y))) px · Distance \(Int(hypot(b.x-a.x, b.y-a.y))) px" }
                        })
                }.frame(height: 420).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            } else { ContentUnavailableView("A canvas from your screen", systemImage: "pencil.and.outline", description: Text("Capture a region to get started.")) }
            Notice(text: message)
        }
    }
    func canvas(image: NSImage) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().interpolation(.none)
            Canvas { context, _ in
                for stroke in strokes {
                    var path = Path()
                    for (i, p) in stroke.points.enumerated() { let point = CGPoint(x: p.x * zoom, y: p.y * zoom); if i == 0 { path.move(to: point) } else { path.addLine(to: point) } }
                    context.stroke(path, with: .color(stroke.color), style: StrokeStyle(lineWidth: 3 * zoom, lineCap: .round, lineJoin: .round))
                }
                if let a = measureStart, let b = measureEnd {
                    let rect = CGRect(x: min(a.x, b.x) * zoom, y: min(a.y, b.y) * zoom, width: abs(a.x-b.x) * zoom, height: abs(a.y-b.y) * zoom)
                    context.stroke(Path(rect), with: .color(.cyan), style: StrokeStyle(lineWidth: 1, dash: [5,3]))
                }
            }.allowsHitTesting(false)
        }
    }
    func capture() {
        busy = true
        Task { do { if let url = try await Capture.region() { defer { try? FileManager.default.removeItem(at: url) }; guard let data = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: data) else { throw ToyError.message("Could not decode capture.") }; pixels = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh); image = NSImage(data: data); strokes = []; measureStart = nil; measureEnd = nil; zoom = min(1, 800.0/max(1.0, Double(pixels.width))); message = "Drag to draw or switch to Ruler. Measurements use captured image pixels." } } catch { message = error.localizedDescription }; busy = false }
    }
    func export() {
        guard let image, let url = Files.save(name: "Annotated.png") else { return }
        let oldZoom = zoom; zoom = 1
        let renderer = ImageRenderer(content: canvas(image: image).frame(width: pixels.width, height: pixels.height)); renderer.scale = 1
        defer { zoom = oldZoom }
        guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { message = "Could not render the annotation."; return }
        do { try data.write(to: url, options: .atomic); message = "Exported \(url.lastPathComponent)." } catch { message = error.localizedDescription }
    }
}
