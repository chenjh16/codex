#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
mod bwrap;
pub mod landlock;
mod manager;
pub mod policy_transforms;
#[cfg(target_os = "macos")]
pub mod seatbelt;

#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
pub use bwrap::find_system_bwrap_in_path;

#[cfg(not(all(target_os = "linux", not(target_env = "ohos"))))]
pub fn find_system_bwrap_in_path() -> Option<std::path::PathBuf> {
    None
}
#[cfg(all(target_os = "linux", not(target_env = "ohos")))]
pub use bwrap::system_bwrap_warning;
pub use manager::SandboxCommand;
pub use manager::SandboxExecRequest;
pub use manager::SandboxManager;
pub use manager::SandboxTransformError;
pub use manager::SandboxTransformRequest;
pub use manager::SandboxType;
pub use manager::SandboxablePreference;
pub use manager::compatibility_sandbox_policy_for_permission_profile;
pub use manager::get_platform_sandbox;

use codex_protocol::error::CodexErr;

#[cfg(not(all(target_os = "linux", not(target_env = "ohos"))))]
pub fn system_bwrap_warning(
    _permission_profile: &codex_protocol::models::PermissionProfile,
) -> Option<String> {
    None
}

impl From<SandboxTransformError> for CodexErr {
    fn from(err: SandboxTransformError) -> Self {
        match err {
            SandboxTransformError::MissingLinuxSandboxExecutable => {
                CodexErr::LandlockSandboxExecutableNotProvided
            }
            #[cfg(all(target_os = "linux", target_env = "ohos"))]
            SandboxTransformError::LinuxSandboxUnsupportedOnHarmony => {
                CodexErr::UnsupportedOperation(
                    "Linux sandbox is not supported on HarmonyOS; Codex runs with the configured approval policy and workspace constraints instead".to_string(),
                )
            }
            #[cfg(all(target_os = "linux", not(target_env = "ohos")))]
            SandboxTransformError::Wsl1UnsupportedForBubblewrap => {
                CodexErr::UnsupportedOperation(crate::bwrap::WSL1_BWRAP_WARNING.to_string())
            }
            #[cfg(not(target_os = "macos"))]
            SandboxTransformError::SeatbeltUnavailable => CodexErr::UnsupportedOperation(
                "seatbelt sandbox is only available on macOS".to_string(),
            ),
        }
    }
}
