# Claude Code Hooks 配置机制详解

> 本文档详细说明 Claude Code 的 hooks 配置文件读取机制、优先级规则，以及我们的监控工具如何利用这些机制。

## 📚 官方文档参考

- **Hooks Guide**: https://docs.claude.com/en/docs/claude-code/hooks-guide
- **Hooks Reference**: https://docs.claude.com/en/docs/claude-code/hooks
- **Settings Reference**: https://docs.claude.com/en/docs/claude-code/settings

---

## 🗂️ 配置文件层次结构

Claude Code 使用**分层配置系统**，配置文件按以下优先级从高到低生效：

### 1. Enterprise Managed Policies (企业管理策略)
- **文件**: `managed-settings.json`
- **位置**: 企业级配置
- **特点**: **不可被覆盖**，由组织管理员统一管理
- **优先级**: ⭐⭐⭐⭐⭐ (最高)

### 2. Command Line Arguments (命令行参数)
- **特点**: 临时会话覆盖
- **优先级**: ⭐⭐⭐⭐

### 3. Local Project Settings (本地项目配置)
- **文件**: `.claude/settings.local.json`
- **位置**: 项目根目录
- **特点**:
  - 🔒 **不提交到版本控制** (自动添加到 .gitignore)
  - 🛠️ 个人偏好和实验性配置
  - 💻 机器特定的覆盖配置
- **用途**: 个人临时修改、本地测试、机器特定配置
- **优先级**: ⭐⭐⭐

### 4. Shared Project Settings (共享项目配置)
- **文件**: `.claude/settings.json`
- **位置**: 项目根目录
- **特点**:
  - ✅ **提交到版本控制**
  - 👥 团队共享
  - 📋 团队标准和规范
- **用途**: 团队统一的配置、项目特定的 hooks、权限策略
- **优先级**: ⭐⭐

### 5. User Settings (用户全局配置)
- **文件**: `~/.claude/settings.json`
- **位置**: 用户 home 目录
- **特点**:
  - 🌐 全局生效
  - 👤 个人默认配置
  - 🔄 所有项目继承
- **用途**: 用户级默认配置、全局 hooks、个人偏好
- **优先级**: ⭐ (最低，但作为基础配置)

---

## 🔄 配置继承与合并规则

### 核心原则

```
更具体的配置 > 更广泛的配置
本地配置 > 共享配置 > 用户配置
```

### 实际继承流程

```
User Settings (~/.claude/settings.json)
    ↓ [继承]
Shared Project Settings (.claude/settings.json)
    ↓ [继承+覆盖]
Local Project Settings (.claude/settings.local.json)
    ↓ [合并]
最终生效的配置
```

### 关键特性

1. **分层合并**: 配置不是完全覆盖，而是逐层合并
2. **字段级覆盖**: 下层只覆盖上层中存在冲突的字段
3. **继承机制**: 即使项目级没有某个配置，也会继承用户级配置

---

## 🎯 Hooks 配置的特殊性

### Hooks 不会被覆盖，而是**累加**

如果用户级配置了 `SessionStart` hook，项目级也配置了 `SessionStart` hook：
- ❌ **不会**: 项目级完全覆盖用户级
- ✅ **会**: 两个 hook 都会执行（按优先级顺序）

### Hooks 启动快照机制

根据官方文档：

> "Direct edits to hooks in settings files don't take effect immediately. Claude Code captures a snapshot of hooks at startup, uses this snapshot throughout the session, warns if hooks are modified externally, and requires review in `/hooks` menu for changes to apply."

**含义**:
- Hooks 在 **Claude Code 启动时** 被快照
- 会话期间修改配置文件 **不会立即生效**
- 外部修改会触发警告
- 需要通过 `/hooks` 菜单审核或重启 Claude Code

---

## 🧪 实际验证：XY-KLineChart-pro 项目案例

### 问题现象

```bash
# XY-KLineChart-pro 项目只有 settings.local.json
$ cat .claude/settings.local.json
{
  "permissions": {
    "allow": ["Bash(git checkout -b feature/upgrade-to-v10)"],
    "deny": [],
    "ask": []
  }
}

# 没有 hooks 配置，但监控功能正常工作！
```

### 原因分析

1. **用户级配置存在 hooks**:
```bash
$ cat ~/.claude/settings.json
{
  "hooks": {
    "SessionStart": [...],
    "UserPromptSubmit": [...],
    "Stop": [...],
    "Notification": [...]
  }
}
```

2. **继承机制生效**:
   - 项目级 `settings.local.json` 没有 hooks 配置
   - 根据继承规则，向上查找
   - 找到用户级 `~/.claude/settings.json` 的 hooks 配置
   - **用户级 hooks 被项目继承并执行**

3. **结论**:
   - ✅ 只需在**用户级**配置 hooks，就能对所有项目生效
   - ❌ 不需要为每个项目单独配置 hooks（除非需要项目特定的行为）

---

## 🔍 当前系统配置状态

### 用户级配置

```bash
$ cat ~/.claude/settings.json
```

**内容**: ✅ 完整的 Claude Code Monitor hooks 配置
- SessionStart (startup/resume)
- UserPromptSubmit
- Stop
- Notification

**效果**: 所有项目继承这些 hooks

### 项目级配置

根据 `~/.claude/claude-code-helper/backups/hook_targets.txt` 记录：

```bash
# 已修改的项目配置文件
/Users/lif/Documents/code/outweb/AI_web/deltaruneprophecy-app/.claude/settings.local.json
/Users/lif/Documents/code/outweb/AI_web/drawmingo-com/.claude/settings.local.json
/Users/lif/Documents/code/outweb/AI_web/easycomic-app/.claude/settings.local.json
... (共16个项目)
```

