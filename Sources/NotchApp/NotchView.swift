import SwiftUI

struct NotchView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        let size = model.currentSize
        let topRadius: CGFloat = model.isExpanded ? 14 : 6
        let bottomRadius: CGFloat = model.isExpanded ? 28 : 12

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                    .fill(Color.black)

                if model.isExpanded {
                    ExpandedContent()
                        .padding(.top, model.geometry.collapsedSize.height)
                        .padding(.horizontal, topRadius + 18)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))
            .onTapGesture { model.expand() }
            .contextMenu {
                Button("NotchApp 종료") { NSApp.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.isExpanded)
    }
}

private struct ExpandedContent: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
