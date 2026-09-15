import SwiftUI

/// No fixed height: long statuses wrap, with secondary details moved underneath.
struct StatusFooter: View {
    let status: String
    let busy: Bool
    private var badge: some View {
        Text("LOCAL LIBRARY / AUTO-SAVED").tracking(0.5).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
    }
    private var indicator: some View {
        Circle().fill(busy ? Color.yellow : Color.green).frame(width: 6, height: 6).padding(.top, 4)
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                indicator
                Text(status).fixedSize().foregroundStyle(.primary)
                Spacer(minLength: 20)
                badge
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    indicator
                    Text(status).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary)
                }
                badge.padding(.leading, 16)
            }
        }
        .font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading).background(surface)
        .textSelection(.enabled).accessibilityElement(children: .combine)
    }
}
