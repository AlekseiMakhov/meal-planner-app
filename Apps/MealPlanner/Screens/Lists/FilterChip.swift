import SwiftUI

/// An active filter under the toolbar, as in Notion: «Отдел: Молочное +1». The chip opens its options; the
/// cross removes the filter.
struct FilterChip<Options: View>: View {
    let title: String
    let value: String
    let onRemove: () -> Void
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                options()
            } label: {
                Text("\(Text("\(title):").foregroundStyle(Color(.textSecondary))) \(value)")
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Button("Убрать фильтр «\(title)»", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .imageScale(.small)
                .foregroundStyle(Color(.textSecondary))
        }
        .chipBackground()
        .popTransition()
    }
}

extension View {
    func chipBackground() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.surfaceRaised), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.hairline)))
    }
}

/// «Показано 100 из 1 240» while the list is still loading, «354 продукта» when all of it is there.
struct ListFooter: View {
    let shown: Int
    let total: Int
    let noun: (one: String, few: String, many: String)

    var body: some View {
        HStack {
            Text(text)
                .font(.callout)
                .foregroundStyle(Color(.textSecondary))
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var text: String {
        let all = Formatting.count(total, noun.one, noun.few, noun.many)
        guard shown < total else { return all }
        return "Показано \(shown.formatted(.number.locale(Formatting.locale))) из \(all)"
    }
}
