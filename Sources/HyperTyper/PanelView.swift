import SwiftUI

struct PanelView: View {
    @ObservedObject var store: CandidateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !store.lastAnswerPreview.isEmpty {
                Text("📟 \(store.lastAnswerPreview)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Divider()
            // 생성 중에도 이전 후보를 계속 보여줌(깜빡임 방지).
            ForEach(Array(store.candidates.enumerated()), id: \.element.id) { idx, candidate in
                row(index: idx + 1, candidate: candidate)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minWidth: 320, minHeight: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("다음 프롬프트 후보")
                .font(.system(size: 13, weight: .bold))
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
            Spacer()
            Button(action: { store.refreshFromTranscript() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("직전 답변으로 다시 생성")
        }
    }

    private func row(index: Int, candidate: Candidate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(candidate.text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: { store.copy(candidate) }) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("복사")
        }
        .padding(.vertical, 2)
    }
}
