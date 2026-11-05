import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
@preconcurrency import AVFoundation

struct BluetoothView: View {
    @ObservedObject var bluetooth: BluetoothStore
    @ObservedObject var location: LocationStore
    var showOnMap: ((Bool) -> Void)? = nil
    @AppStorage("bluetoothDisplayName") private var name = "My phone"
    @State private var scanning = false
    @State private var forget = false

    private var qrImage: UIImage? {
        guard let url = bluetooth.pairingURL else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by:CGAffineTransform(scaleX:7,y:7)),
              let image = CIContext().createCGImage(output,from:output.extent) else { return nil }
        return UIImage(cgImage:image)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(bluetooth.connected ? "Connected to \(bluetooth.peerName)" : bluetooth.paired ? "Reconnecting to \(bluetooth.peerName)…" : "Connect with your person",
                          systemImage:bluetooth.connected ? "checkmark.circle.fill" : "person.2.fill").font(.headline)
                    Text(bluetooth.status).font(.subheadline)
                    Text(bluetooth.connectionStep).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your name") {
                    TextField("Your name",text:$name).textContentType(.givenName).textInputAutocapitalization(.words)
                }
                if let incoming = bluetooth.incomingName {
                    Section("Invitation") {
                        Text("\(incoming) wants to connect with you.").font(.headline)
                        Button("Accept invitation") { bluetooth.acceptInvitation() }.buttonStyle(.borderedProminent)
                        Button("Decline",role:.destructive) { bluetooth.declineInvitation() }
                        Text("Location sharing stays off until you turn it on.").font(.caption)
                    }
                }
                if !bluetooth.paired {
                    Section(bluetooth.awaitingApproval ? "Invitation sent" : "Your QR") {
                        if bluetooth.awaitingApproval {
                            ProgressView("Waiting for \(bluetooth.peerName) to accept…")
                            Text("Keep both phones nearby with Bluetooth on and both apps open.").font(.footnote)
                            Button("Cancel invitation") { bluetooth.forget(); bluetooth.prepareInvitation(name:name) }
                        } else {
                            if let image = qrImage {
                                Image(uiImage:image).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth:260).padding(12).background(.white)
                                    .frame(maxWidth:.infinity).accessibilityLabel("Your private pairing QR")
                            }
                            Text("One person scans the other’s QR. The other person taps Accept. That’s it.").font(.subheadline)
                            Button { scanning = true } label: { Label("Scan their QR",systemImage:"qrcode.viewfinder") }
                                .buttonStyle(.borderedProminent)
                                .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || bluetooth.incomingName != nil)
                            Text("Only show this private QR to the person you want to connect with.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Location sharing") {
                        Toggle("Share my location",isOn:Binding(get:{bluetooth.sharing},set:{ value in
                            if value && !bluetooth.active { bluetooth.start() }
                            bluetooth.setSharing(value)
                        }))
                        Text("When enabled, fresh locations send automatically while your phones can communicate over Bluetooth. Turn this off to stop sending.").font(.footnote)
                        if !bluetooth.active { Button("Reconnect") { bluetooth.start() } }
                        if let fix = location.fix {
                            Text("My GPS: \(fix.timestamp.formatted(date:.omitted,time:.standard)) • ±\(Int(fix.horizontalAccuracy)) m").font(.caption)
                        }
                        if let sent = bluetooth.lastSentAt {
                            Text("Last sent to Bluetooth: \(sent.formatted(date:.omitted,time:.standard))").font(.caption)
                        }
                        DisclosureGroup("Background sharing") {
                            Text(location.backgroundPermission).font(.footnote)
                            Button("Allow background location") { location.requestBackgroundAccess() }
                            Button("Open Settings → Location → Always") { location.openLocationSettings() }
                            Text("Set location access to Always with Precise Location on. iOS may delay or stop background updates. Force-closing the app stops them. Pairing is remembered and reconnects when the apps can run and the phones are nearby.").font(.footnote)
                        }
                        Button("Disconnect this person",role:.destructive) { forget = true }
                    }
                }
                if let packet = bluetooth.received, let at = bluetooth.receivedAt {
                    Section("\(bluetooth.peerName)’s last location") {
                        Text(packet.coordinates).font(.headline.monospaced()).textSelection(.enabled)
                        if let showOnMap {
                            Button("Show on map") { showOnMap(false) }
                            Button("Walking directions") { showOnMap(true) }
                        }
                        Text("GPS: \(packet.recordedAt.formatted(date:.abbreviated,time:.standard))")
                        Text("Received: \(at.formatted(date:.abbreviated,time:.standard))")
                        Text("Accuracy ±\(Int(packet.accuracy)) m. This is the last received reading, which may be old.").font(.footnote)
                    }
                }
            }.navigationTitle("People")
                .onAppear { bluetooth.prepareInvitation(name:name); location.refreshBackgroundPermission() }
                .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)) { _ in location.refreshBackgroundPermission() }
                .onChange(of:name) { _, value in bluetooth.prepareInvitation(name:value) }
                .fullScreenCover(isPresented:$scanning) {
                    NavigationStack {
                        PairQRScanner { url in
                            scanning = false
                            bluetooth.prepareInvitation(name:name)
                            bluetooth.receivePairingLink(url)
                        }.ignoresSafeArea(edges:.bottom)
                            .navigationTitle("Scan their QR")
                            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { scanning = false } } }
                    }
                }
                .confirmationDialog("Disconnect this person?",isPresented:$forget,titleVisibility:.visible) {
                    Button("Disconnect",role:.destructive) { bluetooth.forget(); bluetooth.prepareInvitation(name:name) }
                } message: { Text("Stops sharing and removes this pairing from this phone.") }
        }
    }
}

