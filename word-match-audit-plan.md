# 单词对对碰站点调研与复现方案

## 1. 站点现状结论

- 目标站点：`https://htmls.tsdanci.com/word-match/v30/`
- 页面标题：`单词对对碰 - Word Match Game`
- 形态判断：这是一个 **静态前端站点**，主页面由 Next.js 静态资源输出，运行时再从 CDN 拉取远程 JSON 数据。
- 服务器形态：主站首页由 `nginx` 返回，HTML 中没有发现业务 API 调用入口，核心是前端本地状态 + CDN 资源。
- 当前产品并不只是“单词气泡匹配页”，而是已经包含：
  - 游戏主界面
  - 本地字典
  - 导入记录
  - 游戏历史
  - 帮助面板
  - 一键初始化
  - 多词模式
  - 音效/发音/提示/搜索等游戏控制项

## 2. 已确认的完整功能清单

### 2.1 游戏主界面

- 气泡式中英单词匹配。
- 右上角计时器。
- 底部进度：`已完成 / 总数`。
- 单词搜索框：占位文案为 `搜索单词/拼音 (Enter选择)`。
- 搜索支持“单词 / 拼音”两种入口。
- 底部有“选择 -> 匹配”状态提示。
- 有重开/重置入口。

### 2.2 游戏控制项

- 音效开关：按钮标题为 `关闭音效`。
- 单词发音开关：按钮标题为 `关闭单词发音`。
- 显示顺序切换：
  - `中文优先`
  - `英文优先`
  - `中英混合`
- 难度切换：
  - `简单模式`
  - `困难模式`
- 实测补充：
  - 切到 `困难模式` 后会立刻刷新当前牌面
  - 按钮标题会切换为 `难度: 困难模式`
  - 计时会进入明显更紧的短时压力状态
- 提示按钮：
  - 标题为 `提示配对词 (Ctrl / ⌘ + /)`
  - 代码中明确写了 `单匹配模式可用`
- 使用说明按钮：标题为 `使用说明 (?)`

### 2.3 多词模式

- 主界面可从 `多词模式` 切换进入。
- 切换后会显示新的输入栏，界面上可见：
  - `单词模式`（返回普通模式）
  - `开始匹配`
- 代码里还能确认多词模式下有这些能力：
  - 输入内容按空格/回车拆分
  - `拆分`
  - `清空所有条目`
  - 开始匹配前先整理词条

### 2.4 新增单词 / 录入面板

- 侧边栏入口：`新增单词`
- 右侧抽屉标题：`单词录入`
- 文本区支持三类输入方式：
  - 直接输入英文词，自动去本地字典补全中文
  - 输入 `apple=苹果`
  - 输入 `banana 香蕉`
  - 粘贴一篇英文文章后自动抽取单词
- 当前界面确认按钮：
  - `自动完成`
  - `导入`
- 代码里还能确认完整流程：
  - 先抽取单词对
  - 进入可编辑预览表格
  - 单条编辑英文/中文
  - 删除某一行
  - 底部“快速添加”输入框
  - 快速添加时支持再次自动补全
  - 将预览结果打包为一组“导入词库”

### 2.5 导入记录

- 侧边栏入口：`导入记录`
- 右侧抽屉标题：`导入记录`
- 当前界面确认按钮：
  - `导入`
  - `导出`
  - `清空记录`
- 每组导入记录支持：
  - 行内改名
  - 显示来源
  - 显示创建时间
  - 显示单词总数
  - 预览前 4 个词
  - `开始这一组单词`
  - 删除单组记录
- 当前记录会显示 `进行中`
- 空状态文案也已确认。

### 2.6 游戏历史

- 侧边栏入口：`游戏历史`
- 右侧抽屉标题：`历史记录`
- 当前界面确认按钮：
  - `清空历史`
- 代码里还能确认：
  - 删除单条历史
  - 清空全部历史
