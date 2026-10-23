import SwiftUI

/// The app's motion, one feel throughout. What rearranges or folds moves on a spring that settles without a
/// bounce; what appears grows in from a little smaller; hover and highlight ease out quickly, so the pointer never
/// waits. With «Уменьшить движение» in System Settings things only fade.
enum Motion {
    /// Rows, cards and dishes rearranging, groups folding, a panel opening.
    static let layout = Animation.smooth(duration: 0.3)
    /// One view giving way to another: a recipe and its editor, one week and the next.
    static let swap = Animation.smooth(duration: 0.22)
    /// Something small coming or going: a filter chip, a notice.
    static let pop = Animation.snappy(duration: 0.26)
    /// Hover, highlight, selection, a press: a strong ease-out.
    static let hover = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
}

extension View {
    /// Grows in from 96% as it fades in, and shrinks back on its way out; with reduced motion it only fades.
    func popTransition() -> some View {
        modifier(MotionTransition(moving: .scale(scale: 0.96)))
    }

    /// Rises a few points as it fades in: a notice at the bottom of a screen. With reduced motion it only fades.
    func noticeTransition() -> some View {
        modifier(MotionTransition(moving: .offset(y: 8)))
    }
}

private struct MotionTransition: ViewModifier {
    let moving: AnyTransition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .opacity.combined(with: moving))
    }
}

/// A card that gives a little under the pointer while it is pressed.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
            .animation(Motion.hover, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle {
        PressableButtonStyle()
    }
}
