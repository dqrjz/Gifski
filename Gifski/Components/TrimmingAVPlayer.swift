import AVKit
import SwiftUI

struct TrimmingAVPlayer: NSViewControllerRepresentable {
	struct TimeRangeRequest: Equatable {
		var id = UUID()
		let range: ClosedRange<Double>
	}

	typealias NSViewControllerType = TrimmingAVPlayerViewController

	@Environment(\.colorScheme) private var colorScheme

	let asset: AVAsset
	let shouldShowPreview: Bool
	let fullPreviewState: FullPreviewGenerationEvent
	var controlsStyle = AVPlayerViewControlsStyle.inline
	var loopPlayback = false
	var bouncePlayback = false
	var speed = 1.0
	var overlay: NSView?
	var isPlayPauseButtonEnabled = true
	var isTimelineEnabled = true
	var requestedTimeRange: TimeRangeRequest?
	var timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	func makeNSViewController(context: Context) -> NSViewControllerType {
		.init(
			playerItem: .init(asset: asset),
			controlsStyle: controlsStyle,
			timeRangeDidChange: timeRangeDidChange
		)
	}

	func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
		nsViewController.receiveTimeRangeRequest(requestedTimeRange)

		if asset != nsViewController.currentItem.asset {
			let item = AVPlayerItem(asset: asset)
			forceAVPlayerToRedraw(item: item)
			item.playbackRange = nsViewController.currentItem.playbackRange
			nsViewController.currentItem = item
		}

		// Always update video composition based on preview state.
		// When preview is ON, use custom compositor. When OFF, clear it so AVPlayer handles rotation.
		let currentItem = nsViewController.currentItem
		if
			currentItem.videoComposition == nil,
			shouldShowPreview,
			fullPreviewState.canShowPreview
		{
			forceAVPlayerToRedraw(item: currentItem)
		}

		let didUpdatePreviewState = updatePreviewState(nsViewController)
		forceAVPlayerToRedraw(item: currentItem, forceRedraw: didUpdatePreviewState)

		nsViewController.loopPlayback = loopPlayback
		nsViewController.bouncePlayback = bouncePlayback
		nsViewController.player.defaultRate = Float(speed)
		if nsViewController.player.rate != 0 {
			nsViewController.player.rate = nsViewController.player.rate > 0 ? Float(speed) : -Float(speed)
		}
		nsViewController.overlay = overlay
		nsViewController.isTimelineEnabled = isTimelineEnabled
		nsViewController.isPlayPauseButtonEnabled = isPlayPauseButtonEnabled
		nsViewController.applyRequestedTimeRangeIfReady()
	}

	/**
	Update the preview state.

	- Returns: True if state was updated and needs a redraw, false otherwise.
	*/
	func updatePreviewState(_ controller: NSViewControllerType) -> Bool {
		guard
			let previewVideoCompositor = controller.currentItem.customVideoCompositor as? PreviewVideoCompositor
		else {
			return false
		}

		let previewCheckerboardParams = CompositePreviewFragmentUniforms(
			isDarkMode: colorScheme.isDark,
			videoBounds: controller.playerView.videoBounds
		)

		return previewVideoCompositor.updateState(
			state: .init(
				shouldShowPreview: shouldShowPreview,
				fullPreviewState: fullPreviewState,
				previewCheckerboardParams: previewCheckerboardParams
			)
		)
	}

	/**
	Sets or clears the video composition based on preview state.

	When preview is OFF, we don't use the custom compositor so AVPlayer handles rotation via `preferredTransform` normally.
	When preview is ON, we use the custom compositor which renders the preview overlay.
	*/
	func forceAVPlayerToRedraw(item: AVPlayerItem, forceRedraw: Bool = false) {
		guard let assetVideoComposition = (asset as? PreviewableComposition)?.videoComposition else {
			return
		}

		let shouldUsePreviewCompositor = shouldShowPreview && fullPreviewState.canShowPreview
		let targetVideoComposition = shouldUsePreviewCompositor ? assetVideoComposition : nil
		let hasCompositionStateChanged = (item.videoComposition != nil) != (targetVideoComposition != nil)
		guard
			forceRedraw || hasCompositionStateChanged
		else {
			return
		}

		item.videoComposition = targetVideoComposition
	}
}

