use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;

use async_trait::async_trait;
use serde_json::Value as JsonValue;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::FunctionCallOutputContentItem;
use crate::runtime::CodeModeNestedToolCall;
use crate::runtime::ExecuteRequest;
use crate::runtime::ExecuteToPendingOutcome;
use crate::runtime::RuntimeResponse;
use crate::runtime::WaitOutcome;
use crate::runtime::WaitRequest;
use crate::runtime::WaitToPendingOutcome;
use crate::runtime::WaitToPendingRequest;

const CODE_MODE_UNAVAILABLE: &str =
    "Code Mode is unavailable in this HarmonyOS build because rusty_v8 has no aarch64-unknown-linux-ohos prebuilt archive.";

#[async_trait]
pub trait CodeModeTurnHost: Send + Sync {
    async fn invoke_tool(
        &self,
        invocation: CodeModeNestedToolCall,
        cancellation_token: CancellationToken,
    ) -> Result<JsonValue, String>;

    async fn notify(&self, call_id: String, cell_id: String, text: String) -> Result<(), String>;
}

struct Inner {
    stored_values: Mutex<HashMap<String, JsonValue>>,
    next_cell_id: AtomicU64,
}

pub struct CodeModeService {
    inner: Arc<Inner>,
}

impl CodeModeService {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Inner {
                stored_values: Mutex::new(HashMap::new()),
                next_cell_id: AtomicU64::new(1),
            }),
        }
    }

    pub async fn stored_values(&self) -> HashMap<String, JsonValue> {
        self.inner.stored_values.lock().await.clone()
    }

    pub async fn replace_stored_values(&self, values: HashMap<String, JsonValue>) {
        *self.inner.stored_values.lock().await = values;
    }

    pub fn allocate_cell_id(&self) -> String {
        self.inner
            .next_cell_id
            .fetch_add(1, Ordering::Relaxed)
            .to_string()
    }

    pub async fn execute(&self, request: ExecuteRequest) -> Result<RuntimeResponse, String> {
        Ok(unavailable_response(
            request.cell_id,
            request.stored_values,
        ))
    }

    pub async fn execute_to_pending(
        &self,
        request: ExecuteRequest,
    ) -> Result<ExecuteToPendingOutcome, String> {
        Ok(ExecuteToPendingOutcome::Completed(unavailable_response(
            request.cell_id,
            request.stored_values,
        )))
    }

    pub async fn wait(&self, request: WaitRequest) -> Result<WaitOutcome, String> {
        Ok(WaitOutcome::MissingCell(unavailable_response(
            request.cell_id,
            self.stored_values().await,
        )))
    }

    pub async fn wait_to_pending(
        &self,
        request: WaitToPendingRequest,
    ) -> Result<WaitToPendingOutcome, String> {
        Ok(WaitToPendingOutcome::MissingCell(unavailable_response(
            request.cell_id,
            self.stored_values().await,
        )))
    }

    pub fn start_turn_worker(&self, _host: Arc<dyn CodeModeTurnHost>) -> CodeModeTurnWorker {
        CodeModeTurnWorker
    }
}

impl Default for CodeModeService {
    fn default() -> Self {
        Self::new()
    }
}

pub struct CodeModeTurnWorker;

fn unavailable_response(
    cell_id: String,
    stored_values: HashMap<String, JsonValue>,
) -> RuntimeResponse {
    RuntimeResponse::Result {
        cell_id,
        content_items: vec![FunctionCallOutputContentItem::InputText {
            text: CODE_MODE_UNAVAILABLE.to_string(),
        }],
        stored_values,
        error_text: Some(CODE_MODE_UNAVAILABLE.to_string()),
    }
}
