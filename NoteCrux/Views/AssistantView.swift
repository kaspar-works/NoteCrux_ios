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
                NoteCruxTheme.background(for: colorScheme).ignoresSafeArea()

                VStack(spacing: 12) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                AssistantBubble(message: message)
                            }
                            if !lastCitations.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sources")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(lastCitations.prefix(5), id: \.id) { meeting in
                                        NavigationLink(destination: InsightView(meeting: meeting)) {
                                            HStack {
                                                Image(systemName: "doc.text")
                                                Text(meeting.title)
                                                    .font(.caption)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.horizontal, 12)
                            }
                        }
                        .padding()
                    }

                    SuggestedQuestionsView { prompt in
                        question = prompt
                        ask()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 10) {
                        TextField("Ask your meetings", text: $question, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .onSubmit(ask)

                        Button(action: ask) {
                            Image(systemName: "arrow.up")
                                .font(.headline)
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
            .navigationTitle("Ask")
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

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 42)
            }

            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .foregroundStyle(message.role == .user ? .black : .primary)
                .background(
                    message.role == .user ? Color.green : Color.primary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            if message.role == .assistant {
                Spacer(minLength: 42)
            }
        }
    }
}

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
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(prompt) {
                        choose(prompt)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