// TODO: Move more of the logic here over to the SwiftUI view.
/**
A view controller containing AVPlayerView and also extending possibilities for trimming (view) customization.
*/
final class TrimmingAVPlayerViewController: NSViewController {
	private(set) var timeRange: ClosedRange<Double>?
	private let playerItem: AVPlayerItem
	fileprivate let player: LoopingPlayer
	private let controlsStyle: AVPlayerViewControlsStyle
	private let timeRangeDidChange: ((ClosedRange<Double>) -> Void)?
	private var cancellables = Set<AnyCancellable>()
	private var currentItemDurationRange: ClosedRange<Double>?
	private var pendingTimeRangeRequest: TrimmingAVPlayer.TimeRangeRequest?
	private var lastTimeRangeRequestID: UUID?
	private var isTrimmerReady = false
	private var isApplyingTimeRangeRequest = false


	let playerView = TrimmingAVPlayerView()
	private let timelineView = FixedTimelineView()
	private var nativeTimelineBar: NSView?


	fileprivate var overlay: NSView? {
		didSet {
			guard oldValue != overlay else {
				return
			}

			oldValue?.removeFromSuperview()
			placeOverlay()
		}
	}

	fileprivate var isTimelineEnabled = true {
		didSet {
			updateTimelineInteraction()
		}
	}

	private func updateTimelineInteraction() {
		timelineView.isInteractionEnabled = isTimelineEnabled
		playerView.isTimelineInteractionEnabled = isTimelineEnabled
		playerView.setPlayPauseButton(isEnabled: isTimelineEnabled && isPlayPauseButtonEnabled)
		if !isTimelineEnabled,
			let responder = view.window?.firstResponder as? NSView,
			responder.isDescendant(of: timelineView)
		{
			view.window?.makeFirstResponder(nil)
		}
	}

	/// The preview and timeline are separate siblings, so all overlay coordinates
	/// are relative to the actual video area and never include the controls below.
	private func placeOverlay() {
		guard let overlay, let parent = playerView.contentOverlayView else {
			return
		}
		if overlay.superview !== parent {
			overlay.removeFromSuperview()
			overlay.translatesAutoresizingMaskIntoConstraints = true
			overlay.autoresizingMask = []
			parent.addSubview(overlay)
		}
		let frame = parent.convert(playerView.videoBounds, from: playerView)
		if overlay.frame != frame {
			overlay.frame = frame
		}
	}

	private func installTimelineIfNeeded() {
		guard
			let trimView = playerView.firstSubview(deep: true, where: { $0.simpleClassName == "AVTrimView" }),
			let bar = trimView.superview?.superview?.superview,
			bar !== playerView,
			bar.isDescendant(of: playerView)
		else {
			return
		}

		// Keep AVKit's complete controls subtree and all its internal constraints,
		// actions, thumbnail generation and accessibility elements intact.
		let height = bar.getConstraintConstantFromSuperView(attribute: .height) ?? 64
		timelineView.restoreInteractionState()
		nativeTimelineBar?.removeFromSuperview()
		bar.removeFromSuperview()
		bar.translatesAutoresizingMaskIntoConstraints = false
		timelineView.addSubview(bar)
		NSLayoutConstraint.activate([
			bar.leadingAnchor.constraint(equalTo: timelineView.leadingAnchor, constant: 6),
			bar.trailingAnchor.constraint(equalTo: timelineView.trailingAnchor, constant: -6),
			bar.centerYAnchor.constraint(equalTo: timelineView.centerYAnchor),
			bar.heightAnchor.constraint(equalToConstant: min(64, max(1, height)))
		])
		nativeTimelineBar = bar
		playerView.detachedTimelineView = timelineView
		updateTimelineInteraction()
	}

	fileprivate var isPlayPauseButtonEnabled = true {
		didSet {
			guard isPlayPauseButtonEnabled != oldValue else {
				return
			}

			playerView.setPlayPauseButton(isEnabled: isTimelineEnabled && isPlayPauseButtonEnabled)
		}
	}

	/**
	The minimum duration the trimmer can be set to.
	*/
	var minimumTrimDuration = 0.1 {
		didSet {
			playerView.minimumTrimDuration = minimumTrimDuration
		}
	}

