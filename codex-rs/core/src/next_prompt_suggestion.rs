//! Samples a hidden next-prompt prediction from an already-loaded session.
//!
//! This module owns the model-facing half of next-prompt suggestions. It reuses
//! the visible thread history, appends one synthetic user instruction, samples a
//! short assistant reply, and filters the reply into text that is safe to show as
//! composer ghost text. It intentionally does not create a child thread, expose
//! tools, mutate transcript state, or decide whether the TUI should render the
//! result.
//!
//! Suggestions are best-effort. The caller should treat `Ok(None)` as an
//! expected silent outcome for early conversations, active turns, incomplete
//! tool flow, model silence, or filtered output.

use crate::client_common::Prompt;
use crate::client_common::ResponseEvent;
use crate::session::session::Session;
use codex_protocol::config_types::ServiceTier;
use codex_protocol::error::Result as CodexResult;
use codex_protocol::models::ContentItem;
use codex_protocol::models::ResponseItem;
use codex_protocol::openai_models::ModelPreset;
use codex_protocol::openai_models::ReasoningEffort;
use futures::StreamExt;
use std::collections::HashSet;
use std::time::Instant;

const NEXT_PROMPT_SUGGESTION_PROMPT: &str = r#"[SUGGESTION MODE: Suggest what the user might naturally type next into Codex.]

FIRST: Look at the user's recent messages and original request.

Your job is to predict what THEY would type - not what you think they should do.

Think about the next logical step. If you can infer a goal or a target new functionality, offer the next logical step towards that apparent goal or functionality.

THE TEST: Would they think "I was just about to type that"?

NEVER SUGGEST:
- Evaluative ("looks good", "thanks")
- Questions ("what about...?")
- Codex-voice ("Let me...", "I'll...", "Here's...")
- New ideas they didn't ask about
- Multiple sentences

Stay silent if the next step isn't obvious from what the user said.

Format: 2-12 words, match the user's style including capitalization, verbosity and others.

Reply with ONLY the suggestion, no quotes or explanation."#;

/// Predicts the user's likely next prompt without mutating the session.
///
/// The sample uses the prompt-visible history from `sess` plus one synthetic
/// suggestion instruction. Active turns and histories with unmatched tool call
/// pairs are suppressed before sampling because those states do not represent a
/// stable completed conversation boundary. Returning `Ok(None)` means there is
/// no suggestion worth showing, not that the request failed.
pub(crate) async fn suggest_next_prompt(sess: &Session) -> CodexResult<Option<String>> {
    if sess.active_turn.lock().await.is_some() {
        tracing::debug!("next prompt suggestion skipped while a turn is active");
        return Ok(None);
    }

    let started_at = Instant::now();
    let mut turn_context = sess.new_lightweight_turn().await;
    prefer_fast_suggestion_profile(&mut turn_context);

    let history = sess.clone_history().await;
    if has_unpaired_tool_flow(history.raw_items()) {
        tracing::debug!("next prompt suggestion skipped for incomplete tool flow");
        return Ok(None);
    }
    let mut prompt_input = history.for_prompt(&turn_context.model_info.input_modalities);
    if assistant_message_count(&prompt_input) < 2 {
        return Ok(None);
    }
    prompt_input.push(ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText {
            text: NEXT_PROMPT_SUGGESTION_PROMPT.to_string(),
        }],
        phase: None,
    });

    let prompt = Prompt {
        input: prompt_input,
        tools: Vec::new(),
        parallel_tool_calls: false,
        base_instructions: sess.get_base_instructions().await,
        personality: turn_context.personality,
        output_schema: None,
        output_schema_strict: true,
    };
    let inference_trace = sess.services.rollout_thread_trace.inference_trace_context(
        turn_context.sub_id.as_str(),
        turn_context.model_info.slug.as_str(),
        turn_context.provider.info().name.as_str(),
    );
    let mut client_session = sess.services.model_client.new_session();
    let mut stream = client_session
        .stream(
            &prompt,
            &turn_context.model_info,
            &turn_context.session_telemetry,
            turn_context.reasoning_effort,
            turn_context.reasoning_summary,
            turn_context.config.service_tier.clone(),
            /*turn_metadata_header*/ None,
            &inference_trace,
        )
        .await?;
    let mut streamed_text = String::new();
    let mut completed_text = None;
    while let Some(event) = stream.next().await {
        match event? {
            ResponseEvent::OutputItemDone(item) => {
                if let Some(text) = assistant_output_text(&item) {
                    completed_text = Some(text);
                }
            }
            ResponseEvent::OutputTextDelta(delta) => streamed_text.push_str(&delta),
            ResponseEvent::Completed { .. } => break,
            _ => {}
        }
    }

    let raw = completed_text.unwrap_or(streamed_text);
    let suggestion = filter_next_prompt_suggestion(&raw);
    tracing::debug!(
        latency_ms = u64::try_from(started_at.elapsed().as_millis()).unwrap_or(u64::MAX),
        model = %turn_context.model_info.slug,
        effort = ?turn_context.reasoning_effort,
        service_tier = ?turn_context.config.service_tier,
        has_suggestion = suggestion.is_some(),
        "next prompt suggestion sampled"
    );
    Ok(suggestion)
}

