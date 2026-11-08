import SwiftUI
import UIKit

// SwiftUI can prohibit dismissal but does not expose its attempted-dismiss event.
// Bridge only that event; draft ownership and confirmation stay in SwiftUI.
struct DiscardAttemptObserver: UIViewRepresentable {
    let disabled: Bool
    let attempted: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.disabled = disabled
        context.coordinator.attempted = attempted
        DispatchQueue.main.async { [weak view, coordinator = context.coordinator] in
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController {
                    var parent: UIViewController? = controller
                    while let node = parent {
                        if let presentation = node.presentationController {
                            if presentation.delegate !== coordinator { coordinator.downstream = presentation.delegate }
                            presentation.delegate = coordinator
                            return
                        }
                        parent = node.parent
                    }
                }
                responder = current.next
            }
        }
    }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var downstream: (any UIAdaptivePresentationControllerDelegate)?
        var disabled = false
        var attempted: (() -> Void)?
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !disabled && (downstream?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            downstream?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            downstream?.presentationControllerDidDismiss?(presentationController)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            downstream?.presentationControllerDidAttemptToDismiss?(presentationController)
            attempted?()
        }
    }
}
