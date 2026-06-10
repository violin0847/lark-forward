# `lark-forward` Installation Guide

> This document is intended for CodingAgents (e.g. Claude Code, Codex, Coco, Mir CLI). Follow the steps below in order to install and initialize `lark-forward` in the user's environment.

## Prerequisites
- A terminal with internet access (Linux / macOS).
- `node` / `npm` available (used to run `npx`).
- The user has cloned this repository, and the current working directory is the repository root.

## Step 1: Install `lark-cli` and create a Lark bot
> Skip this step if `lark-cli` is already installed and a bot has been created and authorized.

1. Install `lark-cli`:
   ```bash
   npx @larksuite/cli@latest install
   ```

2. Create a new bot (interactive wizard):
   ```bash
   lark-cli config init --new
   ```

3. Authorize the recommended scopes:
   ```bash
   lark-cli auth login --recommend
   ```

4. Verify that `lark-cli` works:
   ```bash
   lark-cli auth status
   ```

For more `lark-cli` capabilities, see [Lark CLI Capabilities & Best Practices](https://bytedance.larkoffice.com/docx/WnHkdJQM6oGpQFxm9i7ckVdenSh).

## Step 2: Install `tmux`
> Skip the install command if `tmux` is already installed; only run the configuration part.

1. Install:
   - Ubuntu / Debian:
     ```bash
     sudo apt install -y tmux
     ```
   - macOS:
     ```bash
     brew install tmux
     ```

2. Enable mouse support (click to switch panes, scroll history):
   ```bash
   echo "set -g mouse on" >> ~/.tmux.conf
   tmux source ~/.tmux.conf 2>/dev/null || true
   ```

3. Common `tmux` commands (for reference, do not execute):
   ```bash
   # Start a session
   tmux
   tmux new -s <session-name>

   # Attach to an existing session
   tmux attach -t <session-name-prefix>

   # List sessions
   tmux ls
   ```
   - Detach from a session while keeping it running: press `Ctrl+B`, then `D`.
   - Kill a pane: focus the pane, then press `Ctrl+D`.

## Step 3: Build and install the `lark-forward` Skill
1. Build the package from the repository root:
   ```bash
   make
   ```
   This produces `dist/lark-forward.zip`, which contains `SKILL.md` and `scripts/lark_forward.sh`.

2. Install `dist/lark-forward.zip` as a Skill in the current CodingAgent:
   - **Claude Code / generic (via [skills.sh](https://skills.sh/))**:
     ```bash
     npx skills add ./dist/lark-forward.zip
     ```
   - **Other CodingAgents**: import `dist/lark-forward.zip` according to that agent's Skill installation method. If unsure, ask the user which CodingAgent they use and follow its official documentation.

3. After installation, confirm that `lark-forward` appears in the Skill list.

## Step 4: Verify and use
1. Start a tmux session:
   ```bash
   tmux new -s agent
   ```

2. Inside tmux, launch any CodingAgent (e.g. `claude`, `codex`, `coco`).

3. Send the following instruction to the CodingAgent to trigger the `lark-forward` Skill and start the message-forwarding daemon:
   ```
   Forward Lark messages to this pane.
   ```

4. Send a message to the bound Lark bot and verify that the message is forwarded into the tmux pane.

> Tip: Messages starting with a slash are passed through to the tmux pane as commands. For example, Claude Code's `/clear` and `/compact` can be invoked directly via Lark messages.

## Troubleshooting
- `lark-cli auth status` reports not logged in: re-run `lark-cli auth login --recommend`.
- Lark messages are not forwarded to tmux:
  - Confirm a CodingAgent is running in the tmux pane and that "Forward Lark messages to this pane." has been sent.
  - Confirm the `lark-forward` daemon is running (see `SKILL.md` for status commands).
- Network failures on CN dev machines: configure a proxy and retry, e.g. `export http_proxy="http://sys-proxy-rd-relay.byted.org:8118"`.
