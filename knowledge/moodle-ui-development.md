# Build 42 Moodle UI 开发与兼容指南

本文面向需要在 Project Zomboid Build 42 右侧状态栏增加图标的 Mod 作者。重点不是绘制一个方块，而是确保原版 Moodle、注册型自定义 Moodle 和独立 UI 状态同时存在时不会重叠、串 Tooltip 或因动画产生瞬时覆盖。

## 适用基线

- Game Build ID：`24909836`
- Snapshot ID：`build-24909836-80e405a4bfc4-1ddb73078ab8`
- JAR SHA-256：`80e405a4bfc42f6072e75b3735f458a6514143da011d3226007ded305a442f44`

主要证据：

- `zombie/ui/MoodlesUI.java`
- `zombie/ui/MoodleTextureSet.java`
- `zombie/ui/UIManager.java`
- `zombie/characters/Moodles/Moodles.java`
- `zombie/scripting/objects/MoodleType.java`
- `bytecode/java-api.txt`

CFR 文件是用于阅读的重建实现；Java 字节码签名与描述符才是 API 存在性的权威证据。游戏 Build 变化后必须重新复核本文列出的字段、公式和生命周期。

## 先区分两种实现

### 注册为原版 MoodleType

Build 42 提供 `MoodleType.register(String)`，注册结果进入 `Registries.MOODLE_TYPE`。但注册成功不等于已经完整接入原版 UI：

- `Moodles` 构造时只为当时注册表中的类型创建状态对象。
- `MoodlesUI` 构造时只为当时注册表中的类型创建 `MoodleUIData`。
- `MoodleTextureSet` 的图标表在 Java 构造函数中明确列出原版类型，没有按注册表自动加载新类型的纹理。
- 原版名称和说明按 `Moodles_<translationName>_lvlN` 与 `Moodles_<translationName>_desc_lvlN` 查找。

因此，运行期较晚注册可能遇到状态对象缺失、UI 数据缺失或图标为空。只有在确认注册时机、纹理接入和翻译路径都成立时，才应选择这一方案。

### 独立 UI 控件模拟 Moodle

另一种做法是创建 `ISUIElement` 或 `ISButton`，使用原版 Moodle 背景、边框、尺寸和右侧列位置自行绘制。它更容易承载倒计时、点击、徽标和自定义 Tooltip，但它不属于原版 `MoodlesUI`：

- 不会进入 `MoodlesUI.moodleUiState`。
- 不会增加原版 `numUsedSlots`。
- 原版不会替它安排位置或处理重排动画。
- 多个 Mod 若都把自己放在“原版最后一格之后”，就会占用同一坐标。

本文后续的兼容算法主要解决独立 UI 控件的共存问题。

## 原版布局机制

### 锚点与尺寸

`UIManager` 每帧把原版状态栏放到当前玩家视口右侧：

```text
x = viewportWidth - (10 + moodleWidth)
```

单人常见起始 `y` 为时钟下方；分屏时会按玩家视口调整。不要写死 `x = screenWidth - 58` 或 `y = 120`，应读取当前玩家的 `UIManager.getMoodleUI(playerNum)`：

```lua
local playerNum = player:getPlayerNum()
local moodleUI = UIManager.getMoodleUI(playerNum)
local x = moodleUI:getAbsoluteX()
local y = moodleUI:getAbsoluteY()
local size = moodleUI:getWidth()
```

原版支持的纹理尺寸为 `32/48/64/80/96/128`。槽位垂直距离为：

```text
moodleDistY = moodleWidth + 10
```

第 `n` 个槽位的目标位置为：

```text
targetY = moodleY + n * (moodleWidth + 10)
```

### 可见槽位统计

原版遍历 `Registries.MOODLE_TYPE.values()`，通常把等级大于 `0` 的状态计为可见槽位。`FOOD_EATEN` 是例外：其等级低于 `HighMoodleLevel`，即数值小于 `3` 时不显示，也不占槽。

不要用写死的 Moodle 枚举表统计。Build 更新或其他 Mod 注册新 `MoodleType` 后，写死表会漏算。

### 入场和重排动画