	var loopPlayback: Bool {
		get { player.loopPlayback }
		set {
			player.loopPlayback = newValue
		}
	}

	var bouncePlayback: Bool {
		get { player.bouncePlayback }
		set {
			player.bouncePlayback = newValue
		}
	}

	/**
	Get or set the current player item.

	When setting an item, it preserves the current playback rate (which means pause state too), playback position, and trim range.
	*/
	var currentItem: AVPlayerItem {
		get { player.currentItem! }
		set {
			let rate = player.rate
			let playbackPercentage = player.currentItem?.playbackProgress ?? 0
			let playbackRangePercentage = player.currentItem?.playbackRangePercentage

			isTrimmerReady = false
			player.replaceCurrentItem(with: newValue)

			let requestID = lastTimeRangeRequestID
			let hasPendingRequest = pendingTimeRangeRequest != nil
			DispatchQueue.main.async { [weak self, weak newValue] in
				guard let self, let newValue, player.currentItem === newValue else {
					return
				}
				player.rate = rate
				// A project import supersedes the old item's trim and playhead.
				guard !hasPendingRequest, pendingTimeRangeRequest == nil, lastTimeRangeRequestID == requestID else {
					return
				}
				newValue.seek(toPercentage: playbackPercentage)
				newValue.playbackRangePercentage = playbackRangePercentage
			}
		}
	}

	init(
		playerItem: AVPlayerItem,
		controlsStyle: AVPlayerViewControlsStyle = .inline,
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self.playerItem = playerItem
		self.player = LoopingPlayer(playerItem: playerItem)
		self.controlsStyle = controlsStyle
		self.timeRangeDidChange = timeRangeDidChange
		super.init(nibName: nil, bundle: nil)
	}

	deinit {
		print("TrimmingAVPlayerViewController - DEINIT")
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let container = NSView()
		container.addSubview(playerView)
		container.addSubview(timelineView)
		playerView.translatesAutoresizingMaskIntoConstraints = false
		timelineView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			playerView.topAnchor.constraint(equalTo: container.topAnchor),
			playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			playerView.bottomAnchor.constraint(equalTo: timelineView.topAnchor),
			timelineView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			timelineView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			timelineView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			timelineView.heightAnchor.constraint(equalToConstant: 76)
		])
		playerView.onVideoBoundsChange = { [weak self] in
			self?.installTimelineIfNeeded()
			self?.placeOverlay()
		}
		playerView.allowsVideoFrameAnalysis = false
		playerView.controlsStyle = controlsStyle
		playerView.player = player
		view = container
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Support replacing the item.
		player.publisher(for: \.currentItem)
			.compactMap(\.self)
			.flatMap { currentItem in
				// TODO: Make a `AVPlayerItem#waitForReady` async property when using Swift 6.
				currentItem.publisher(for: \.status)
					.first { $0 == .readyToPlay }
					.map { _ in currentItem }
			}
			.receive(on: DispatchQueue.main)
			.sink { [weak self] item in
				guard let self, player.currentItem === item else {
					return
				}

				if pendingTimeRangeRequest == nil {
					onNewDurationRange(durationRange: item.durationRange)
				} else {
					currentItemDurationRange = item.durationRange
				}

				// Ignore initialization changes until the requested project range is installed.
				playerView.observeTrimmedTimeRange { [weak self, weak item] timeRange in
					guard let self, let item, player.currentItem === item,
						pendingTimeRangeRequest == nil, !isApplyingTimeRangeRequest
					else {
						return
					}
					self.timeRange = timeRange
					timeRangeDidChange?(timeRange)
				}
				playerView.setupTrimmingObserver { [weak self, weak item] in
					guard let self, let item, player.currentItem === item else {
						return
					}
					installTimelineIfNeeded()
					isTrimmerReady = true
					applyRequestedTimeRangeIfReady()
				}
			}
			.store(in: &cancellables)
	}

	fileprivate func receiveTimeRangeRequest(_ request: TrimmingAVPlayer.TimeRangeRequest?) {
		guard let request, request.id != lastTimeRangeRequestID else {
			return
		}
		lastTimeRangeRequestID = request.id
		pendingTimeRangeRequest = request
	}

	fileprivate func applyRequestedTimeRangeIfReady() {
		guard let request = pendingTimeRangeRequest,
			currentItem.status == .readyToPlay, isTrimmerReady,
			let durationRange = currentItem.durationRange
		else {
			return
		}
		let range = request.range
		guard range.lowerBound.isFinite, range.upperBound.isFinite,
			range.lowerBound >= durationRange.lowerBound,
			range.upperBound <= durationRange.upperBound,
			range.lowerBound < range.upperBound
		else {
			pendingTimeRangeRequest = nil
			return
		}

		isApplyingTimeRangeRequest = true
		// Preserve imported fractional timestamps instead of rounding to the
		// 1/600-second convenience setter used by interactive trimming.
		currentItem.forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: 1_000_000_000)
		currentItem.reversePlaybackEndTime = CMTime(seconds: range.lowerBound, preferredTimescale: 1_000_000_000)
		currentItem.seek(to: currentItem.reversePlaybackEndTime, toleranceBefore: .zero, toleranceAfter: .zero)
		currentItemDurationRange = durationRange
		timeRange = range
		pendingTimeRangeRequest = nil
		isApplyingTimeRangeRequest = false
		playerView.needsLayout = true
		timeRangeDidChange?(range)
	}

	func onNewDurationRange(durationRange newItemDurationRange: ClosedRange<Double>?) {
		guard let newItemDurationRange else {
			currentItemDurationRange = nil
			return
		}
		defer {
			currentItemDurationRange = newItemDurationRange
		}
		guard
			let timeRange,
			let currentItemDurationRange
		else {
			self.timeRange = newItemDurationRange
			timeRangeDidChange?(newItemDurationRange)
			return
		}
		let newTimeRange = timeRange.translated(from: currentItemDurationRange, to: newItemDurationRange)
		self.timeRange = newTimeRange
		timeRangeDidChange?(newTimeRange)
	}
}