private struct PairQRScanner: UIViewControllerRepresentable {
    let onScan: (URL) -> Void
    func makeUIViewController(context: Context) -> PairQRScannerController { PairQRScannerController(onScan:onScan) }
    func updateUIViewController(_ controller: PairQRScannerController, context: Context) { }
}

private final class PairQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label:"offlinecompanion.qr.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var visible = false
    private var configured = false
    private var finished = false
    private let onScan: (URL) -> Void
    private let message = UILabel()
    init(onScan: @escaping (URL) -> Void) { self.onScan = onScan; super.init(nibName:nil,bundle:nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        message.text = "Point the camera at the other phone’s QR."
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(message)
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:24),
            message.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-24),
            message.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-24)])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); visible = true
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.visible else { return }
                    if allowed { self.configure() } else { self.message.text = "Allow Camera in iPhone Settings > Apps > Offline Companion to scan a QR." }
                }
            }
        default: message.text = "Allow Camera in iPhone Settings > Apps > Offline Companion to scan a QR."
        }
    }
    private func configure() {
        guard !configured, visible else { return }
        guard let device = AVCaptureDevice.default(for:.video), let input = try? AVCaptureDeviceInput(device:device), session.canAddInput(input) else {
            message.text = "Camera unavailable. Close other camera apps and try again."; return
        }
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration(); session.addInput(input)
        guard session.canAddOutput(output) else { session.commitConfiguration(); message.text = "QR scanning unavailable."; return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self,queue:.main); output.metadataObjectTypes = [.qr]
        session.commitConfiguration(); configured = true
        let layer = AVCaptureVideoPreviewLayer(session:session); layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer,at:0); preview = layer; layer.frame = view.bounds
        sessionQueue.async { [session] in session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); visible = false
        sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects:[AVMetadataObject], from connection:AVCaptureConnection) {
        guard visible, !finished else { return }
        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject, let text = code.stringValue,
                  let url = URL(string:text), url.scheme == "offlinecompanion", url.host == "pair" else { continue }
            finished = true; onScan(url); return
        }
    }
}

struct BluetoothSharingBanner: View {
    @ObservedObject var bluetooth: BluetoothStore
    var body: some View {
        if bluetooth.sharing {
            HStack {
                Label(bluetooth.connected ? "Location sharing on" : "Sharing on • waiting for nearby link",systemImage:"location.fill").font(.caption)
                Spacer()
                Button("Stop sharing") { bluetooth.setSharing(false) }.font(.caption.bold())
            }.padding(10).background(Color.orange.opacity(0.15))
        }
    }
}
