import Foundation

/// 후보 생성기 추상화 — 테스트에서 LLM(claude CLI)을 mock으로 대체하기 위한 경계.
protocol CandidateGenerating {
    func generate(from exchange: Exchange, count: Int) async -> [Candidate]
}

/// 포커스된 pane 해석 추상화 — 테스트에서 Orca 상태를 주입하기 위한 경계.
protocol FocusResolving {
    func focusedPaneInfo() -> PaneInfo?
}

extension CandidateGenerator: CandidateGenerating {}
extension OrcaState: FocusResolving {}
