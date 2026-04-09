import CrowCore
import CrowIPC
import Foundation

func hookHandlers(
    appState: AppState,
    notifManager: NotificationManager?
) -> [String: CommandRouter.Handler] {
    [
        "hook-event": { @Sendable params in
            guard let sessionIDStr = params["session_id"]?.stringValue,
                  let sessionID = UUID(uuidString: sessionIDStr),
                  let eventName = params["event_name"]?.stringValue else {
                throw RPCError.invalidParams("session_id and event_name required")
            }
            let payload = params["payload"]?.objectValue ?? [:]

            // Build a human-readable summary from the event
            let summary: String = {
                switch eventName {
                case "PreToolUse", "PostToolUse", "PostToolUseFailure":
                    let tool = payload["tool_name"]?.stringValue ?? "unknown"
                    return "\(eventName): \(tool)"
                case "Notification":
                    let msg = payload["message"]?.stringValue ?? ""
                    return "Notification: \(msg.prefix(80))"
                case "Stop":
                    return "Claude finished responding"
                case "StopFailure":
                    return "Claude stopped with error"
                case "SessionStart":
                    return "Session started"
                case "SessionEnd":
                    return "Session ended"
                case "PermissionRequest":
                    return "Permission requested"
                case "PermissionDenied":
                    return "Permission denied"
                case "UserPromptSubmit":
                    return "User submitted prompt"
                case "TaskCreated":
                    return "Task created"
                case "TaskCompleted":
                    return "Task completed"
                case "SubagentStart":
                    let agentType = payload["agent_type"]?.stringValue ?? "agent"
                    return "Subagent started: \(agentType)"
                case "SubagentStop":
                    return "Subagent stopped"
                case "PreCompact":
                    return "Context compaction starting"
                case "PostCompact":
                    return "Context compaction finished"
                default:
                    return eventName
                }
            }()

            let event = HookEvent(
                sessionID: sessionID,
                eventName: eventName,
                summary: summary
            )

            return await MainActor.run {
                let state = appState.hookState(for: sessionID)

                // Append to ring buffer (keep last 50 events per session)
                state.hookEvents.append(event)
                if state.hookEvents.count > 50 { state.hookEvents.removeFirst(state.hookEvents.count - 50) }

                // Update derived state based on event type.
                // Clear pending notification on ANY event that indicates
                // Claude moved past the waiting state (except Notification
                // itself, which may SET the pending state).
                if eventName != "Notification" && eventName != "PermissionRequest" {
                    state.pendingNotification = nil
                }

                switch eventName {
                case "PreToolUse":
                    let toolName = payload["tool_name"]?.stringValue ?? "unknown"
                    if toolName == "AskUserQuestion" {
                        // Question for the user — set attention state
                        state.pendingNotification = HookNotification(
                            message: "Claude has a question",
                            notificationType: "question"
                        )
                        state.claudeState = .waiting
                        state.lastToolActivity = nil
                    } else {
                        state.lastToolActivity = ToolActivity(
                            toolName: toolName, isActive: true
                        )
                        state.claudeState = .working
                    }

                case "PostToolUse":
                    let toolName = payload["tool_name"]?.stringValue ?? "unknown"
                    state.lastToolActivity = ToolActivity(
                        toolName: toolName, isActive: false
                    )

                case "PostToolUseFailure":
                    let toolName = payload["tool_name"]?.stringValue ?? "unknown"
                    state.lastToolActivity = ToolActivity(
                        toolName: toolName, isActive: false
                    )

                case "Notification":
                    let message = payload["message"]?.stringValue ?? ""
                    let notifType = payload["notification_type"]?.stringValue ?? ""
                    if notifType == "permission_prompt" {
                        // Permission needed — show attention state
                        state.pendingNotification = HookNotification(
                            message: message, notificationType: notifType
                        )
                        state.claudeState = .waiting
                    } else if notifType == "idle_prompt" {
                        // Claude is at the prompt — clear any stale permission notification
                        // but don't change claudeState (Stop already set it to .done)
                        state.pendingNotification = nil
                    }

                case "PermissionRequest":
                    // Don't override a "question" notification — AskUserQuestion
                    // triggers both PreToolUse and PermissionRequest, and the
                    // question badge is more specific than generic "Permission"
                    if state.pendingNotification?.notificationType != "question" {
                        state.pendingNotification = HookNotification(
                            message: "Permission requested",
                            notificationType: "permission_prompt"
                        )
                    }
                    state.claudeState = .waiting
                    state.lastToolActivity = nil

                case "UserPromptSubmit":
                    state.claudeState = .working

                case "Stop":
                    state.claudeState = .done
                    state.lastToolActivity = nil

                case "StopFailure":
                    state.claudeState = .waiting

                case "SessionStart":
                    let source = payload["source"]?.stringValue ?? "startup"
                    if source == "resume" {
                        state.claudeState = .done
                    } else {
                        state.claudeState = .idle
                    }

                case "SessionEnd":
                    state.claudeState = .idle
                    state.lastToolActivity = nil

                case "SubagentStart":
                    state.claudeState = .working

                case "TaskCreated", "TaskCompleted", "SubagentStop":
                    // Stay in working state
                    if state.claudeState != .waiting {
                        state.claudeState = .working
                    }

                default:
                    // PermissionDenied, PreCompact, PostCompact — state change
                    // handled by blanket notification clear above
                    if eventName == "PermissionDenied" {
                        state.claudeState = .working
                        state.lastToolActivity = nil
                    }
                }

                // Trigger notification/sound for this event
                notifManager?.handleEvent(
                    sessionID: sessionID,
                    eventName: eventName,
                    payload: payload,
                    summary: summary
                )

                return [
                    "received": .bool(true),
                    "session_id": .string(sessionIDStr),
                    "event_name": .string(eventName),
                ]
            }
        },
    ]
}
