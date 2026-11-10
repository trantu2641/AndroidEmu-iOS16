import UIKit

final class AndroidDisplayView: UIView {

    private var displayLayer: CALayer?

    override class var layerClass: AnyClass {
        return CALayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black

        isMultipleTouchEnabled = true

        layer.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attachDisplayLayer(_ layer: CALayer) {

        displayLayer?.removeFromSuperlayer()

        displayLayer = layer

        self.layer.addSublayer(layer)

        layer.frame = bounds

        layer.contentsGravity = .resizeAspect

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        displayLayer?.frame = bounds
    }

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        InputBridge.shared.handleTouches(
            touches,
            phase: .began,
            view: self
        )
    }

    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        InputBridge.shared.handleTouches(
            touches,
            phase: .moved,
            view: self
        )
    }

    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        InputBridge.shared.handleTouches(
            touches,
            phase: .ended,
            view: self
        )
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        InputBridge.shared.handleTouches(
            touches,
            phase: .cancelled,
            view: self
        )
    }
}