新状态出现时，原版不是立即放到最终位置：

```text
slotsDesiredPos = moodleDistY * currentSlotPlace
slotsPos = slotsDesiredPos + 500
slotsPos += (slotsDesiredPos - slotsPos) * 0.15
```

当当前位置与目标位置相差不超过约 `0.8px` 时，才吸附到目标位置。

这意味着独立 UI 即使算对最终槽位，如果立即显示，原版图标仍可能从下方穿过它。在穿越期间，两套控件会短暂重叠，鼠标悬停可能显示错误状态文字。

### 鼠标命中

原版按下式计算鼠标所在槽位：

```text
mouseOverSlot = (MouseY - moodleUI.y) / moodleDistY
```

然后用渲染顺序匹配 Tooltip。独立 UI 控件若覆盖原版区域，会同时接收鼠标事件。典型症状是：

- 看到的是自定义图标，文字却属于原版最后一个状态。
- 鼠标轻微移动后 Tooltip 在两个状态之间跳变。
- 最后一个原版图标像是被替换，实际是两个控件同坐标绘制。

## `numUsedSlots` 的边界

Build 24909836 中 `numUsedSlots` 是 `MoodlesUI` 的私有字段，没有稳定公开 getter。它只统计 `moodleUiState` 中原版 UI 已知且当前可见的项目。

因此：

- 不要把直接读取 `moodleUI.numUsedSlots` 当作唯一方案。
- 某些 Lua 桥接或 UI 替换可能暴露该字段或自定义 getter，但这只是兼容信息。
- 即使能读到，它仍不包含其他 Mod 独立绘制的状态。
- 安全策略是动态统计角色的已注册 Moodle，并与可选的暴露值取较大值。

```text
vanillaSlots = max(dynamicRegistryCount, exposedSlotCount or 0)
occupiedSlots = vanillaSlots + externalIndependentSlots
```

## 重叠事故的根因

最常见的错误实现是：

```text
customY = moodleY + numUsedSlots * spacing
```

当另一个 Mod 已经在原版列末尾独立绘制状态时，它没有增加 `numUsedSlots`。两个 Mod 都得到同一个“下一格”，于是发生永久重叠。

第二类错误是只在初始化时算一次位置。原版状态会随饥饿、受伤、疲劳等实时增减，窗口尺寸、Moodle 尺寸和分屏状态也会变化。位置必须在客户端更新过程中重新计算。

第三类错误是位置变化后立即显示。原版有 500px 入场位移，独立图标需要给原版动画留下稳定时间。

## 推荐的兼容协议

同一客户端最好只有一个“独立 Moodle 列管理器”。各功能或各 Mod 向管理器登记状态，而不是各自创建一套右侧控件。

管理器至少应提供：

```lua
StatusColumn.set(namespaceId, {
    active = true,
    priority = 100,
    iconPath = "media/ui/example.png",
    tooltip = "状态说明",
    badge = "2/4",
})

StatusColumn.remove(namespaceId)
StatusColumn.getActiveCount()
StatusColumn.getLayoutSnapshot()
```

兼容约定：

1. `namespaceId` 必须包含 Mod 命名空间，避免不同 Mod 使用相同 ID。
2. `priority` 只决定独立状态之间的顺序，不得插入原版槽位中间。
3. 管理器统一负责尺寸、锚点、动画、鼠标和 Tooltip。
4. 状态提供方只提交本地显示数据，不自行修改其他控件坐标。
5. 若无法共用管理器，后绘制方必须通过明确的 provider/adapter 统计前方独立状态，不能猜测其内部表结构。
6. 不要扫描全部 UI 控件并按纹理或类名猜状态数量；这既脆弱又容易把隐藏控件计入。

一个简单的 provider 协议可以是：

```lua
ExternalMoodleSlots = ExternalMoodleSlots or {}

ExternalMoodleSlots["example.mod"] = function(playerNum)
    -- 只返回当前真实可见、已占用右侧列的数量。
    return 2
end
```

列管理器对每个 provider 使用 `pcall`，只接受非负有限整数，并在 provider 异常时忽略该项。正式项目还应避免同一批状态被两个 provider 重复计数。

