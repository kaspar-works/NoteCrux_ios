import ActivityKit
import WidgetKit
import SwiftUI

struct NoteCruxWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isPaused ? "pause.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(context.state.isPaused ? Color.orange : Color(red: 0.48, green: 0.38, blue: 0.93))
                        Text(context.attributes.meetingTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WaveformBar(level: context.state.audioLevel, isPaused: context.state.isPaused)
                        .frame(height: 18)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(context.state.isPaused ? Color.orange : Color(red: 0.48, green: 0.38, blue: 0.93))
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(context.state.isPaused ? Color.orange : Color(red: 0.48, green: 0.38, blue: 0.93))
            }
            .keylineTint(Color(red: 0.48, green: 0.38, blue: 0.93))
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(context.state.isPaused ? Color.orange.opacity(0.15) : Color(red: 0.48, green: 0.38, blue: 0.93).opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(context.state.isPaused ? Color.orange : Color(red: 0.48, green: 0.38, blue: 0.93))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.meetingTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(context.state.isPaused ? "Paused" : "Recording")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer()

            WaveformBar(level: context.state.audioLevel, isPaused: context.state.isPaused)
                .frame(width: 52, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct WaveformBar: View {
    let level: Double
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                let offset = Double(index) * 0.14
                let modulated = isPaused ? 0.15 : max(0.15, min(1.0, level + sin(offset * .pi) * 0.3))
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isPaused ? Color.orange : Color(red: 0.48, green: 0.38, blue: 0.93))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: modulated, anchor: .center)
            }
        }
    }
}

extension RecordingActivityAttributes {
    fileprivate static var preview: RecordingActivityAttributes {
        RecordingActivityAttributes(meetingTitle: "Standup · April 20")
    }
}

extension RecordingActivityAttributes.ContentState {
    fileprivate static var recording: RecordingActivityAttributes.ContentState {
        RecordingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-425),
            isPaused: false,
            audioLevel: 0.6
        )
    }

    fileprivate static var paused: RecordingActivityAttributes.ContentState {
        RecordingActivityAttributes.ContentState(
            startedAt: Date().addingTimeInterval(-425),
            isPaused: true,
            audioLevel: 0.0
        )
    }
}

#Preview("Lock Screen", as: .content, using: RecordingActivityAttributes.preview) {
    NoteCruxWidgetsLiveActivity()
} contentStates: {
    RecordingActivityAttributes.ContentState.recording
    RecordingActivityAttributes.ContentState.paused
}
