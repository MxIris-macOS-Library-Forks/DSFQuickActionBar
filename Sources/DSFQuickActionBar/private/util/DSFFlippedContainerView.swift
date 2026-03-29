import AppKit

/// A flipped NSView (origin at top-left) used as the window's content view.
/// This ensures subviews pinned to the top stay at a constant y-coordinate
/// when the window frame changes, preventing layout jumps during animation.
class DSFFlippedContainerView: NSView {
	override var isFlipped: Bool { return true }
}