**实际检查结果**:
- 部分项目的 `settings.local.json` 包含 hooks 配置（冗余）
- 部分项目的 `settings.local.json` 只有 permissions 等其他配置（正常）

---

## 🎨 最佳实践建议

### 对于 Claude Code Monitor

#### ✅ 推荐方案：只配置用户级

```bash
# install.sh 应该只做这件事:
1. 修改 ~/.claude/settings.json (用户级)
2. 添加 hooks 配置
3. 完成！

# 好处：
✅ 简单可靠
✅ 全局生效
✅ 易于维护
✅ 卸载干净
```

#### ❌ 当前方案的问题：扫描并修改项目级配置

```bash
# install.sh 当前还做了这些:
1. 扫描 ~/Documents/**/.claude/settings*.json
2. 为每个项目添加 hooks 配置
3. 记录到 hook_targets.txt
4. 卸载时清理所有项目配置

# 问题：
❌ 不必要的复杂性
❌ 可能覆盖团队配置
❌ settings.local.json 本应是个人配置，不应被工具自动修改
❌ 增加卸载难度
⚠️ 如果用户级配置已经足够，这些操作是多余的
```

### 推荐的配置策略

#### 场景 1: 个人使用（当前情况）
```
只配置用户级 (~/.claude/settings.json)
→ 所有项目自动继承
→ 简单可靠
```

#### 场景 2: 团队使用
```
方案 A（推荐）:
  每个团队成员自己配置用户级 (~/.claude/settings.json)
  → 不影响版本控制
  → 个人选择是否启用监控

方案 B（团队强制）:
  配置项目级 (.claude/settings.json)
  → 提交到版本控制
  → 团队成员都会启用
  → 需要团队同意
```

#### 场景 3: 项目特定配置
```
只在特定项目需要不同行为时，才修改项目级配置
例如：
  - 某个项目需要额外的 hooks
  - 某个项目需要禁用某些 hooks
```

---

## 🔧 改进建议

### 建议 1: 简化 install.sh

```bash
# 移除项目扫描逻辑
# 只保留用户级配置

./install.sh
  ↓
1. 复制脚本到 ~/.claude/claude-code-helper/
2. 初始化数据库
3. 配置 ~/.claude/settings.json (仅用户级)
4. 添加 shell 别名
5. 完成！
```

**优点**:
- ✅ 代码量减少 ~150 行
- ✅ 安装速度更快
- ✅ 不会误触项目配置
- ✅ 卸载更简单
- ✅ 维护成本低

### 建议 2: 提供项目级配置选项

```bash
# 如果用户确实需要项目级配置
./install.sh --project-level

# 或者提供独立命令
./scripts/add-project-hooks.sh /path/to/project
```

### 建议 3: 完善文档

在 README.md 中说明:
1. hooks 配置的优先级
2. 用户级 vs 项目级的选择建议
3. 团队使用场景的最佳实践

---

## 📊 配置文件对比表

| 特性 | User Settings | Shared Project | Local Project |
|------|---------------|----------------|---------------|
| **文件路径** | `~/.claude/settings.json` | `.claude/settings.json` | `.claude/settings.local.json` |
| **作用范围** | 所有项目 | 当前项目（团队） | 当前项目（个人） |
| **版本控制** | ❌ 不提交 | ✅ 提交 | ❌ 不提交 |
| **优先级** | 最低 | 中等 | 较高 |
| **适用场景** | 个人全局配置 | 团队统一标准 | 个人实验/覆盖 |
| **Hooks 继承** | ✅ 被所有项目继承 | ✅ 覆盖用户级 | ✅ 覆盖项目级 |
| **监控工具推荐** | ⭐⭐⭐ 强烈推荐 | ⭐ 可选 | ❌ 不推荐 |

---

## 🎬 总结

### 关键发现

1. **Claude Code 使用 5 层配置系统**，优先级从高到低
2. **配置是分层合并的**，不是简单覆盖
3. **Hooks 会累加执行**，不会互相覆盖
4. **用户级配置会被所有项目继承**
5. **settings.local.json 用于个人偏好**，不应被工具自动修改

### 对 Claude Code Monitor 的影响

#### 当前实现
- ✅ 用户级配置: 正确且必需
- ⚠️ 项目级扫描: 不必要且可能有问题
- 📝 hook_targets.txt: 维护成本高

#### 推荐改进
- 🎯 **只配置用户级**: 简单可靠，完全够用
- 🚀 **移除项目扫描**: 减少复杂度和维护成本
- 📚 **完善文档**: 说明配置机制和最佳实践

### 用户答疑

**Q: 为什么 XY-KLineChart-pro 项目没有 hooks 配置，但监控仍然工作？**
A: 因为用户级的 `~/.claude/settings.json` 配置了 hooks，根据继承规则，所有项目都会继承用户级的配置。

**Q: 需要为每个项目单独配置 hooks 吗？**
A: 不需要！只需在用户级配置一次，就能对所有项目生效。

**Q: 什么时候需要项目级配置？**
A: 只有在以下情况才需要：
   - 团队要求统一启用某些 hooks（使用 settings.json）
   - 某个项目需要不同的 hook 行为
   - 临时测试或实验性配置（使用 settings.local.json）

**Q: settings.json 和 settings.local.json 有什么区别？**
A:
   - `settings.json`: 提交到 git，团队共享
   - `settings.local.json`: 不提交，个人使用

---

## 📅 文档更新日期

- **创建**: 2025-11-02
- **最后更新**: 2025-11-02
- **作者**: Claude Code Helper Project
- **版本**: 1.0.0
