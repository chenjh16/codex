//! Slash-command input parsing, cursor detection, and completion helpers.

use std::ops::Range;

use crate::bottom_pane::command_popup::CommandItem;
use crate::bottom_pane::command_popup::CommandPopup;
use crate::bottom_pane::command_popup::CommandPopupFlags;
use crate::bottom_pane::prompt_args::parse_slash_name;
use crate::bottom_pane::slash_commands::BuiltinCommandFlags;
use crate::bottom_pane::slash_commands::ServiceTierCommand;
use crate::bottom_pane::slash_commands::SlashCommandItem;
use crate::bottom_pane::slash_commands::find_slash_command;
use crate::bottom_pane::slash_commands::has_slash_command_prefix;
use crate::slash_command::SlashCommand;
use codex_protocol::user_input::ByteRange;
use codex_protocol::user_input::TextElement;

use super::QueuedInputAction;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum SlashValidation {
    Immediate,
    Deferred,
}

pub(super) enum SubmissionValidation {
    Valid,
    UnknownCommand(String),
}

pub(super) struct InlineCommand<'a> {
    pub(super) command: SlashCommandItem,
    pub(super) rest: &'a str,
    pub(super) rest_offset: usize,
}

pub(super) struct SlashInput<'a> {
    enabled: bool,
    is_bash_mode: bool,
    command_flags: BuiltinCommandFlags,
    service_tier_commands: &'a [ServiceTierCommand],
}

impl<'a> SlashInput<'a> {
    pub(super) fn new(
        enabled: bool,
        is_bash_mode: bool,
        command_flags: BuiltinCommandFlags,
        service_tier_commands: &'a [ServiceTierCommand],
    ) -> Self {
        Self {
            enabled,
            is_bash_mode,
            command_flags,
            service_tier_commands,
        }
    }

    pub(super) fn validate_submission(
        &self,
        text: &str,
        input_starts_with_space: bool,
    ) -> SubmissionValidation {
        if !self.enabled {
            return SubmissionValidation::Valid;
        }
        let Some((name, _rest, _rest_offset)) = parse_slash_name(text) else {
            return SubmissionValidation::Valid;
        };
        if input_starts_with_space || name.contains('/') {
            return SubmissionValidation::Valid;
        }
        if self.command(name).is_some() {
            SubmissionValidation::Valid
        } else {
            SubmissionValidation::UnknownCommand(name.to_string())
        }
    }

    pub(super) fn bare_command(&self, text: &str) -> Option<SlashCommandItem> {
        if !self.enabled || self.is_bash_mode {
            return None;
        }
        let first_line = text.lines().next().unwrap_or("");
        let (name, rest, _rest_offset) = parse_slash_name(first_line)?;
        if !rest.is_empty() {
            return None;
        }
        let command = self.command(name)?;
        if command.supports_inline_args()
            && parse_slash_name(text).is_some_and(|(_, full_rest, _)| !full_rest.is_empty())
        {
            return None;
        }
        Some(command)
    }

