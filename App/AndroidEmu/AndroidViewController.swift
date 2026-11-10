import UIKit
import SwiftUI

struct AndroidViewControllerRepresentable:
    UIViewControllerRepresentable {

    func makeUIViewController(
        context: Context
    ) -> AndroidViewController {

        return AndroidViewController()
    }

    func updateUIViewController(
        _ uiViewController: AndroidViewController,
        context: Context
    ) {
    }
}

final class AndroidViewController: UIViewController {

    private let displayView = AndroidDisplayView()
    private let session = AndroidSession()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupDisplay()
        setupSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        session.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        session.stop()
    }

    private func setupDisplay() {

        displayView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(displayView)

        NSLayoutConstraint.activate([
            displayView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),

            displayView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),

            displayView.topAnchor.constraint(
                equalTo: view.topAnchor
            ),

            displayView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
    }

    private func setupSession() {

        session.display = displayView

        session.onBootStateChanged = { state in

            print("[AndroidEmu] \(state)")
        }
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }
}