- 我实际查看时为空状态：`还没有游戏历史`

### 2.7 帮助

- 侧边栏入口：`帮助`
- 右侧抽屉为 iframe 帮助面板。
- 已确认 iframe 地址：
  - `https://ts-danci.feishu.cn/wiki/NqlPwDn8bioFnjk5Huqc25fLnVg`
- 代码里还能确认该帮助抽屉支持拖拽改变宽度。

### 2.8 一键配置 / 一键准备

- 侧边栏入口：`一键配置`
- 页面底部有引导卡片：`一键准备字典与导入记录`
- 已确认步骤条：
  - `本地字典`
  - `导入记录`
  - `自动完成（可选）`
- 文案说明已经确认：
  - 自动初始化本地字典
  - 加载远程导入记录
  - 没有远程数据时使用内置例子数据
- 可见按钮：
  - `查看导入记录`
  - `一键配置`
  - 完成后可 `重新配置`
  - 可收起引导

### 2.9 字典配置

- 侧边栏入口：`字典配置`
- 页面标题：`字典配置`
- 已确认展示信息：
  - 当前版本
  - 最后更新
  - 最近检查
  - 总词条数
- 当前运行时实测数据：
  - 当前版本：`v2`
  - 词条数：`26564`
- 可见按钮：
  - `导入字典`
  - `导出备份`
  - `检查更新`
  - `更新字典`
  - `清空数据`

## 3. 数据源与外部依赖

### 3.1 已确认远程资源

- 远程配置：
  - `https://oss-cdn.tsdanci.com/a-json-data/dict/latest.json`
- 返回内容中明确包含：
  - `version: 2`
  - `downloadUrl: https://oss-cdn.tsdanci.com/a-json-data/dict/v1.json`
  - `articleUrl`
  - `templateUrl`
  - `wordMatchUrl: https://oss-cdn.tsdanci.com/a-json-data/dict/word_match_v2.json`
  - `updatedAt`

### 3.2 已确认字典数据格式

- `v1.json` 是主词典，格式为数组。
- 单条结构实测为：
  - `word`
  - `chinese`
  - `chinesePos`
  - `us`

### 3.3 已确认导入记录模板格式

- `word_match_v2.json` 中实测存在：
  - `historyItems`
- 每组结构包括：
  - `id`
  - `name`
  - `source`
  - `createdAt`
  - `createdAtLabel`
  - `words`
- `words` 内部为：
  - `en`
  - `zh`

### 3.4 已确认音频依赖

- 成功音效：
  - `https://d.tsdanci.com/mp3/yes.mp3`
- 失败音效：
  - `https://d.tsdanci.com/mp3/failure.mp3`
- 英文发音：
  - `https://dict.youdao.com/dictvoice?audio=...`

## 4. 隐藏逻辑与兼容策略

### 4.1 导入记录远程回退逻辑

- 代码优先尝试远程导入记录 URL。
- 我实测直接访问 `word_match_import_history_v1.json` 返回 `NoSuchKey`。
- 但站点代码会继续回退：
  1. 先看 `latest.json` 里的 `wordMatchUrl`
  2. 再不行就退回内置 example 数据

这说明当前线上产品已经在做“远程模板缺失时自动兜底”。

### 4.2 导入记录 JSON 的兼容输入

- 代码可接受这些顶层字段之一：
  - `historyItems`
  - `importHistory`
  - `packs`
  - `records`
  - `data`
  - `examples`
  - `words`
- 单词字段兼容别名：
  - 英文：`en / word / english / text`
  - 中文：`zh / chinese / translation / meaning / cn`

### 4.3 新增单词抽取逻辑

- 自动完成模式并不只吃固定格式。
- 它会同时支持：
  - `english=中文`
  - `english 中文`
  - 从句子/段落中抽取英文词
  - 先查本地词典再补全中文
- 这意味着复现时不能只做一个简单 textarea + split。

