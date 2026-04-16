import SwiftData
import SwiftUI

struct AssistantView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @Query private var tasks: [MeetingActionItem]
    @State private var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "Ask about decisions, tasks, deadlines, risks, or recurring topics from your meetings."
        )
    ]
    @State private var question = ""
    @State private var isAnswering = false
    @State private var lastCitations: [Meeting] = []

    private let engine = MeetingAssistantEngine()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBackground.ignoresSafeArea()

                VStack(spacing: NCSpacing.md) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: NCSpacing.md) {
                            ForEach(messages) { message in
                                AssistantBubble(message: message)
                            }

                            if isAnswering {
                                TypingIndicator()
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }

                            if !lastCitations.isEmpty {
                                VStack(alignment: .leading, spacing: NCSpacing.xs) {
                                    Text("Sources")
                                        .font(.ncCaption1.weight(.semibold))
                                        .foregroundStyle(Color.ncSecondary)
                                    ForEach(lastCitations.prefix(5), id: \.id) { meeting in
                                        NavigationLink(destination: InsightView(meeting: meeting)) {
                                            HStack {
                                                Image(systemName: "doc.text")
                                                Text(meeting.title)
                                                    .font(.ncCaption1)
                                                Spacer()
                                            }
                                            .foregroundStyle(Color.ncPurple)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, NCSpacing.sm)
                                .padding(.horizontal, NCSpacing.md)
                            }
                        }
                        .padding()
                    }

                    SuggestedQuestionsView { prompt in
                        question = prompt
                        ask()
                    }
                    .padding(.horizontal)

                    HStack(spacing: NCSpacing.sm + 2) {
                        TextField("Ask your meetings", text: $question, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .font(.ncBody)
                            .padding(NCSpacing.md)
                            .background(
                                Color.ncSurface,
                                in: RoundedRectangle(cornerRadius: NCRadius.medium, style: .continuous)
                            )
                            .onSubmit(ask)

                        Button(action: ask) {
                            Image(systemName: "arrow.up")
                                .font(.ncHeadline)
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(
                                    Color.ncPurple,
                                    in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                                )
                        }
                        .buttonStyle(NCPressButtonStyle())
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
            .navigationTitle("Ask")
            .animation(.ncEaseOut, value: isAnswering)
        }
    }

    private func ask() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        messages.append(AssistantMessage(role: .user, text: prompt))
        question = ""
        Task {
            isAnswering = true
            defer { isAnswering = false }
            let result = await engine.answer(question: prompt, meetings: meetings, tasks: tasks)
            lastCitations = result.citedMeetings
            messages.append(AssistantMessage(role: .assistant, text: result.answer))
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack {
            HStack(spacing: NCSpacing.xs + 2) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.ncMuted)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotScale(for: index))
                        .opacity(dotOpacity(for: index))
                }
            }
            .padding(.horizontal, NCSpacing.lg)
            .padding(.vertical, NCSpacing.md)
            .background(
                Color.ncSurface,
                in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
            )

            Spacer(minLength: 42)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.6)
                .repeatForever(autoreverses: true)
            ) {
                phase = 1
            }
        }
    }

    private func dotScale(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let adjusted = max(0, min(1, phase - delay / 0.6))
        return 0.6 + 0.4 * adjusted
    }

    private func dotOpacity(for index: Int) -> Double {
        let delay = Double(index) * 0.15
        let adjusted = max(0, min(1, phase - delay / 0.6))
        return 0.4 + 0.6 * adjusted
    }
}

// MARK: - Chat Bubble

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 42)
            }

            Text(message.text)
                .font(.ncBody)
                .textSelection(.enabled)
                .padding(NCSpacing.md)
                .foregroundStyle(message.role == .user ? .white : Color.ncInk)
                .background(
                    message.role == .user ? Color.ncPurple : Color.ncSurface,
                    in: RoundedRectangle(cornerRadius: NCRadius.small, style: .continuous)
                )

            if message.role == .assistant {
                Spacer(minLength: 42)
            }
        }
    }
}

// MARK: - Suggested Questions

private struct SuggestedQuestionsView: View {
    let choose: (String) -> Void

    private let prompts = [
        "What did we decide last week?",
        "List all tasks from yesterday meeting",
        "Show discussions about deadlines",
        "Find repeated issues"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NCSpacing.sm) {
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        choose(prompt)
                    } label: {
                        Text(prompt)
                            .font(.ncCaption1.weight(.semibold))
                            .foregroundStyle(Color.ncPurple)
                            .padding(.horizontal, NCSpacing.sm + 2)
                            .padding(.vertical, NCSpacing.xs + 1)
                            .background(
                                Color.ncPurple.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(NCPressButtonStyle())
                }
            }
        }
    }
}