final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeCancellable: AnyCancellable?
	private var trimmingCancellable: AnyCancellable?
	private var readyForDisplayCancellable: AnyCancellable?
	private var checkerboardVideoBounds: CGRect?
	private var checkerboardContainerBounds: CGRect?
	private var pendingOverlayRefresh = false
	fileprivate var onVideoBoundsChange: (() -> Void)?
	fileprivate weak var detachedTimelineView: NSView?
	fileprivate var isTimelineInteractionEnabled = true

	private var nativeTrimView: NSView? {
		firstSubview(deep: true) { $0.simpleClassName == "AVTrimView" }
			?? detachedTimelineView?.firstSubview(deep: true) { $0.simpleClassName == "AVTrimView" }
	}


	/**
	The minimum duration the trimmer can be set to.
	*/
	var minimumTrimDuration = 0.1

	deinit {
		print("TrimmingAVPlayerView - DEINIT")
	}

	override func layout() {
		super.layout()

		updateCheckerboardViewIfNeeded()
		onVideoBoundsChange?()

		// AVKit can finish laying out its internal video layer after this view's
		// layout callback. Refresh both overlays once that pass has completed.
		guard !pendingOverlayRefresh else {
			return
		}
		pendingOverlayRefresh = true
		DispatchQueue.main.async { [weak self] in
			guard let self else {
				return
			}
			pendingOverlayRefresh = false
			updateCheckerboardViewIfNeeded()
			onVideoBoundsChange?()
		}
	}

	// TODO: This should be an AsyncSequence.
	fileprivate func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		var skipNextUpdate = false

		timeRangeCancellable = player?.currentItem?.publisher(for: \.duration, options: .new)
			.sink { [weak self] _ in
				guard
					let self,
					let item = player?.currentItem,
					let fullRange = item.durationRange,
					let playbackRange = item.playbackRange
				else {
					return
				}

				// Prevent infinite recursion.
				guard !skipNextUpdate else {
					skipNextUpdate = false
					updateClosure(playbackRange.minimumRangeLength(of: minimumTrimDuration, in: fullRange))
					return
				}

				guard playbackRange.length > minimumTrimDuration else {
					skipNextUpdate = true
					item.playbackRange = playbackRange.minimumRangeLength(of: minimumTrimDuration, in: fullRange)
					return
				}

				updateClosure(playbackRange)
			}
	}

	fileprivate func setupTrimmingObserver(onReady: @escaping () -> Void) {
		trimmingCancellable = Task {
			do {
				// Replacing a speed-adjusted player item can preserve the existing
				// trim session. In that state canBeginTrimming stays false because
				// trimming is already active; waiting for it would never restore
				// the imported range to the player or its existing handles.
				if nativeTrimView == nil {
					try await activateTrimming()
				}
				try Task.checkCancellation()
				hideTrimButtons()
				onReady()
				window?.makeFirstResponder(self)
			} catch is CancellationError {
				// Task was cancelled, ignore.
			} catch {
				assertionFailure("Failed to activate trimming: \(error)")
			}
		}
		.toCancellable

		observeReadyForDisplay()
	}

	private func observeReadyForDisplay() {
		readyForDisplayCancellable = publisher(for: \.isReadyForDisplay)
			.first(where: \.self)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.updateCheckerboardViewIfNeeded()
			}
	}

	fileprivate func setPlayPauseButton(isEnabled: Bool) {
		guard
			let avTrimView = nativeTrimView,
			let superview = avTrimView.superview
		else {
			return
		}

		guard let playPauseButton = superview.firstSubview(deep: true, where: {
			($0 as? NSButton)?.action?.description == "playPauseButtonPressed:"
		}) as? NSButton else {
			return
		}

		playPauseButton.isEnabled = isEnabled
	}

	fileprivate func hideTrimButtons() {
		// This method is a collection of hacks, so it might be acting funky on different OS versions.
		guard
			let avTrimView = nativeTrimView,
			let superview = avTrimView.superview
		else {
			return
		}

		// First find the constraints for `avTrimView` that pins to the left edge of the button.
		// Then replace the left edge of a button with the right edge - this will stretch the trim view.
		if #available(macOS 27, *) {
			// The play button is now a direct sibling, and the trailing constraint points to a separate container for Trim and Cancel.
			guard
				let constraint = superview.constraints.first(where: {
					($0.secondItem as? NSView) == avTrimView && $0.secondAttribute == .trailing
				}),
				let buttonContainer = constraint.firstItem as? NSView
			else {
				return
			}

			buttonContainer.isHidden = true
			superview.removeConstraint(constraint)
			constraint.changing(firstAttribute: .trailing).isActive = true
			return
		}

		if let constraint = superview.constraints.first(where: {
			($0.firstItem as? NSView) == avTrimView && $0.firstAttribute == .right
		}) {
			superview.removeConstraint(constraint)
			constraint.changing(secondAttribute: .right).isActive = true
		}

		if let constraint = superview.constraints.first(where: {
			($0.secondItem as? NSView) == avTrimView && $0.secondAttribute == .right
		}) {
			superview.removeConstraint(constraint)
			constraint.changing(firstAttribute: .right).isActive = true
		}

		// Now find buttons that are not images (images are playing controls) and hide them.
		superview.subviews
			.first { $0 != avTrimView }?
			.subviews
			.filter { ($0 as? NSButton)?.image == nil }
			.forEach {
				$0.isHidden = true
			}
	}

	private func updateCheckerboardViewIfNeeded() {
		guard let contentOverlayView else {
			return
		}

		// Large videos can become ready before AVPlayer has computed `videoBounds`. Wait for a real rect so the checkerboard does not cover the whole player.
		let convertedRect = contentOverlayView.convert(videoBounds, from: self)
		let clearRect = Self.checkerboardClearRect(convertedRect, in: contentOverlayView.bounds, isFlipped: contentOverlayView.isFlipped)
		guard !clearRect.isEmpty else {
			return
		}

		let existingCheckerboardViews = contentOverlayView.subviews.filter { $0.identifier == Self.checkerboardViewIdentifier }
		let needsNewCheckerboardView = clearRect != checkerboardVideoBounds || contentOverlayView.bounds != checkerboardContainerBounds || existingCheckerboardViews.isEmpty
		guard needsNewCheckerboardView else {
			return
		}

		for subview in existingCheckerboardViews {
			subview.removeFromSuperview()
		}

		let overlayView = NSHostingView(rootView: CheckerboardView(clearRect: clearRect))
		overlayView.identifier = Self.checkerboardViewIdentifier
		contentOverlayView.addSubview(overlayView)
		overlayView.constrainEdgesToSuperview()
		checkerboardVideoBounds = clearRect
		checkerboardContainerBounds = contentOverlayView.bounds
	}

	/// SwiftUI positions use top-left coordinates, independently of the AppKit host.
	static func checkerboardClearRect(_ rect: CGRect, in bounds: CGRect, isFlipped: Bool) -> CGRect {
		CGRect(
			x: rect.minX - bounds.minX,
			y: isFlipped ? rect.minY - bounds.minY : bounds.maxY - rect.maxY,
			width: rect.width,
			height: rect.height
		)
	}

	private static let checkerboardViewIdentifier = NSUserInterfaceItemIdentifier("CheckerboardView")

	/**
	Prevent user from dismissing trimming view.
	*/
	override func cancelOperation(_ sender: Any?) {}

	override func keyDown(with event: NSEvent) {
		guard isTimelineInteractionEnabled else {
			return
		}
		super.keyDown(with: event)
	}
}