## 通用 Lua 参考实现

以下代码只展示布局核心，不包含具体 Mod 状态和网络逻辑：

```lua
local function call(target, method, ...)
    if not target then return nil end
    local okMethod, fn = pcall(function() return target[method] end)
    if not okMethod or type(fn) ~= "function" then return nil end
    local args = { ... }
    local ok, value = pcall(function() return fn(target, unpack(args)) end)
    return ok and value or nil
end

local function countRegisteredMoodles(player)
    local moodles = call(player, "getMoodles")
    local registry = Registries and Registries.MOODLE_TYPE
    local values = registry and call(registry, "values")
    local size = values and tonumber(call(values, "size"))
    if not moodles or not size then return 0 end

    local count = 0
    for index = 0, size - 1 do
        local moodleType = call(values, "get", index)
        local level = moodleType and tonumber(call(moodles, "getMoodleLevel", moodleType)) or 0
        if moodleType == MoodleType.FOOD_EATEN then
            if level >= 3 then count = count + 1 end
        elseif level > 0 then
            count = count + 1
        end
    end
    return count
end

local function exposedSlotCount(moodleUI)
    for _, getter in ipairs({ "getNumUsedSlots", "getUsedSlotCount", "getMoodleCount" }) do
        local value = tonumber(call(moodleUI, getter))
        if value and value >= 0 then return math.floor(value) end
    end
    local ok, value = pcall(function() return tonumber(moodleUI.numUsedSlots) end)
    if ok and value and value >= 0 then return math.floor(value) end
    return nil
end

local function externalSlotCount(playerNum)
    local total = 0
    for _, provider in pairs(ExternalMoodleSlots or {}) do
        if type(provider) == "function" then
            local ok, value = pcall(provider, playerNum)
            value = ok and tonumber(value) or nil
            if value and value >= 0 and value < math.huge then
                total = total + math.floor(value)
            end
        end
    end
    return total
end

local function layout(control, localCustomIndex)
    local player = getPlayer()
    if not player then control:setVisible(false); return end

    local playerNum = player:getPlayerNum()
    local moodleUI = UIManager.getMoodleUI(playerNum)
    if not moodleUI or moodleUI:isVisible() == false then
        control:setVisible(false)
        return
    end

    local size = tonumber(moodleUI:getWidth()) or 48
    local counted = countRegisteredMoodles(player)
    local exposed = exposedSlotCount(moodleUI) or 0
    local occupied = math.max(counted, exposed) + externalSlotCount(playerNum)

    control:setWidth(size)
    control:setHeight(size)
    control:setX(moodleUI:getAbsoluteX())
    control:setY(moodleUI:getAbsoluteY() + (occupied + localCustomIndex) * (size + 10))
end
```

这段代码仍需配合“布局稳定等待”和管理器内部的去重，否则 provider 数量变化时仍可能出现瞬时穿越。

## 布局稳定等待

检测到基础槽位总数变化后，建议暂时隐藏独立状态，等待原版重排结束。Build 24909836 的经验值可以是约 `1.4秒`，并同时保留约 `50帧` 作为无可靠时钟时的兜底。

不要只依赖固定帧数：低帧率机器上 50 帧可能远超过 1.4 秒，高帧率机器上又可能过短。实际实现可采用“时间或帧数任一仍未结束就继续等待”的保守策略，或者直接跟踪原版槽位位置是否稳定。

独立状态自身也可沿用原版视觉节奏：

```text
currentY = targetY + max(180, iconHeight * 5)
currentY += (targetY - currentY) * min(0.75, 0.15 * frameFraction)
abs(currentY - targetY) <= 0.8 时吸附
```

所有动画应以渲染耗时或时间戳驱动，不能假设固定 FPS。

## Tooltip 与鼠标所有权

每个独立状态只处理自己矩形内的鼠标事件。推荐使用一个真实的 `ISUIElement`/`ISButton` 对应一个状态，并让管理器设置其最终位置。

不要：

- 在全屏透明控件上统一接管鼠标。
- 覆盖原版 `MoodlesUI.onMouseMove()`。
- 让隐藏状态继续保留可点击区域。
- 在 `render()` 中临时改变坐标，而命中测试仍使用旧坐标。
- 让两套控件共享同一格，再试图通过绘制顺序解决 Tooltip。

