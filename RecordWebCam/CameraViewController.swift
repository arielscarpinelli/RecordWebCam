/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's primary view controller that presents the camera interface.
*/

import UIKit
import AVFoundation
import Photos
import VideoToolbox

class CameraViewController: UIViewController { // AVCaptureFileOutputRecordingDelegate
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
	
    private var connection: TCPConnection = .init()
    
    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ipAddress.text = getBestIpAddress()
        
        // Disable the UI. Enable the UI later, if and only if the session starts running.
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        
        // Set up the video preview view.
        previewView.session = session
		
        /*
         Check the video authorization status. Video access is required and audio
         access is optional. If the user denies audio access, AVCam won't
         record audio during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
        }
        do {
            try connection.start()
        } catch {
            self.showErrorAndStopRecording("unknown error initializing connection \(error)")
        }

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
        
        connection.accept()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        connection.close()
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        return !isRecording
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        if session.canSetSessionPreset(.hd4K3840x2160) == true {
            session.sessionPreset = .hd4K3840x2160
        } else {
            session.sessionPreset = .high
        }
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear dual wide camera.
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual wide camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            // Configure for 60fps if supported
            if videoDevice.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 60 }) {
                do {
                    try videoDevice.lockForConfiguration()
                    videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                    videoDevice.unlockForConfiguration()
                } catch {
                    print("Failed to configure camera for 60fps: \(error)")
                }
            }

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                     You can manipulate UIView only on the main thread.
                     Note: As an exception to the above rule, it's not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the window scene's orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }

        // Output
        // let movieFileOutput = AVCaptureMovieFileOutput()
        
        let videoOutput = AVCaptureVideoDataOutput()

        // videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
//        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        let videoQueue = DispatchQueue(label: "videoQueue")
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        
        if self.session.canAddOutput(videoOutput) {
            self.session.beginConfiguration()
            self.session.addOutput(videoOutput)

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.session.commitConfiguration()
            
            self.videoOutput = videoOutput
            
            setupVideoToolboxEncoder()

            DispatchQueue.main.async {
                self.recordButton.isEnabled = true
            }
        }

        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running, for example, if a phone or FaceTime call is still
             using audio or video. This failure is communicated by the session posting a
             runtime error notification. To avoid repeatedly failing to start the session,
             only try to restart the session in the error handler if you aren't
             trying to resume the session.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    // MARK: Device Configuration
    
    @IBOutlet private weak var ipAddress: UILabel!

    @IBOutlet private weak var cameraButton: UIButton!
    
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera],
                                                                               mediaType: .video, position: .unspecified)

    /// - Tag: ChangeCamera
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        cameraButton.isEnabled = false
        recordButton.isEnabled = false
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position

            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                                                                                   mediaType: .video, position: .back)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                                                                                    mediaType: .video, position: .front)
            var newVideoDevice: AVCaptureDevice? = nil
            
            switch currentPosition {
            case .unspecified, .front:
                newVideoDevice = backVideoDeviceDiscoverySession.devices.first
                
            case .back:
                newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
                
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.videoOutput?.connection(with: .video) {
                        if self.session.canSetSessionPreset(.hd4K3840x2160) == true {
                            self.session.sessionPreset = .hd4K3840x2160
                        } else {
                            self.session.sessionPreset = .high
                        }
                    }

                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.cameraButton.isEnabled = true
                self.recordButton.isEnabled = self.videoOutput != nil
            }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }

    // MARK: Recording Movies
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet private weak var recordButton: UIButton!
    
    @IBOutlet private weak var resumeButton: UIButton!
    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isEnabled = isSessionRunning && self.videoOutput != nil
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleSystemPressure
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios you want to enable the user to resume the session.
         For example, if music playback is initiated from Control Center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in Control Center will not automatically resume the session.
         Also note that it's not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                // Fade-in a button to enable the user to try to resume the session running.
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
        connection.close()
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
        connection.accept()
    }

    // MARK: - Properties
    private var isRecording: Bool = false
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var recordingStartTime: CMTime?
    private var recordingStopTime: CMTime?
    private var currentFileURL: URL?

    // VideoToolbox encoder
    private var compressionSession: VTCompressionSession?
    private var encodedDataCallback: VTCompressionOutputCallback?



    // MARK: - Video Recording
    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {

        cameraButton.isEnabled = false
        recordButton.isEnabled = false

        sessionQueue.async { [self] in
            
            if (isRecording) {
                stopRecording()
            } else {
                startRecording()
            }
        }

    }
    

    private func startRecording() {
        // Create a unique file URL
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] // NSTemporaryDirectory()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let fileName = "video_\(dateString).mov"
        let url = URL(fileURLWithPath: documentsPath).appendingPathComponent(fileName)

        currentFileURL = url
        
        do {
            // Create asset writer
            videoWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            if videoWriter?.canAdd(videoWriterInput!) == true {
                videoWriter?.add(videoWriterInput!)
            }
            
            recordingStartTime = nil
            recordingStopTime = nil
            
            // Start writing session
            if (!(videoWriter?.startWriting() ?? false)) {
                print("Failed to start recording: \(String(describing: videoWriter?.error))")
            }
            videoWriter?.startSession(atSourceTime: CMTime.zero)
            
            isRecording = true

            DispatchQueue.main.async {
                self.recordButton.isEnabled = true
                self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
            }

        } catch {
            showErrorAndStopRecording("Failed to start recording: \(error)")
            self.recordButton.isEnabled = true
        }
    }

    private func stopRecording() {
        
        isRecording = false
        DispatchQueue.main.async {
            self.recordButton.isEnabled = false
        }
        
        sessionQueue.async { [self] in
            if recordingStopTime != nil {
                VTCompressionSessionCompleteFrames(compressionSession!, untilPresentationTimeStamp: recordingStopTime!)
            }
            videoWriterInput?.markAsFinished()
            videoWriter?.finishWriting { [weak self] in
                guard let self = self, let url = self.currentFileURL else { return }

                // Save to camera roll
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        PHPhotoLibrary.shared().performChanges({
                            let options = PHAssetResourceCreationOptions()
                            options.shouldMoveFile = true
                            let creationRequest = PHAssetCreationRequest.forAsset()
                            creationRequest.addResource(with: .video, fileURL: url, options: options)
                        }) { success, error in
                            if success {
                                print("Video saved to camera roll")
                            } else if let error = error {
                                self.showErrorAndStopRecording("Error saving video: \(error). You can still check it in the Files app")
                            }
                            DispatchQueue.main.async {
                                // Only enable the ability to change camera if the device has more than one camera.
                                self.cameraButton.isEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                                self.recordButton.isEnabled = true
                                self.recordButton.setImage(#imageLiteral(resourceName: "CaptureVideo"), for: [])
                            }

                        }
                    }
                }
            }
            
            videoWriter = nil
            videoWriterInput = nil
        }

    }

    // MARK: - VideoToolbox Encoder Setup
    private func setupVideoToolboxEncoder() {
        // Create compression session
        var session: VTCompressionSession?
        
        // Create callback for encoded frames
        encodedDataCallback = { outputCallbackRefCon, sourceFrameRefCon, status, flags, sampleBuffer in
            guard let sampleBuffer = sampleBuffer else { return }
            
            let selfPointer = Unmanaged<CameraViewController>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
            selfPointer.handleEncodedFrame(sampleBuffer: sampleBuffer)
        }
        
        // Create encoder session (4K resolution)
        let width = 3840
        let height = 2160
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodedDataCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        if status != noErr {
            print("Failed to create VideoToolbox session: \(status)")
            return
        }
        
        compressionSession = session
        
        // Configure encoder properties
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 60))
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 60))
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1))
        
        // Prepare for encoding
        VTCompressionSessionPrepareToEncodeFrames(compressionSession!)
    }

    private func teardownVideoToolboxEncoder() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }

    private func handleEncodedFrame(sampleBuffer: CMSampleBuffer) {
        // Use the encoded frame for both recording and streaming
        connection.append(sampleBuffer)

        if isRecording {
            appendSampleBufferToRecording(sampleBuffer)
        }
        
    }

    private func appendSampleBufferToRecording(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, let writer = videoWriter, let input = videoWriterInput, writer.status == .writing else {
            if (videoWriter?.status == .failed) {
                showErrorAndStopRecording("\(videoWriter!.error!)")
            }
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if recordingStartTime == nil {
            recordingStartTime = timestamp
        }
        recordingStopTime = timestamp

        if input.isReadyForMoreMediaData {
            print("saving frame")
            
            let adjustedTime = CMTimeSubtract(timestamp, recordingStartTime ?? CMTime.zero)

            var timingInfo = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: adjustedTime, decodeTimeStamp: .invalid)

            var adjustedSampleBuffer: CMSampleBuffer?
            
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleBufferOut: &adjustedSampleBuffer
            )
            
            if adjustedSampleBuffer == nil {
                showErrorAndStopRecording("failed to adjust frame timing")
                return
            }

            // For H.264 encoded data, we can just append the sample buffer directly
            if !input.append(adjustedSampleBuffer!) {
                print("error adding frame")
            }
        } else {
            print("skipping frame")
        }
    }

    private func showErrorAndStopRecording(_ message:String) {
        print(message)
        
        if (isRecording) {
            stopRecording();
        }

        DispatchQueue.main.async {
            
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: UIAlertController.Style.alert)
            
            // add an action (button)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
            
            // show the alert
            self.present(alert, animated: true, completion: nil)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if !isRecording && !self.connection.isConnected {
            return
        }

        guard let compressionSession = compressionSession,
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}
