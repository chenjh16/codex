//! Composer placeholder support for predicted next prompts.

use super::*;

impl ChatWidget {
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn set_next_prompt_suggestion(&mut self, suggestion: Option<String>) {
        self.next_prompt_suggestion = suggestion;
        self.refresh_composer_placeholder();
    }

    pub(crate) fn clear_next_prompt_suggestion(&mut self) -> bool {
        if self.next_prompt_suggestion.take().is_none() {
            return false;
        }
        self.refresh_composer_placeholder();
        true
    }

    pub(crate) fn take_next_prompt_suggestion(&mut self) -> Option<String> {
        let suggestion = self.next_prompt_suggestion.take()?;
        self.refresh_composer_placeholder();
        Some(suggestion)
    }

    #[cfg(test)]
    pub(crate) fn next_prompt_suggestion(&self) -> Option<&str> {
        self.next_prompt_suggestion.as_deref()
    }

    pub(crate) fn can_show_next_prompt_suggestion(&self) -> bool {
        self.bottom_pane.composer_is_empty()
            && self.no_modal_or_popup_active()
            && !self.active_side_conversation
            && self.active_mode_kind() != ModeKind::Plan
            && self.last_non_retry_error.is_none()
            && self.codex_rate_limit_reached_type.is_none()
            && !self.bottom_pane.is_task_running()
    }

    pub(crate) fn refresh_composer_placeholder(&mut self) {
        let placeholder = if self.active_side_conversation {
            self.side_placeholder_text.clone()
        } else if self.can_show_next_prompt_suggestion()
            && let Some(suggestion) = self.next_prompt_suggestion.as_ref()
        {
            suggestion.clone()
        } else {
            self.normal_placeholder_text.clone()
        };
        self.bottom_pane.set_placeholder_text(placeholder);
    }
}
