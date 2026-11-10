import UIKit

final class InputBridge {

    static let shared = InputBridge()

    private init() {}

    enum TouchPhase {
        case began
        case moved
        case ended
        case cancelled
    }

    func handleTouches(
        _ touches: Set<UITouch>,
        phase: TouchPhase,
        view: UIView
    ) {

        for touch in touches {

            let point = touch.location(
                in: view
            )

            let x = Float(point.x)
            let y = Float(point.y)

            switch phase {

            case .began:

                AndroidBridge.shared.touch(
                    action: 0,
                    x: x,
                    y: y
                )

            case .moved:

                AndroidBridge.shared.touch(
                    action: 2,
                    x: x,
                    y: y
                )

            case .ended:

                AndroidBridge.shared.touch(
                    action: 1,
                    x: x,
                    y: y
                )

            case .cancelled:

                AndroidBridge.shared.touch(
                    action: 1,
                    x: x,
                    y: y
                )
            }
        }
    }
}