## 5. 对当前站点的关键判断

### 5.1 当前站点是“前端重、本地存储重”

- 没有发现业务 API 服务依赖。
- 字典、导入记录、历史记录、设置都明显偏本地持久化思路。
- 这对我们复现是好事：
  - 可以先做“纯本地离线版”
  - 再决定是否加服务端同步

### 5.2 当前站点的真实产品边界

如果按复刻目标来拆，至少要覆盖 7 个模块：

1. 游戏引擎  
2. 字典系统  
3. 新增单词/文本抽取  
4. 导入记录  
5. 游戏历史  
6. 一键初始化  
7. 帮助/设置/音频/发音/提示

## 6. 复现建议：推荐技术栈

## 6.1 最推荐方案

采用：

- 前端：`React + TypeScript + Vite`
- UI：`Tailwind CSS + shadcn/ui`
- 状态：`Zustand`
- 搜索：`Fuse.js` 或 `FlexSearch`
- 拼音：`pinyin-pro`
- 服务端：`Go`
- 数据库：`SQLite`
- 部署形态：`Go 单文件二进制 + 内嵌前端静态资源`

### 为什么推荐这套

- 你在 Mac 上开发没问题。
- Windows 使用方 **不需要安装 Node / Python / Java / 数据库环境**。
- Go 后端可以直接编译：
  - macOS 一个可执行文件
  - Windows 一个 `.exe`
- 同一套产物既能：
  - 在 Windows 本地双击运行
  - 也能在 Mac 上开服务，通过 Tailscale 给 Windows 浏览器访问

## 6.2 为什么不推荐继续用 Next.js 复刻

- 当前站点虽然是 Next 产物，但业务本质并不依赖 SSR。
- 你目标里最重要的是：
  - 本地运行
  - Windows 端免环境
  - 后续可打包
- Vite 更轻，更适合：
  - 静态前端
  - 桌面壳
  - 被 Go 服务内嵌

## 6.3 为什么服务端建议用 Go 而不是 Node

- Node 在开发很舒服，但“给 Windows 用户无环境运行”不如 Go 干净。
- Go 的优势：
  - 单文件交付
  - 跨平台编译稳定
  - 内嵌静态资源容易
  - SQLite 配套成熟

## 7. 建议的系统架构

## 7.1 分层设计

### 前端层

- `GamePage`
- `AddWordsDrawer`
- `ImportHistoryDrawer`
- `GameHistoryDrawer`
- `DictionaryPage`
- `SetupBanner`
- `HelpDrawer`

### 领域层

- `GameEngine`
- `PackService`
- `DictionaryService`
- `HistoryService`
- `AudioService`
- `PronunciationService`
- `SearchService`

### 存储层

- `dictionary_words`
- `word_packs`
- `pack_words`
- `game_history`
- `app_settings`
- `setup_state`

## 7.2 推荐数据库表

### dictionary_words

- `id`
- `word`
- `word_lower`
- `chinese`
- `chinese_pos`
- `phonetic_us`
- `phonetic_uk`
- `pinyin`
- `source`
- `updated_at`

### word_packs

- `id`
- `name`
- `source`
- `created_at`
- `updated_at`
- `is_active`

### pack_words

- `id`
- `pack_id`
- `en`
- `zh`
- `sort_index`

### game_history

- `id`
- `pack_id`
- `mode`
- `difficulty`
- `display_order`
- `matched_count`
- `total_count`
- `duration_seconds`
- `completed_at`

### app_settings

- `sound_enabled`
- `pronunciation_enabled`
- `display_order`
- `difficulty`
- `hint_enabled`

## 8. 复现时的功能实现策略

## 8.1 游戏引擎

- 普通模式：
  - 从当前词包生成中英气泡
  - 打乱顺序
  - 点击两项后比对
  - 成功播放成功音效
  - 失败播放失败音效
