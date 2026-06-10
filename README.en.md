# `lark-forward`
A Lark message-forwarding Skill that lets you interact with any command-line Agent / CodingAgent (e.g. Claude Code, Codex) through Lark conversations.

# Features

# Quick Start
Send the following prompt to your CodingAgent (e.g. Claude Code, Codex). It will follow [INSTALL.md](./INSTALL.md) to install and initialize `lark-forward` for you:

```
Please follow the steps in INSTALL.md at the root of this repository to install and initialize lark-forward for me.
```

# Manual Installation
## 1. Install dependencies
### 1.1 Install `lark-cli` and create a Lark bot (skip if already available)
- Install `lark-cli`:
```bash
npx @larksuite/cli@latest install
```

- Create a new bot:
```bash
lark-cli config init --new
```

- Authorize the recommended scopes:
```bash
lark-cli auth login --recommend
```

For more details, see [Lark CLI Capabilities & Best Practices](https://bytedance.larkoffice.com/docx/WnHkdJQM6oGpQFxm9i7ckVdenSh).

### 1.2 Install `tmux`
- Installation (Ubuntu / Debian shown below; on macOS use `brew install tmux`):
```bash
sudo apt install tmux
```

- Recommended: enable mouse support (click to switch panes, scroll history):
```bash
echo "set -g mouse on" >> ~/.tmux.conf
tmux source ~/.tmux.conf
```

- Common `tmux` commands:
```bash
# Start a session
tmux
tmux new -s <session-name>

# Attach to an existing session
tmux attach -t <session-name-prefix>

# List sessions
tmux ls
```

Detach from a session while keeping it running: press `Ctrl+B`, then `D`.
Kill a pane: focus the pane and press `Ctrl+D`.

## 2. Install `lark-forward`
1. Package `SKILL.md` and `scripts/lark_forward.sh`:
```bash
make
```
Install the resulting `dist/lark-forward.zip` as a Skill in your CodingAgent.

## 3. Usage
After installation, open `tmux`, launch any CodingAgent, and send it the following instruction:
```
Forward Lark messages to this pane.
```

You can then use the Lark bot to drive the CodingAgent in place of direct terminal interaction.

### Commands supported on the Lark side

| Command | Description |
|---------|-------------|
| `/<any command>` | Messages starting with a slash are passed through to the currently forwarded tmux pane as-is; they do not trigger the CodingAgent reply flow. For example, Claude Code's `/clear` / `/compact`, Codex's `/model`, etc., can be sent directly via Lark. |
| `/showtmux` | Built-in command. Asks the `lark-forward` daemon to capture the current target tmux pane's content and reply to the sender in Lark, so you can inspect the CodingAgent's terminal state directly from Lark. |

> Tip: `/showtmux` is handled by the `lark-forward` daemon and is **not** forwarded to the CodingAgent. Other slash commands are passed through to the tmux pane verbatim.
