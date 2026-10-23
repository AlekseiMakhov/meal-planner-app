import SwiftUI

/// A number in a table: right-aligned with even digits, a dash when there is none, «≈» when it is partial.
struct NumberCell: View {
    let value: Double?
    var digits = 1
    var isApproximate = false

    var body: some View {
        Text((isApproximate && value != nil ? "≈ " : "") + Formatting.number(value, digits: digits))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .foregroundStyle(value == nil ? Color(.textSecondary) : Color(.textPrimary))
    }
}
