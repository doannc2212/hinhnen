use crate::config::SetterConfig;
use anyhow::{Context, Result, anyhow};
use std::{path::Path, process::Stdio, time::Duration};
use tokio::process::Command;

const DAEMON_READY_TIMEOUT: Duration = Duration::from_secs(5);
const DAEMON_POLL_INTERVAL: Duration = Duration::from_millis(100);

pub struct Awww {
    transition: Option<String>,
    transition_duration: f32,
}

impl Awww {
    pub fn new(cfg: &SetterConfig) -> Self {
        Self {
            transition: cfg.transition.clone(),
            transition_duration: cfg.transition_duration,
        }
    }

    pub async fn set(&self, path: &Path) -> Result<()> {
        ensure_daemon().await?;

        let status = self
            .img_command(path)
            .status()
            .await
            .context("failed to run awww - is awww installed?")?;
        if status.success() {
            Ok(())
        } else {
            Err(anyhow!("awww img exited with status {status}"))
        }
    }

    fn img_command(&self, path: &Path) -> Command {
        let mut cmd = Command::new("awww");
        cmd.arg("img").arg(path);
        if let Some(transition) = &self.transition {
            cmd.arg("--transition-type").arg(transition);
            cmd.arg("--transition-duration")
                .arg(self.transition_duration.to_string());
        }
        cmd
    }
}

async fn ensure_daemon() -> Result<()> {
    if daemon_ready().await {
        return Ok(());
    }

    tracing::info!("awww-daemon is not running; starting it");
    // Own process group so the daemon outlives Ctrl-C on awws in a terminal.
    Command::new("awww-daemon")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .process_group(0)
        .spawn()
        .context("failed to start awww-daemon - is awww installed?")?;

    let deadline = tokio::time::Instant::now() + DAEMON_READY_TIMEOUT;
    while tokio::time::Instant::now() < deadline {
        tokio::time::sleep(DAEMON_POLL_INTERVAL).await;
        if daemon_ready().await {
            return Ok(());
        }
    }
    Err(anyhow!(
        "awww-daemon did not become ready within {}s",
        DAEMON_READY_TIMEOUT.as_secs()
    ))
}

async fn daemon_ready() -> bool {
    Command::new("awww")
        .arg("query")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .is_ok_and(|status| status.success())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsStr;

    fn args(cmd: &Command) -> Vec<&OsStr> {
        cmd.as_std().get_args().collect()
    }

    #[test]
    fn img_command_with_transition() {
        let awww = Awww::new(&SetterConfig {
            transition: Some("wipe".into()),
            transition_duration: 2.5,
        });
        let cmd = awww.img_command(Path::new("/tmp/a.jpg"));
        assert_eq!(cmd.as_std().get_program(), "awww");
        assert_eq!(
            args(&cmd),
            [
                "img",
                "/tmp/a.jpg",
                "--transition-type",
                "wipe",
                "--transition-duration",
                "2.5"
            ]
        );
    }

    #[test]
    fn img_command_without_transition() {
        let awww = Awww::new(&SetterConfig {
            transition: None,
            transition_duration: 1.0,
        });
        let cmd = awww.img_command(Path::new("/tmp/a.jpg"));
        assert_eq!(args(&cmd), ["img", "/tmp/a.jpg"]);
    }
}
