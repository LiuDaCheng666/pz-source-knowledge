# 功能领域索引

知识库按原版证据来源组织，不把反编译推断当成官方源码。

| 领域 | 原版 Lua 入口 | Java 重点包/类型 |
|---|---|---|
| 网络同步 | `media/lua/client`、`media/lua/server` | `zombie.network`、`zombie.core.raknet` |
| 背包与容器 | TimedActions、ISInventoryPane | `zombie.inventory` |
| 车辆 | Vehicles UI、TimedActions | `zombie.vehicles` |
| 安全屋与世界对象 | SafeHouse UI、BuildingObjects | `zombie.iso.areas.SafeHouse`、`zombie.iso` |
| 伤势与医疗 | HealthPanel、HealthPanelAction | `zombie.characters.BodyDamage` |
| 僵尸与生成 | Zombie、Spawn、Meta | `zombie.characters.IsoZombie`、`zombie.popman` |
| TimedAction | `media/lua/shared/TimedActions` | `zombie.characters.CharacterTimedActions` |
| 物品与配方 | `media/scripts` | `zombie.scripting` |

每项开发工作应先读取 `current.json` 确认 Build，再查询相关符号、事件和实现。结论应记录文件路径、行号、Build ID 和 JAR 哈希。
