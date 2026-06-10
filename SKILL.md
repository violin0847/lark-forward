---
name: lark-forward
description: "Control the Lark-to-tmux message forwarding daemon. Use this skill when the user mentions 'lark-forward', asks to start/stop/restart/check the Lark forwarder, wants to forward Lark messages to a tmux pane, hot-swap the target pane, inspect forwarding status/logs, or troubleshoot the Lark forwarding daemon. 当用户要求启动、停止、查看状态、切换转发目标、排查转发异常，或明确提到“lark-forward”“飞书消息转发”“tmux 转发”时，都应使用此 skill。**重要：所有飞书发来的消息，都必须在整个任务过程用飞书消息进行回复，并且绝对不可以不回复就停止工作。所有飞书发来的消息都会在最后一行的开头会有`# 这是一条飞书消息`这样的提示，应以此作为识别标识**"
---

# lark-forward skill

订阅飞书 IM 消息，将每条消息（附带飞书回复指令与表情确认约定）转发到指定的 tmux pane。

---

## 安装

### 前置要求

需要先确保环境中已经安装 `tmux` 和飞书 CLI。

如果尚未安装飞书 CLI，提示用户：可以这样安装飞书 CLI：`https://open.feishu.cn/document/no_class/mcp-archive/feishu-cli-installation-guide.md`

### 1. 获取通知用户的 User ID

安装前先确认 `--notify-uid` 要填的飞书用户 ID。它通常是 `ou_`开头的字符串格式的 `open_id`，用于把 daemon 启动、阻塞、报错等状态通知到正确的人。

优先使用 `lark-cli contact +get-user` 获取当前认证用户的 ID：

```bash
lark-cli contact +get-user
```

如果要通知其他人，先用姓名、邮箱或手机号搜索：

```bash
lark-cli contact +search-user "<姓名或邮箱>"
```

从输出中取 `open_id` / `user_id` 里形如 `ou_` 开头的字符串格式 的值，后续命令统一传给 `--notify-uid`。如果拿不到用户 ID，缺少权限将权限链接发给用户，先让用户授权获取自己的 `open_id`，不要用占位符启动 daemon。

### 2. 获取脚本位置

先确认脚本当前所在路径。本 skill 仓库内的默认位置是 `scripts/lark_forward.sh`，可用以下命令获取绝对路径：

```bash
realpath scripts/lark_forward.sh
```

将命令输出记为 `<script-path>`，后续所有示例中的 `<script-path>` 都指这里获取到的绝对路径。

### 3. 依赖检查

脚本依赖以下命令，确保均已安装并在 PATH 中：

| 命令 | 用途 |
|------|------|
| `lark-cli` | 飞书事件订阅 & 消息发送 |
| `python3` | JSON 解析（替代 jq） |
| `tmux` | 向目标 pane 注入文本 |

### 4. 持久运行方式

**方式 A — nohup（无 tmux 依赖，推荐在无界面服务器使用）**

```bash
nohup bash <script-path> <tmux-target> \
    --notify-uid <your-open-id> \
    > /tmp/lark_forward.log 2>&1 &

echo "PID=$!"   # 记录 PID 以便后续停止
```

停止：

```bash
kill $(pgrep -f lark_forward.sh)
```

查看日志：

```bash
tail -f /tmp/lark_forward.log
```

**方式 B — --daemon（内置 tmux 会话 + 自动重启，推荐日常使用）**

```bash
bash <script-path> <tmux-target> \
    --daemon \
    --notify-uid <your-open-id>
```

查看日志：`tmux attach -t lark-forward-daemon`
停止：`bash <script-path> --stop`

---

## 固定参数

以下命令中的 `<script-path>`，统一使用第 2 步输出的绝对路径。

| 参数 | 值 |
|------|-----|
| `--notify-uid` | `ou_` 开头的字符串格式的 `open_id` 开头的字符串格式的 `user_id` |
| 默认 tmux target | `0:0.0` |
| `script-path` | 第 2 步输出的绝对路径 |

---

## 子命令操作指南

### start [tmux-target]

用 `--daemon` 模式启动（默认 target: `0:0.0`）：

```bash
bash <script-path> <tmux-target> \
    --daemon \
    --notify-uid <your-open-id>
```

启动成功后告知用户：
- 转发目标 pane
- 查看日志：`tmux attach -t lark-forward-daemon`
- 热切换目标：`/lark-forward set-target <新 pane>`
- 停止：`/lark-forward stop`

### stop

```bash
bash <script-path> --stop
```

### status