/**
A permanently visible host for AVKit's native timeline. Disabling it prevents
mouse, keyboard and accessibility interaction while retaining the current trim.
*/
private final class FixedTimelineView: NSView {
	private var disabledControls = [(NSControl, Bool)]()
	private var disabledAccessibility = [(any NSAccessibilityProtocol, Bool)]()
	private var disabledElementIDs = Set<ObjectIdentifier>()

	var isInteractionEnabled = true {
		didSet {
			if isInteractionEnabled {
				restoreInteractionState()
			} else {
				disableInteraction()
			}
			alphaValue = isInteractionEnabled ? 1 : 0.45
			setAccessibilityEnabled(isInteractionEnabled)
			if oldValue != isInteractionEnabled {
				NSAccessibility.post(element: self, notification: .layoutChanged)
			}
		}
	}

	// AVKit's virtual sliders can ignore enabled setters on their ancestors.
	// Present one unavailable group while editing instead of publishing native
	// descendants that still accept accessibility increment/set-value actions.
	override func isAccessibilityElement() -> Bool { true }
	override func accessibilityRole() -> NSAccessibility.Role? { .group }
	override func accessibilityLabel() -> String? { "Timeline" }
	override func isAccessibilityEnabled() -> Bool { isInteractionEnabled }
	// swiftlint:disable:next discouraged_optional_collection
	override func accessibilityChildren() -> [Any]? {
		isInteractionEnabled ? super.accessibilityChildren() : []
	}

