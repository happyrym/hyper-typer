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
            if store.candidates.isEmpty && store.isRefreshing {
                // 로딩 중엔 이전(낡은) 후보를 감추고 생성 중 표시만.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("후보 생성 중…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(Array(store.candidates.enumerated()), id: \.element.id) { idx, candidate in
                    row(index: idx + 1, candidate: candidate)
                }
                if store.appendingMore {
                    // early 후보는 이미 떠 있고, answer 후보가 아래에 더 붙는 중.
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                        Text("후보 더 생성 중…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
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
                .font(.system(size: store.fontSize - 2, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(candidate.text)
                .font(.system(size: store.fontSize))
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