fn assistant_message_count(items: &[ResponseItem]) -> usize {
    items
        .iter()
        .filter(|item| matches!(item, ResponseItem::Message { role, .. } if role == "assistant"))
        .count()
}

fn assistant_output_text(item: &ResponseItem) -> Option<String> {
    let ResponseItem::Message { role, content, .. } = item else {
        return None;
    };
    if role != "assistant" {
        return None;
    }
    let text = content
        .iter()
        .filter_map(|content| match content {
            ContentItem::OutputText { text } => Some(text.as_str()),
            ContentItem::InputText { .. } | ContentItem::InputImage { .. } => None,
        })
        .collect::<String>();
    (!text.is_empty()).then_some(text)
}

/// Reports whether prompt-visible tool calls are missing their corresponding outputs.
///
/// Resume can expose a transcript while a prior tool flow is still incomplete.
/// Sampling that history would either produce malformed input or predict from a
/// boundary the user has not actually seen completed yet, so those sessions stay
/// silent until the call/output sets match again.
fn has_unpaired_tool_flow(items: &[ResponseItem]) -> bool {
    let mut function_calls = HashSet::new();
    let mut function_outputs = HashSet::new();
    let mut custom_tool_calls = HashSet::new();
    let mut custom_tool_outputs = HashSet::new();
    let mut tool_search_calls = HashSet::new();
    let mut tool_search_outputs = HashSet::new();

    for item in items {
        match item {
            ResponseItem::FunctionCall { call_id, .. } => {
                function_calls.insert(call_id.clone());
            }
            ResponseItem::FunctionCallOutput { call_id, .. } => {
                function_outputs.insert(call_id.clone());
            }
            ResponseItem::ToolSearchCall {
                call_id: Some(call_id),
                ..
            } => {
                tool_search_calls.insert(call_id.clone());
            }
            ResponseItem::ToolSearchOutput {
                call_id: Some(call_id),
                ..
            } => {
                tool_search_outputs.insert(call_id.clone());
            }
            ResponseItem::CustomToolCall { call_id, .. } => {
                custom_tool_calls.insert(call_id.clone());
            }
            ResponseItem::CustomToolCallOutput { call_id, .. } => {
                custom_tool_outputs.insert(call_id.clone());
            }
            ResponseItem::LocalShellCall {
                call_id: Some(call_id),
                ..
            } => {
                function_calls.insert(call_id.clone());
            }
            ResponseItem::Message { .. }
            | ResponseItem::Reasoning { .. }
            | ResponseItem::ToolSearchCall { call_id: None, .. }
            | ResponseItem::ToolSearchOutput { call_id: None, .. }
            | ResponseItem::WebSearchCall { .. }
            | ResponseItem::ImageGenerationCall { .. }
            | ResponseItem::LocalShellCall { call_id: None, .. }
            | ResponseItem::Compaction { .. }
            | ResponseItem::CompactionTrigger
            | ResponseItem::ContextCompaction { .. }
            | ResponseItem::Other => {}
        }
    }

    function_calls != function_outputs
        || custom_tool_calls != custom_tool_outputs
        || tool_search_calls != tool_search_outputs
}

/// Selects the fastest supported profile for an ephemeral suggestion sample.
///
/// This only adjusts the cloned lightweight turn context. It does not change the
/// parent thread's configured model, reasoning effort, or service tier.
fn prefer_fast_suggestion_profile(turn_context: &mut std::sync::Arc<crate::TurnContext>) {
    let Some(turn_context) = std::sync::Arc::get_mut(turn_context) else {
        return;
    };
    if let Some(preset) = turn_context
        .available_models
        .iter()
        .find(|preset| preset.model == turn_context.model_info.slug)
    {
        turn_context.reasoning_effort =
            preferred_suggestion_effort(preset, turn_context.reasoning_effort);
        if preset.supports_fast_mode() {
            std::sync::Arc::make_mut(&mut turn_context.config).service_tier =
                Some(ServiceTier::Fast.request_value().to_string());
        }
    }
}