图标隐藏时必须同时 `setVisible(false)`；仅把 alpha 设为 0 可能仍会保留输入命中。

## 异构数据防护

兼容其他状态框架时，不要假设其表中每一项都是 Moodle 对象。实际表可能混入字符串、数字、配置项或占位符。调用 `getLevel()` 前必须检查类型并使用 `pcall`：

```lua
local function countVisibleEntries(entries)
    if type(entries) ~= "table" then return 0 end
    local count = 0
    for _, value in pairs(entries) do
        local valueType = type(value)
        local level = valueType == "table" and tonumber(value.Level) or nil
        if level == nil and (valueType == "table" or valueType == "userdata") then
            level = tonumber(call(value, "getLevel"))
        end
        if level and level > 0 then count = count + 1 end
    end
    return count
end
```

适配器应放在消费方自己的仓库中，并按依赖版本测试；不要把第三方 Mod 数据结构写入原版知识库。

## 网络与性能原则

Moodle 绘制本身应是纯客户端行为：

- 已存在于客户端的状态直接本地读取和排版。
- 不要在 `OnRenderTick`、`OnTick` 或每帧 `update()` 中发送网络请求。
- 服务端状态变化时使用已有定向状态包或低频增量包更新本地缓存。
- Tooltip 文本、换行结果、物品定义和纹理应缓存，不要每帧重新查询脚本管理器。
- 只在状态、尺寸、语言或布局槽位变化时重建昂贵内容。

为了兼容而额外统计本地表，不需要任何全服广播。

## 测试矩阵

至少覆盖以下场景：

| 场景 | 验收结果 |
|---|---|
| 无原版状态 | 第一个自定义状态位于原版起点 |
| 多个原版状态 | 自定义状态位于最后一个原版状态之后 |
| `FOOD_EATEN` 等级 1/2 | 不占原版槽位 |
| `FOOD_EATEN` 等级 3/4 | 正确占用一个槽位 |
| 注册型第三方 Moodle | 动态注册表统计后不重叠 |
| 独立 UI 第三方状态 | provider 或共享管理器统计后不重叠 |
| 原版状态突然出现 | 入场动画期间无穿越、无串 Tooltip |
| 原版状态消失 | 独立状态平滑上移且命中区同步 |
| 两个以上自定义状态 | 顺序稳定，ID 和优先级不冲突 |
| 切换 Moodle 尺寸 | 图标、间距、背景和边框同步缩放 |
| 分屏玩家 | 使用各自 playerNum 和视口锚点 |
| 隐藏全部 UI | 自定义状态同时隐藏 |
| 低 FPS/高 FPS | 动画时间基本一致，不急停或漂移 |
| 鼠标逐格悬停 | 图标、标题、说明严格对应 |
| 存档退出重进 | 状态按权威数据恢复，不残留旧控件 |

自动化测试至少应模拟：动态注册表、私有槽位不可读、暴露槽位高于动态计数、外部表混入非对象项、基础槽位变化后的等待期、多个自定义状态排序与隐藏。

## 更新后的复核清单

游戏更新后重新检查：

1. `UIManager.getMoodleUI` 是否仍存在，参数和返回类型是否变化。
2. `MoodlesUI` 的尺寸来源、右侧边距和垂直间距是否变化。
3. `numUsedSlots` 是否仍为私有字段，是否新增公开 getter。
4. 原版可见规则，尤其 `FOOD_EATEN` 阈值是否变化。
5. 入场初始偏移、插值系数和吸附阈值是否变化。
6. `MoodleType.register`、注册表和构造时机是否变化。
7. `MoodleTextureSet` 是否开始支持动态类型纹理。
8. 分屏和 UI 缩放下的锚点是否变化。
9. 已适配的独立状态框架是否改变数据结构或生命周期。
10. 全部兼容矩阵和鼠标命中测试是否通过。

不能因为旧 Build 的实现曾经可用，就假设字段访问、注册时机和布局常量在新 Build 中保持不变。
