# Project Zomboid Source Knowledge

面向 Project Zomboid Mod 作者与 AI 编程工具的本地原版源码知识库生成器。

本仓库发布构建、检索、校验和版本比较工具，不分发 Project Zomboid 的 JAR、Lua、scripts、资源或反编译源码。使用者需要从自己合法安装的 Project Zomboid Dedicated Server 在本地生成知识库。

## 能生成什么

- 原版 Lua 和 scripts 的逐文件快照与全文检索。
- `projectzomboid.jar` 的 class 清单和 SHA-256。
- `javap -p -s` 提取的类、字段、方法签名及 JVM 描述符。
- CFR 生成的可阅读 Java 重建源码。
- Lua 函数、事件注册、网络调用和脚本定义索引。
- SQLite FTS5 全文搜索数据库。
- Build ID、Depot Manifest、JAR 与源码树哈希。
- 游戏版本之间的文件、Java API、Lua、事件和协议差异报告。

生成内容位于 `generated/`，只保存在本地并被 Git 忽略。

## 环境要求

- Windows 10/11 和 PowerShell 7。
- Node.js 22.5 或更高版本，需要内置 `node:sqlite`。
- JDK，必须提供 `java` 和 `javap`；推荐 JDK 21 或更高版本。
- [CFR 0.152](https://www.benf.org/other/cfr/)。
- 自己合法安装的 Project Zomboid Dedicated Server。
- 建议预留至少 3 GB 磁盘空间和 16 GB 内存。

## 快速开始

```powershell
git clone https://github.com/LiuDaCheng666/pz-source-knowledge.git
Set-Location .\pz-source-knowledge

$env:PZ_CFR_JAR = 'C:\Tools\cfr-0.152.jar'
pwsh -NoProfile -File .\Build-PZSourceKnowledge.ps1 `
  -SourceRoot 'D:\ProjectZomboidDedicatedServer'
```

也可以直接传入 CFR 路径：

```powershell
pwsh -NoProfile -File .\Build-PZSourceKnowledge.ps1 `
  -SourceRoot 'D:\ProjectZomboidDedicatedServer' `
  -CfrJar 'C:\Tools\cfr-0.152.jar'
```

首次构建需要复制原版文本文件、读取 JAR、执行 `javap`、完整反编译并建立全文索引，耗时取决于 CPU 和磁盘速度。成功后会生成本机专用的 `current.json`。

## 查询

```powershell
pwsh -NoProfile -File .\Search-PZSourceKnowledge.ps1 `
  -Query 'sendServerCommand' -Limit 20

pwsh -NoProfile -File .\Search-PZSourceKnowledge.ps1 `
  -Query 'BaseVehicle container' -Scope game -Limit 20
```

搜索结果包含证据范围、相对路径、类型、命中片段和排序分值。AI 工具应先读取 `current.json`，记录 `gameBuildId` 与 `jarSha256`，再引用搜索结果。

## 校验

```powershell
pwsh -NoProfile -File .\Validate-PZSourceKnowledge.ps1
```

校验内容包括 JSONL 可解析性、SQLite 实际查询、Lua/scripts/Java 覆盖率、JAR 与字节码 API 是否存在，以及 CFR 文件数是否覆盖顶层 class。

## 游戏更新

先把新版专服下载到隔离目录，不要直接更新生产服务器：

```powershell
pwsh -NoProfile -File .\Check-PZSourceKnowledgeUpdate.ps1 `
  -SourceRoot 'D:\PZ-KB-Candidate'
```

检查会比较：

- Steam Build ID
- JAR SHA-256
- 原版 Lua/scripts 源码树 SHA-256
- 翻译、动画、服装、地图和模型等文本元数据 SHA-256

确认需要更新后执行：

```powershell
pwsh -NoProfile -File .\Check-PZSourceKnowledgeUpdate.ps1 `
  -SourceRoot 'D:\PZ-KB-Candidate' `
  -CfrJar 'C:\Tools\cfr-0.152.jar' `
  -Sync
```

新版本会创建新的不可变快照。只有完整校验通过后才原子更新 `current.json`；旧快照继续保留，并在 `generated/reports/` 生成版本差异报告。

## 给 Mod 和 AI 工具接入

知识库是只读的原版证据源。每个 Mod 应把自己的源码索引、兼容报告、测试和发布信息保存在自己的仓库，不得写回本知识库。

推荐流程：

1. 读取 `current.json`，确认目标 Build 和 JAR 哈希。
2. 使用 `Search-PZSourceKnowledge.ps1` 查询相关原版 API、Lua 和行为。
3. 字节码签名与描述符作为 Java API 权威证据。
4. CFR 输出只作为实现阅读材料，不视为官方原始源码。
5. 在 Mod 自己的仓库运行兼容测试并记录所依据的 Build。

仓库中的 [AGENTS.md](AGENTS.md) 可直接供 Codex 等 AI 编程代理读取。

## 数据结构

```text
generated/
  snapshots/<snapshot-id>/
    raw/media/lua/          原版 Lua
    raw/media/scripts/      原版 scripts
    raw/java/               本地 JAR
    bytecode/               class 清单与 javap API
    java-decompiled/        CFR 重建源码
    indexes/                JSONL 与 SQLite FTS5
    provenance.json         来源与哈希
  reports/                  版本差异报告
current.json                当前已验证快照指针
```

## 法律与版权边界

本仓库不包含也不授权分发 Project Zomboid 的游戏文件或反编译源码。生成内容仅供拥有合法游戏副本的用户在本地进行兼容性研究和 Mod 开发。Project Zomboid 及相关内容归 The Indie Stone 所有。

## License

本仓库自行编写的工具和文档使用 [MIT License](LICENSE)。该许可不适用于 Project Zomboid 的任何游戏内容。