    pub(super) fn inline_command<'text>(&self, text: &'text str) -> Option<InlineCommand<'text>> {
        if !self.enabled || self.is_bash_mode || text.starts_with(' ') {
            return None;
        }

        let (name, rest, rest_offset) = parse_slash_name(text)?;
        if rest.is_empty() || name.contains('/') {
            return None;
        }

        let command = self.command(name)?;
        command.supports_inline_args().then_some(InlineCommand {
            command,
            rest,
            rest_offset,
        })
    }

    pub(super) fn should_parse_on_dequeue(&self, text: &str) -> bool {
        self.enabled && !text.starts_with(' ') && text.trim().starts_with('/')
    }

    pub(super) fn command_element_range(&self, first_line: &str) -> Option<Range<usize>> {
        if self.is_bash_mode {
            return None;
        }
        let (name, _rest, _rest_offset) = parse_slash_name(first_line)?;
        if name.contains('/') {
            return None;
        }
        let element_end = 1 + name.len();
        let has_space_after = first_line
            .get(element_end..)
            .and_then(|tail| tail.chars().next())
            .is_some_and(char::is_whitespace);
        if !has_space_after {
            return None;
        }
        self.command(name).is_some().then_some(0..element_end)
    }

    pub(super) fn is_editing_command_name(&self, first_line: &str, cursor: usize) -> bool {
        let Some((name, rest)) = command_under_cursor(first_line, cursor) else {
            return false;
        };
        if !self.enabled {
            return false;
        }
        if name.is_empty() {
            return rest.is_empty();
        }

        has_slash_command_prefix(name, self.command_flags, self.service_tier_commands)
    }

    pub(super) fn command_popup(&self, first_line: &str) -> CommandPopup {
        let mut command_popup = CommandPopup::new(
            CommandPopupFlags {
                collaboration_modes_enabled: self.command_flags.collaboration_modes_enabled,
                connectors_enabled: self.command_flags.connectors_enabled,
                plugins_command_enabled: self.command_flags.plugins_command_enabled,
                service_tier_commands_enabled: self.command_flags.service_tier_commands_enabled,
                goal_command_enabled: self.command_flags.goal_command_enabled,
                personality_command_enabled: self.command_flags.personality_command_enabled,
                realtime_conversation_enabled: self.command_flags.realtime_conversation_enabled,
                audio_device_selection_enabled: self.command_flags.audio_device_selection_enabled,
                windows_degraded_sandbox_active: self.command_flags.allow_elevate_sandbox,
                side_conversation_active: self.command_flags.side_conversation_active,
            },
            self.service_tier_commands.to_vec(),
        );
        command_popup.on_composer_text_change(first_line.to_string());
        command_popup
    }

    fn command(&self, name: &str) -> Option<SlashCommandItem> {
        find_slash_command(name, self.command_flags, self.service_tier_commands)
    }
}

pub(super) fn queued_input_action(
    prepared_text: &str,
    defer_slash_validation: bool,
) -> QueuedInputAction {
    if defer_slash_validation && prepared_text.starts_with('/') {
        QueuedInputAction::ParseSlash
    } else if prepared_text.starts_with('!') {
        QueuedInputAction::RunShell
    } else {
        QueuedInputAction::Plain
    }
}

pub(super) fn selected_command_dispatches_immediately_on_tab(command: &CommandItem) -> bool {
    matches!(command, CommandItem::Builtin(SlashCommand::Skills))
}

pub(super) fn selected_command_completion(
    first_line: &str,
    command: &CommandItem,
) -> Option<String> {
    let selected_command_text = format!("/{}", command.command());
    (!first_line.trim_start().starts_with(&selected_command_text))
        .then(|| format!("{selected_command_text} "))
}

pub(super) fn prepared_args(prepared_text: &str) -> Option<(&str, usize)> {
    let (_, prepared_rest, prepared_rest_offset) = parse_slash_name(prepared_text)?;
    Some((prepared_rest, prepared_rest_offset))
}

/// Translate full-text element ranges into command-argument ranges.
///
/// `rest_offset` is the byte offset where `rest` begins in the full text.
pub(super) fn args_elements(
    rest: &str,
    rest_offset: usize,
    text_elements: &[TextElement],
) -> Vec<TextElement> {
    if rest.is_empty() || text_elements.is_empty() {
        return Vec::new();
    }
    text_elements
        .iter()
        .filter_map(|elem| {
            if elem.byte_range.end <= rest_offset {
                return None;
            }
            let start = elem.byte_range.start.saturating_sub(rest_offset);
            let mut end = elem.byte_range.end.saturating_sub(rest_offset);
            if start >= rest.len() {
                return None;
            }
            end = end.min(rest.len());
            (start < end).then_some(elem.map_range(|_| ByteRange { start, end }))
        })
        .collect()
}

/// If the cursor is currently within a slash command on the first line,
/// extract the command name and the rest of the line after it.
fn command_under_cursor(first_line: &str, cursor: usize) -> Option<(&str, &str)> {
    if !first_line.starts_with('/') {
        return None;
    }

    let name_start = 1usize;
    let name_end = first_line[name_start..]
        .find(char::is_whitespace)
        .map(|idx| name_start + idx)
        .unwrap_or_else(|| first_line.len());

    if cursor > name_end {
        return None;
    }

    let name = &first_line[name_start..name_end];
    let rest_start = first_line[name_end..]
        .find(|c: char| !c.is_whitespace())
        .map(|idx| name_end + idx)
        .unwrap_or(name_end);
    let rest = &first_line[rest_start..];

    Some((name, rest))
}