- 多词模式：
  - 输入若干词
  - 支持拆分
  - 生成临时匹配局
  - 返回普通模式后不污染常规词包

## 8.2 搜索与拼音

- 英文搜索：前缀 + 模糊
- 中文搜索：直接匹配
- 拼音搜索：
  - 预生成中文拼音字段
  - 支持全拼和无空格检索

## 8.3 新增单词 / 文本抽取

- 支持输入：
  - `apple=苹果`
  - `apple 苹果`
  - `apple - 苹果`
  - 一篇英文文章
- 抽取策略：
  - 先识别结构化输入
  - 再回退到词典查词补全
  - 进入预览表格后二次编辑

## 8.4 导入记录

- 支持导入/导出 JSON
- 保留兼容当前线上站点的多种字段命名
- 每次“导入词库”都落成一组 pack
- 可改名、删除、清空、激活开始游戏

## 8.5 字典更新

- 保留远程 `latest.json` 机制
- 本地保存当前 `datasetVersion`
- `检查更新` 只比版本
- `更新字典` 才真正下载覆盖

## 9. Windows 使用方案

## 9.1 首选方案：单文件程序

交付一个 Windows 可执行文件：

- 双击启动本地服务
- 自动打开默认浏览器
- 数据保存在本地 SQLite
- 不需要安装开发环境

这是我最推荐的落地方式。

## 9.2 备选方案：Mac 部署 + Tailscale

如果你不想给 Windows 发本地程序，就用同一个 Go 程序部署在 Mac 上：

- Mac 运行服务
- SQLite 放在 Mac
- Windows 通过 Tailscale 访问
- 浏览器直接打开即可

### 这种方案的优点

- Windows 彻底零环境
- 数据天然集中
- 方便多设备共用同一套字典/历史/导入记录

### 这种方案的缺点

- Mac 必须在线
- 依赖 Tailscale 网络可达

## 10. 颜色 bug 的修复方案

## 10.1 现有问题

- 当前线上气泡的中英文配对颜色一致。
- 用户会直接通过颜色猜出配对关系，破坏玩法。

## 10.2 正确修复方式

不要再用“按配对词绑定同一颜色”的策略。

改成：

- 所有气泡单独分配颜色
- 中英文两端颜色 **不建立一一对应关系**
- 每局重新洗牌颜色顺序
- 可加一个约束：
  - 同屏相邻不要过多重复色
  - 但不要让颜色和语言类型形成稳定规律

## 10.3 推荐实现

- 准备 6 到 8 组气泡渐变主题。
- 每轮生成后：
  - 先把所有气泡打乱
  - 再对气泡列表做颜色池轮转分配
  - 不按 pairId 上色

伪规则：

- `tile.color = shuffledPalette[index % palette.length]`
- 不要 `tile.color = pair.color`

## 11. 开发优先级建议

### Phase 1：先做可玩闭环

- 普通模式
- 词包加载
- 搜索
- 音效
- 显示顺序
- 简单/困难模式入口

### Phase 2：补管理功能

- 新增单词
- 导入记录
- 游戏历史
- 字典配置

### Phase 3：补自动化能力

- 一键配置
- 远程字典更新
- 远程模板兜底
- 多词模式

### Phase 4：交付与部署

- Windows 单文件打包
- Mac 服务模式
- Tailscale 访问

## 12. 最终推荐决策

如果你要我现在就定方案，我建议：

- **业务实现方案**：`React + TS + Vite + Zustand + Tailwind + Go + SQLite`
- **交付主方案**：Windows 单文件本地运行
- **交付备选**：Mac 开服务，Windows 通过 Tailscale 浏览器访问
- **颜色 bug 修复**：颜色分配从“按配对”改为“按气泡随机”

这样做的好处是：

- 开发体验对 Mac 友好
- Windows 端不需要装环境
- 同一套代码可以同时支持本地运行和远程访问
- 后续如果你想再加账号、云同步、多人共用，也能平滑演进
