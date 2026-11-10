import Foundation

final class AndroidSession {

    weak var display: AndroidDisplayView?

    var onBootStateChanged:
        ((String) -> Void)?

    private var running = false

    func start() {

        guard !running else {
            return
        }

        running = true

        onBootStateChanged?(
            "Starting Kernarium..."
        )

        AndroidBridge.shared.start(
            display: display
        ) { [weak self] state in

            self?.onBootStateChanged?(state)
        }
    }

    func stop() {

        guard running else {
            return
        }

        running = false

        AndroidBridge.shared.stop()

        onBootStateChanged?(
            "Android stopped"
        )
    }

    deinit {
        stop()
    }
}