fn preferred_suggestion_effort(
    preset: &ModelPreset,
    fallback: Option<ReasoningEffort>,
) -> Option<ReasoningEffort> {
    if preset_supports_effort(preset, ReasoningEffort::Minimal) {
        return Some(ReasoningEffort::Minimal);
    }
    if preset_supports_effort(preset, ReasoningEffort::Low) {
        return Some(ReasoningEffort::Low);
    }
    fallback
        .filter(|effort| preset_supports_effort(preset, *effort))
        .or(Some(preset.default_reasoning_effort))
}

fn preset_supports_effort(preset: &ModelPreset, effort: ReasoningEffort) -> bool {
    preset
        .supported_reasoning_efforts
        .iter()
        .any(|supported| supported.effort == effort)
}

/// Converts raw model text into a single composer-safe prompt candidate.
///
/// The model is allowed to stay silent. Formatting, meta labels, evaluative
/// replies, assistant-voice phrasing, and sentence-like outputs are rejected so
/// the UI only receives concise text the user could plausibly type verbatim.
fn filter_next_prompt_suggestion(raw: &str) -> Option<String> {
    let suggestion = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if suggestion.is_empty()
        || raw.chars().any(|ch| matches!(ch, '\n' | '\r' | '\t'))
        || suggestion.len() >= 100
        || suggestion.chars().any(|ch| matches!(ch, '?' | '!' | '.'))
        || suggestion.chars().any(|ch| matches!(ch, '`' | '*'))
        || suggestion.starts_with("- ")
    {
        return None;
    }

    let lower = suggestion.to_ascii_lowercase();
    if matches!(
        lower.as_str(),
        "done" | "no suggestion" | "stay silent" | "silence"
    ) || lower.starts_with("suggestion:")
        || lower.starts_with("next prompt:")
        || is_wrapped_meta(&suggestion)
        || starts_with_any(&lower, &["looks good", "thanks", "thank you"])
        || starts_with_any(&lower, &["let me", "i'll", "i will", "here's"])
    {
        return None;
    }

    let word_count = suggestion.split_whitespace().count();
    if word_count > 12
        || (word_count < 2 && !matches!(lower.as_str(), "yes" | "commit" | "push" | "continue"))
    {
        return None;
    }

    Some(suggestion)
}

fn is_wrapped_meta(suggestion: &str) -> bool {
    (suggestion.starts_with('(') && suggestion.ends_with(')'))
        || (suggestion.starts_with('[') && suggestion.ends_with(']'))
}

fn starts_with_any(value: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|prefix| value.starts_with(prefix))
}

#[cfg(test)]
mod tests {
    use super::filter_next_prompt_suggestion;
    use super::has_unpaired_tool_flow;
    use codex_protocol::models::FunctionCallOutputPayload;
    use codex_protocol::models::ResponseItem;
    use pretty_assertions::assert_eq;

    #[test]
    fn filter_keeps_specific_prompt() {
        assert_eq!(
            filter_next_prompt_suggestion("run the tests"),
            Some("run the tests".to_string())
        );
    }

    #[test]
    fn filter_keeps_allowed_single_word_prompt() {
        assert_eq!(
            filter_next_prompt_suggestion("commit"),
            Some("commit".to_string())
        );
    }

    #[test]
    fn filter_keeps_code_identifier_prompt() {
        assert_eq!(
            filter_next_prompt_suggestion("set CODEX_HOME"),
            Some("set CODEX_HOME".to_string())
        );
    }

    #[test]
    fn incomplete_custom_tool_flow_is_suppressed() {
        assert!(has_unpaired_tool_flow(&[ResponseItem::CustomToolCall {
            id: None,
            status: None,
            call_id: "call-1".to_string(),
            name: "exec".to_string(),
            input: "{}".to_string(),
        }]));
    }

    #[test]
    fn completed_custom_tool_flow_is_allowed() {
        assert!(!has_unpaired_tool_flow(&[
            ResponseItem::CustomToolCall {
                id: None,
                status: None,
                call_id: "call-1".to_string(),
                name: "exec".to_string(),
                input: "{}".to_string(),
            },
            ResponseItem::CustomToolCallOutput {
                call_id: "call-1".to_string(),
                name: Some("exec".to_string()),
                output: FunctionCallOutputPayload::from_text("done".to_string()),
            },
        ]));
    }

    #[test]
    fn filter_rejects_invalid_prompts() {
        for suggestion in [
            "",
            "done",
            "Suggestion: run the tests",
            "(stay silent)",
            "looks good",
            "thanks",
            "let me run tests",
            "what about tests?",
            "run tests.",
            "run\ntests",
            "continue with every possible next step in this project and explain every detail now",
        ] {
            assert_eq!(
                filter_next_prompt_suggestion(suggestion),
                None,
                "expected {suggestion:?} to be filtered"
            );
        }
    }
}
