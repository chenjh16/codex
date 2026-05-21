//! TUI interactions for already-generated next-prompt suggestions.

use super::*;

impl App {
    pub(crate) fn clear_next_prompt_suggestion(&mut self) {
        self.chat_widget.clear_next_prompt_suggestion();
    }

    pub(crate) fn accept_next_prompt_suggestion(&mut self) -> bool {
        let Some(suggestion) = self.chat_widget.take_next_prompt_suggestion() else {
            return false;
        };
        self.chat_widget
            .set_composer_text(suggestion, Vec::new(), Vec::new());
        true
    }

    pub(crate) fn next_prompt_suggestion_key_should_accept(&self, key_event: KeyEvent) -> bool {
        self.chat_widget.can_show_next_prompt_suggestion()
            && matches!(
                key_event,
                KeyEvent {
                    code: KeyCode::Tab,
                    modifiers: KeyModifiers::NONE,
                    kind: KeyEventKind::Press,
                    ..
                }
            )
    }
}