```bash
bash <script-path> --status
```

### set-target \<tmux-target\>

热切换转发目标，无需重启 daemon，下条消息立即生效：

```bash
bash <script-path> --set-target <tmux-target>
```

---

## 消息处理约定

agent 收到转发消息后，按以下顺序处理：

1. 脚本收到消息后，会立刻给原消息加一个确认表情，`OK`、`SaluteFace`、`Typing`、`Get` 四选一随机使用，表示已经接单。
2. 脚本会记录创建表情返回的 `reaction_id`，并把它写入转发到 tmux 的回复提示中。
3. agent 准备正式回复时，先执行删除表情命令，再发送文本回复。

正式回复飞书时，如果回复内容包含多行，必须使用 `heredoc`、临时文件或 Bash 的 `$'...'` 三选一；不允许把 `\n` 写在普通引号字符串里，例如 `--text '第一行\n第二行'` 是错误写法，飞书里会看到字面量 `\n`，而不是真换行。

脚本内部实际执行的加确认表情命令示例（`emoji_type` 可为 `OK`、`SaluteFace`、`Typing`、`Get`）：

```bash
lark-cli im reactions create --as bot \
  --params '{"message_id":"om_x100b502dc58010acb48367797279d20"}' \
  --data '{"reaction_type":{"emoji_type":"OK"}}'
```

成功返回中会包含 `reaction_id`，例如：

```json
{
  "code": 0,
  "data": {
    "reaction_id": "pdAXrds5HMYY9UjYolDLhxfZMUgDKQ6uv-2VMFM7kF-vfqw9fFr8SDphHvM4hkFQ",
    "reaction_type": {
      "emoji_type": "OK"
    }
  },
  "msg": "success"
}
```

agent 正式回复前要执行的删除确认表情命令示例：

```bash
lark-cli im reactions delete --as bot \
  --params '{"message_id":"om_x100b502dc58010acb48367797279d20","reaction_id":"pdAXrds5HMYY9UjYolDLhxfZMUgDKQ6uv-2VMFM7kF-vfqw9fFr8SDphHvM4hkFQ"}'
```

多行正式回复推荐优先使用 `heredoc`，因为长文本、Markdown 和命令示例更容易维护：

```bash
reply=$(cat <<'EOF_INNER'
第一行
第二行
EOF_INNER
)
lark-cli im +messages-reply --as bot --message-id <msg_id> --text "$reply"
```

也可以使用 Bash ANSI-C quoting：

```bash
lark-cli im +messages-reply --as bot --message-id <msg_id> --text $'第一行\n第二行'
```

如果发送 Markdown 或较长总结，优先写到临时文件再发送：

```bash
lark-cli im +messages-reply --as bot --message-id <msg_id> --markdown "$(cat /tmp/reply.md)"
```

## 转发内容格式

每条转发到 tmux pane 的内容建议遵循以下格式：

```Plain
<原始消息文本>
# 这是一条飞书消息，你必须回复，回复方式：lark-cli im reactions delete --as {as_identity} --params '{"message_id":"{msg_id}","reaction_id":"{reaction_id}"}';lark-cli im +messages-reply --as {as_identity} --message-id {msg_id} --text '你的回复'
```

其中：

- `<msg_id>` 是原始飞书消息 ID。
- `<emoji_type>` 由脚本在 `OK`、`SaluteFace`、`Typing`、`Get` 中随机选择一个，并由脚本立即发送到原消息上。
- `<reaction_id>` 是脚本加确认表情成功后返回的 reaction ID，删除表情时必填。
- 正式回复前先删表情，避免消息长期保持“处理中”状态。

agent 收到后，不需要再次执行“加表情”命令；真正回复时，将 `你的回复` 替换为实际内容，并在发送前先删除对应的确认表情。若回复内容是多行文本，必须按上面的 `heredoc`、临时文件或 `$'...'` 方式传参，不能在普通引号里写 `\n`。

---

## 可选参数速查

| 参数 | 说明 |
|------|------|
| `--no-enter` | 发送文本但不按 Enter（默认按 Enter 提交） |
| `--with-sender` | 在消息前加 `sender_id: ` 前缀 |
| `--as user\|bot` | 订阅身份（默认 bot） |
| `--no-reply-prompt` | 不附加回复指令后缀 |
| `--reply-template T` | 自定义回复提示词模板，支持 `{msg_id}`、`{emoji_type}`、`{reaction_id}`、`{as_identity}` 占位 |
| `--raw` | 转发原始 NDJSON（调试用） |