	override func accessibilityHitTest(_ point: CGPoint) -> Any? {
		isInteractionEnabled ? super.accessibilityHitTest(point) : self
	}

	func restoreInteractionState() {
		for (element, enabled) in disabledAccessibility {
			element.setAccessibilityEnabled(enabled)
		}
		for (control, enabled) in disabledControls {
			control.isEnabled = enabled
		}
		disabledAccessibility.removeAll()
		disabledControls.removeAll()
		disabledElementIDs.removeAll()
	}

	private func disableInteraction() {
		func disable(_ element: any NSAccessibilityProtocol) {
			guard disabledElementIDs.insert(ObjectIdentifier(element)).inserted else {
				return
			}
			disabledAccessibility.append((element, element.isAccessibilityEnabled()))
			if let control = element as? NSControl {
				disabledControls.append((control, control.isEnabled))
				control.isEnabled = false
			}
			element.setAccessibilityEnabled(false)
			for child in element.accessibilityChildren() ?? [] {
				if let child = child as? any NSAccessibilityProtocol {
					disable(child)
				}
			}
			if let view = element as? NSView {
				for child in view.subviews {
					disable(child)
				}
			}
		}
		for child in subviews {
			disable(child)
		}
	}

	override func hitTest(_ point: CGPoint) -> NSView? {
		guard !isInteractionEnabled else {
			return super.hitTest(point)
		}
		return frame.contains(point) ? self : nil
	}

	override func mouseDown(with event: NSEvent) {}
	override func rightMouseDown(with event: NSEvent) {}
	override func scrollWheel(with event: NSEvent) {}
	override func keyDown(with event: NSEvent) {}
}
