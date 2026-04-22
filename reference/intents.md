# Intent Triggers (Multilingual)

All intents match via semantic similarity. English is reference.

## recommend
- en: recommend, suggest, discover, what should I install
- zh: 推荐技能, 有什么好技能
- de: empfehle, was soll ich installieren

## search
- en: search, find, look for
- zh: 搜索, 查找

## privacy
- en: privacy, redact, delete my data, forget me
- zh: 隐私, 数据保护

## persona/report
- en: analyze me, my persona, roast me
- zh: 分析我, 我的人格

## security
- en: is X safe, security score, trust
- zh: 安全吗, 安全评分

## bundle
- en: bundle, pack, workflow pack
- zh: 套装, 技能包

## workflow
- en: workflow, routine, skill chain
- zh: 工作流, 常用组合

## clean
- en: clean, zombies, unused
- zh: 清理, 僵尸技能

## cost/savings
- en: cost, save money, budget
- zh: 省钱, 成本

## Fallback (Semantic Matching)

If no keyword matches, use context:
- "帮我选" → recommend (selection)
- "省钱" → recommend (cost context)