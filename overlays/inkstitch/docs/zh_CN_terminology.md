# Ink/Stitch 简体中文术语规则

本文档记录本地预览版的简体中文术语标准。后续修改界面、菜单、tooltip、导出格式、参数面板和说明文本时，优先遵守这里的术语。

## 核心原则

- 以刺绣软件语境优先，不按英文逐字直译。
- 同一英文概念在同一功能域内保持同一译法。
- 与 Inkscape 通用矢量术语冲突时，按上下文区分：`Stroke` 作为矢量属性译为“描边”，作为 Ink/Stitch 针法入口时避免误译成“轮廓线”。
- 本地预览版允许覆盖官方 `zh_CN` 中已存在但不专业或不一致的译文。
- 不改变算法、文件格式、针迹生成语义，只修正用户可见文案。

## 推荐术语表

| English | 简体中文 | 说明 |
| --- | --- | --- |
| Params / Embroidery Params | 刺绣参数 | 指 Ink/Stitch 参数窗口或参数命令。 |
| Satin stitch | 缎纹针迹 | 不使用“缎面针迹”。 |
| Satin column | 缎纹柱 | 不使用“缎面柱”“缎面立柱”。 |
| AutoSatin | 自动缎纹 | 指自动生成/布线缎纹柱的功能。 |
| Running stitch | 平针 | 不译为“描边针迹”。 |
| Bean stitch | 豆形针 | 用于 repeated/backtracking running stitch 语境。 |
| Fill stitch / FillStitch | 填充针迹 | 参数页可简称“填充针迹”，避免只写“填针”造成歧义。 |
| Auto Fill | 自动填充 | 填充针迹方法。 |
| Tatami | 榻榻米填充 | 不使用“他他米”。 |
| Legacy Fill | 旧版填充 | 指旧算法，不是 Tatami。 |
| Guided Fill | 引导填充 | 不使用“导向填充”。 |
| Contour Fill | 轮廓填充 | 沿轮廓方向生成填充。 |
| Meander Fill | 蜿蜒填充 | 指 meander 图案填充。 |
| Tartan Fill | 格纹填充 | 不译为“方格花纹”。 |
| Ripple Stitch | 波纹针迹 | 不译为“螺旋针”。 |
| Underlay | 底针 | 可按语境写“填充底针”“轮廓底针”“中心走线底针”。 |
| Underpath | 底走线 | 指区域间移动时隐藏在形状内部的行走针迹，不等同于 `Underlay`。 |
| Pull compensation | 收缩补偿 | 指补偿布料被线迹拉窄。 |
| Lock stitch | 锁针 | 用于锁线/防脱线语境。 |
| Tack stitch | 加固针 | 用于起止端加固或固定语境。 |
| Trim | 剪线 | 不使用“修剪线”。 |
| Jump stitch | 跳针 | 保持不变。 |
| Stop command | 停止命令 / 停针 | 按按钮或参数标签选择短译。 |
| Needle point | 落针点 | 不使用“针点”。 |
| Stitch Plan | 针迹方案 | 指生成后的针迹数据/对象。 |
| Stitch Plan Preview | 针迹方案预览 | 指可视化预览入口。 |
| Rails | 轨道 | Satin column 两侧边界。 |
| Rungs | 横档 | 连接两条轨道的横向基准线。 |
| Frame Out position | 移框位置 | 指暂停/停止后针头或绣框移动到安全位置。 |

## 审校清单

- 参数标签应短、可扫读；tooltip 负责解释完整语义。
- 下拉选项优先用刺绣行业常用词，不用音译或硬直译。
- 同一页中不得混用“缎面/缎纹”“底层/底针”“描边针迹/平针”。
- 文件格式名称保留品牌和格式英文，如 `Tajima DST`、`Brother PES`。
- `PNG` 等通用图像格式可译为“PNG 图像”，不使用生硬全称“便携式网络图形”。
- 修正翻译后需要同步预览包，并检查 `LANGUAGE=zh_CN` 下关键字符串是否被本地术语覆盖。
