# Translate 流式位移诊断记录

## 结论

已定位根因并完成渲染器替换：旧 `SwiftStreamingMarkdown` 在每次流式替换文本后调用 `invalidateIntrinsicContentSize()`，在 macOS 27 上会让 AppKit 视图几何与绘制层失配，表现为视图不动、实际译文持续下移。

当前已替换为 `Lakr233/MarkdownView`，它是纯 AppKit 流式渲染器，内部为 LLM token 更新做了节流与视图复用。应用侧通过自有 `NSViewRepresentable` 消费完整快照，并保留 AppKit 层几何回归测试。

改动：

- `Package.swift` / `Package.resolved`：移除 `SwiftStreamingMarkdown`，接入 `MarkdownView` 4.3.2 和 `MarkdownParser`。
- `Sources/Yagraker/MarkdownStreamSource.swift`：改为 Lakr233 AppKit 流式渲染，并应用 Yagraker 主题。
- `Sources/Yagraker/PopupView.swift`：流式和完成状态共用该 AppKit 渲染器，避免完成时换引擎。
- `Tests/YagrakerUITests/YagrakerUITests.swift`：保留层几何回归测试，连续流式追加时断言绘制层相对窗口顶部不变。
- `Sources/Yagraker/TranslationLayoutProbe.swift`：可选运行期探针，默认关闭。

验证：`swift test` 已通过（UI 39 项、Core 52 项）。测试期间出现过一次无关窗口拖动测试失败，重新全量运行已通过。

## 开启和采集

先正常退出旧的 Yagraker，确保复现的是本次构建。在仓库目录启动：

```sh
CONFIGURATION=debug DIST_DIR="$PWD/.build/layout-debug-app" bash Scripts/build-app.sh
/usr/bin/open -n --env YAGRAKER_DEBUG_TRANSLATION_LAYOUT=1 "$PWD/.build/layout-debug-app/Yagraker.app"
```

构建使用项目配置的稳定签名身份，不覆盖 `dist`。不要只用 `swift run`：本机 macOS 27 上裸可执行文件启动后，已观察到 `AppKit:StatusBar scene activation failed` / `BSServiceConnectionErrorDomain Code=3` 每秒重试，进程存活却没有菜单栏图标。改用带 Info.plist 和签名的 `.app` 经 LaunchServices 启动；`open --env` 显式传入探针开关（普通 shell 环境前缀不保证传给应用）。

另一个终端**先开始监听，再执行翻译**：

```sh
/usr/bin/log stream --style compact --level info --predicate 'subsystem == "Yagraker" AND category == "TranslationLayout"'
```

最近记录也可查询（info 历史记录是否保留由系统决定，优先实时监听）：

```sh
/usr/bin/log show --last 5m --style compact --info --predicate 'subsystem == "Yagraker" AND category == "TranslationLayout"'
```

不要贴 API key 或网络请求内容。关闭时退出本次进程，按平常方式重新启动即可，无持久化设置。

## 探针契约

- `Sources/Yagraker/TranslationLayoutProbe.swift`，在 `PopupView` 的结果区域背景挂载；translation/deep read 流式和完成状态均可观察。
- 默认关闭。开启时每 100ms 读取当前布局，仅数据改变才输出；不主动 layout、不把几何值写回 SwiftUI、不拦截鼠标。
- 只读当前窗口的几何数据、视图标识、UTF-16 长度、stream UUID、阶段和绘制层坐标，不记录原文/译文/凭证。
- 最多记录 24 个文本视图和 24 个滚动容器；长 Markdown 后续块可能不在采样范围。100ms 以下的瞬态或纯绘制动画不保证捕获。
- 视图移除后释放计时器。结果仍显示时继续观察完成后的布局变化。
- `[DEBUG-translate-layout]` 按 `stream` + `seq` 关联一次采样。summary/text/scroll/rendering 分行，避免 unified log 截断大 JSON。

## 如何读日志

所有矩形为 `[x, y, width, height]`，单位 pt；`windowRect` 使用 AppKit 窗口坐标（Y 向上），`frame` 使用各自父视图坐标，不能直接跨视图比较。

- `summary.resultTopFromWindowTop` 增大：结果区域相对窗口顶部下移。
- `summary.panelFrame`：区分窗口自身移动/缩放与窗口内部位移；屏幕上的结果顶部为 `panelFrame.y + resultWindowRect.y + resultWindowRect.height`。
- `text.role=source` 的 `heightLimits` 与对应 source scroll 的 `windowRect.height`：检查原文区域是否随窗口预算变高，挤压译文。
- `scroll.clipBounds.y`：区分滚动偏移变化；原文编辑器自身的滚动不等于外层滚动。
- `rendering.type=firstLine` 的 `lineTopFromWindowTop` 变化：译文首行实际绘制位置变化。
- `rendering.type=layer` 的 `frameDelta`/`positionDelta`：绘制层与模型层是否不一致。
- 同一 `stream` 内 `id` 改变：视图可能重建；切换到 done 时更换 Markdown 渲染器属于现有行为。

## 自动反馈循环

```sh
swift test --filter YagrakerUITests.testTranslationStreamKeepsFirstLineStationary
YAGRAKER_DEBUG_TRANSLATION_LAYOUT=1 swift test --filter YagrakerUITests.testTranslationStreamKeepsFirstLineStationary
```

测试使用真实 PopupView/ToolPanelModel/Markdown 渲染链、合成 LLM 服务，不请求外部 API。长原文 + 短译文起步，再连续追加 8 段同段落文本，确认内容已被消费，断言绘制层相对窗口顶部保持在 2pt 内。修复前该断言失败，修复后通过。

诊断完成后移除临时探针及 PopupView 挂载点，保留有效回归测试。
