//
//  EphemeralWindow.swift
//
//  Copyright © 2022 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import AppKit
import Foundation
import QuartzCore

/// A window class that closes when the window resigns its focus (eg clicking outside it)
class EphemeralWindow: NSPanel {

	private var hasClosed = false

	override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
		super.init(
			contentRect: contentRect,
			styleMask: [.nonactivatingPanel, .titled, .borderless, .resizable, .closable, .fullSizeContentView],
			backing: backingStoreType,
			defer: flag
		)

		self.isFloatingPanel = true
		self.level = .floating

		/// Don't show a window title, even if it's set
		self.titleVisibility = .hidden
		self.titlebarAppearsTransparent = true

		self.hasShadow = true
		self.invalidateShadow()

		self.hidesOnDeactivate = true

		self.animationBehavior = .none
	}

	/// Close automatically when out of focus, e.g. outside click
	override func resignMain() {
		super.resignMain()
		self.close()
	}

    override func resignKey() {
        super.resignKey()
        self.close()
    }

	/// Close and toggle presentation, so that it matches the current state of the panel
	override func close() {
		if self.hasClosed == false {
			self.hasClosed = true
			// Cancel any pending present-animation callback and in-flight scale animation
			self.didFinishPresentAnimation = nil
			self.animationLayer?.removeAnimation(forKey: Self.animationKey)
			dismissWithAnimation { [weak self] in
				guard let self = self else { return }
				self.performSuperClose()
				self.didDetectClose?()
			}
		}
	}

	/// Helper to call super.close() from within a closure
	private func performSuperClose() {
		super.close()
	}

	/// A block that gets called when the window closes
	var didDetectClose: (() -> Void)?

	/// A block that gets called when the present animation finishes
	var didFinishPresentAnimation: (() -> Void)?

	/// The layer to apply scale animation to (defaults to contentView.layer)
	var animationLayer: CALayer?

	/// `canBecomeKey` and `canBecomeMain` are both required so that text inputs inside the panel can receive focus
	override var canBecomeKey: Bool {
		return true
	}

	override var canBecomeMain: Bool {
		return true
	}

	// MARK: - Spotlight-style Animations

	private static let animationKey = "spotlight_scale"

	/// Create a pair of spring animations (scale + translation) for one axis.
	/// The translation compensates for anchor point at (0,0) to simulate center-origin scaling.
	private static func makeAxisAnimations(
		scaleKeyPath: String,
		translationKeyPath: String,
		scaleFrom: CGFloat,
		scaleTo: CGFloat,
		axisLength: CGFloat,
		perceptualDuration: CGFloat,
		bounce: CGFloat,
		fillForwards: Bool
	) -> (CASpringAnimation, CASpringAnimation) {
		let scaleAnim: CASpringAnimation
		let transAnim: CASpringAnimation

		if #available(macOS 14.0, *) {
			scaleAnim = CASpringAnimation(perceptualDuration: perceptualDuration, bounce: bounce)
			transAnim = CASpringAnimation(perceptualDuration: perceptualDuration, bounce: bounce)
		} else {
			scaleAnim = CASpringAnimation(keyPath: scaleKeyPath)
			transAnim = CASpringAnimation(keyPath: translationKeyPath)
			let d: CGFloat = bounce > 0.2 ? 10 + (0.41 - bounce) * 20 : 20
			let s: CGFloat = bounce > 0.2 ? 300 : 150
			for a in [scaleAnim, transAnim] { a.damping = d; a.stiffness = s; a.mass = 1 }
		}

		scaleAnim.keyPath = scaleKeyPath
		scaleAnim.fromValue = scaleFrom
		scaleAnim.toValue = scaleTo
		scaleAnim.duration = scaleAnim.settlingDuration

		// Translation = axisLength * (1 - scale) / 2  keeps scaling visually centered
		transAnim.keyPath = translationKeyPath
		transAnim.fromValue = axisLength * (1.0 - scaleFrom) / 2.0
		transAnim.toValue = axisLength * (1.0 - scaleTo) / 2.0
		transAnim.duration = transAnim.settlingDuration

		if fillForwards {
			for a in [scaleAnim, transAnim] {
				a.fillMode = .forwards
				a.isRemovedOnCompletion = false
			}
		}

		return (scaleAnim, transAnim)
	}

	/// Present the window with a Spotlight-style spring scale + fade animation
	func presentWithAnimation() {
		let layer = self.animationLayer ?? self.contentView?.layer
		guard let layer = layer else {
			self.makeKeyAndOrderFront(nil)
			self.didFinishPresentAnimation?()
			self.didFinishPresentAnimation = nil
			return
		}

		CATransaction.begin()
		CATransaction.setDisableActions(true)
		self.alphaValue = 0
		CATransaction.commit()

		self.makeKeyAndOrderFront(nil)

		let bounds = layer.bounds

		let (sxAnim, txAnim) = Self.makeAxisAnimations(
			scaleKeyPath: "transform.scale.x", translationKeyPath: "transform.translation.x",
			scaleFrom: 1.12, scaleTo: 1.0, axisLength: bounds.width,
			perceptualDuration: 0.28, bounce: 0.41, fillForwards: false)

		let (syAnim, tyAnim) = Self.makeAxisAnimations(
			scaleKeyPath: "transform.scale.y", translationKeyPath: "transform.translation.y",
			scaleFrom: 0.95, scaleTo: 1.0, axisLength: bounds.height,
			perceptualDuration: 0.28, bounce: 0.32, fillForwards: false)

		let group = CAAnimationGroup()
		group.animations = [sxAnim, txAnim, syAnim, tyAnim]
		group.duration = [sxAnim, txAnim, syAnim, tyAnim].map(\.duration).max() ?? 0.3
		layer.add(group, forKey: Self.animationKey)

		if #available(macOS 14.0, *) {
			self.animations = ["alphaValue": CASpringAnimation(perceptualDuration: 0.28, bounce: 0.41)]
		}

		NSAnimationContext.runAnimationGroup({ context in
			context.duration = 0.25
			context.allowsImplicitAnimation = true
			self.animator().alphaValue = 1.0
		}, completionHandler: { [weak self] in
			self?.didFinishPresentAnimation?()
			self?.didFinishPresentAnimation = nil
		})
	}

	/// Dismiss the window with a Spotlight-style spring scale + fade animation
	private func dismissWithAnimation(completion: @escaping () -> Void) {
		let layer = self.animationLayer ?? self.contentView?.layer
		guard let layer = layer else {
			completion()
			return
		}

		let bounds = layer.bounds

		let (sxAnim, txAnim) = Self.makeAxisAnimations(
			scaleKeyPath: "transform.scale.x", translationKeyPath: "transform.translation.x",
			scaleFrom: 1.0, scaleTo: 1.12, axisLength: bounds.width,
			perceptualDuration: 0.45, bounce: 0.05, fillForwards: true)

		let (syAnim, tyAnim) = Self.makeAxisAnimations(
			scaleKeyPath: "transform.scale.y", translationKeyPath: "transform.translation.y",
			scaleFrom: 1.0, scaleTo: 0.95, axisLength: bounds.height,
			perceptualDuration: 0.45, bounce: 0.05, fillForwards: true)

		let group = CAAnimationGroup()
		group.animations = [sxAnim, txAnim, syAnim, tyAnim]
		group.duration = [sxAnim, txAnim, syAnim, tyAnim].map(\.duration).max() ?? 0.3
		group.fillMode = .forwards
		group.isRemovedOnCompletion = false
		layer.add(group, forKey: Self.animationKey)

		if #available(macOS 14.0, *) {
			self.animations = ["alphaValue": CASpringAnimation(perceptualDuration: 0.28, bounce: 0.41)]
		}

		NSAnimationContext.runAnimationGroup({ context in
			context.duration = 0.25
			context.allowsImplicitAnimation = true
			self.animator().alphaValue = 0
		}, completionHandler: completion)
	}
}
