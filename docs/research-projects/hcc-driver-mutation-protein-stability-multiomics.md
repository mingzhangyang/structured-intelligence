# 肝细胞癌驱动基因错义突变的蛋白稳定性后果与多组学整合分析

TCGA-LIHC Driver-Gene Missense Mutations: Protein-Stability Consequences and Multi-Omics Integration

**状态**: 研究计划（待启动）
**版本**: v1.0
**日期**: 2026-05-17

---

## 一、课题定位与差异化

### 科学背景

肝细胞癌（hepatocellular carcinoma, HCC）是全球癌症死因前三的肿瘤，TCGA-LIHC 队列在过去十年提供了配对的 WXS、RNA-seq 与临床数据。该队列中已识别的高频驱动基因包括 *TP53*、*CTNNB1*、*AXIN1*、*ARID1A*、*ARID2*、*KEAP1*、*NFE2L2*、*RB1*。其中绝大多数为**错义突变**（missense），但目前临床报告仍将所有错义变异等价为「mutation present / absent」二元状态。

错义突变对蛋白功能的影响不是开关式的：不同氨基酸取代会以不同程度破坏蛋白折叠稳定性、配体结合或亚基界面。最近一系列实验（例如 Giacomelli 2018 *Nat Genet* 对 *TP53* 的饱和突变扫描）和计算预测（FoldX、Rosetta、AlphaMissense）表明，**ΔΔG（突变体相对野生型的折叠自由能变化）与表型严重程度呈剂量关系**。但这些工作多数局限于单一基因（典型是 *TP53*），且少有研究在同一临床队列中把 ΔΔG 链接到下游转录组与生存。

### 科学问题

> 在 TCGA-LIHC 队列中，**观察到的驱动基因错义突变所引起的蛋白稳定性破坏程度（ΔΔG）**，能否解释下游转录组重编程的幅度，并比二元突变状态更准确地预测患者生存？

### 三个子问题

1. **稳定性量化**：每个驱动基因上观察到的错义突变中，哪些显著破坏蛋白稳定性（|ΔΔG| > 2 kcal/mol）？这些位点是否聚集在已知功能结构域？
2. **剂量-反应**：在突变携带者中，蛋白稳定性破坏程度是否与该基因下游通路的转录扰动幅度成正相关？
3. **生存预测**：用 ΔΔG 加权的「功能负荷分数」取代二元突变状态，是否提升 Cox 模型对总生存（OS）的预测性能？

### 与现有工作的差异化

| 现有工作 | 本研究的差异 |
|----------|-------------|
| TCGA PanCanAtlas (Bailey 2018 *Cell*)：泛癌驱动基因目录 | 不再做新的驱动基因发现，而是把已知驱动突变按 ΔΔG 加权重新分层 |
| Giacomelli 2018 *Nat Genet*：*TP53* 饱和突变扫描 | 将单基因的功能-后果范式扩展到 HCC 的 ≥7 个驱动基因，且不依赖额外实验 |
| AlphaMissense (Cheng 2023 *Science*)：泛蛋白错义变异致病性 | 不预测"致病/良性"二分类，而是直接用 ΔΔG 连续值进入下游建模 |
| cBioPortal 常规分析：突变 vs 表达/生存 | 用「ΔΔG 加权负荷」替代二元状态，验证连续量化是否提升预测 |
| 大量计算预测论文 | 在同一队列内闭环"突变 → ΔΔG → 转录组 → 生存"，提供端到端的多组学证据链 |

### 本研究的独特贡献

1. **闭环因果链**：在单一队列内同时回答"突变发生 → 蛋白稳定性 → 转录后果 → 临床后果"四个层级。
2. **结构域感知**：用 RPS-BLAST/CDD 把每个突变映射到结构域，分离"结构域内 ΔΔG"与"结构域外 ΔΔG"对下游的不同效应。
3. **贝叶斯效应量**：核心结论（ΔΔG 与通路扰动的剂量关系）以贝叶斯层级模型估计，报告后验分布而非单纯 p 值。
4. **工具链压力测试**：覆盖此前两个课题未涉及的 WGS/WES、批量 RNA-seq 与蛋白工程 skill 链路。

---

## 二、数据来源

### 主数据：TCGA-LIHC

| 数据类型 | 规模 | 来源 | 用途 |
|----------|------|------|------|
| WXS BAM（肿瘤+正常配对） | ~370 患者 × 2 | GDC Legacy / GDC Active | 体细胞变异调用 |
| GDC 已 call MAF（MuTect2 PoN） | ~370 患者 | GDC | 与本流程结果对比 |
| RNA-seq STAR counts | ~370 患者（含 ~50 配对正常） | GDC | 差异表达、通路扰动 |
| 临床（生存、分期、HBV/HCV、分化等级） | ~370 患者 | GDC | 协变量、生存终点 |

### 辅助数据

| 数据 | 来源 | 用途 |
|------|------|------|
| 蛋白序列与功能注释 | UniProt（reviewed/SwissProt） | WT 序列、活性位点注释 |
| 蛋白结构 | AlphaFold DB（首选）+ RCSB PDB（实验结构若有） | FoldX 评分输入 |
| CDD/Pfam 结构域 | NCBI CDD（通过 `rpsblast-assistant` 本地化） | 突变-结构域映射 |
| 亚洲 HCC 验证队列（可选） | GSA / ENA（如 ICGC-LIRI-JP） | 跨人群验证关键结论 |

### 数据量与下载策略

- TCGA-LIHC 全量 BAM 约 60 TB，不现实。**分层下载策略**：
  - **Tier 1（全量，~50 GB）**：GDC 已 call 的 MAF + STAR counts + 临床表。用于主分析。
  - **Tier 2（子集，~3 TB）**：抽取 30 例配对 WXS BAM（10 例高 ΔΔG / 10 例低 ΔΔG / 10 例 WT）做端到端工具链验证。
- 受控访问（dbGaP）问题：MAF 与 counts 多为开放数据；BAM 需 dbGaP 授权。在课题启动前由 PI 申请。

### 驱动基因焦点列表（v1）

依据 PanCanAtlas + COSMIC + LIHC 文献：

| 基因 | 功能 | LIHC 突变频率 | 关键结构域（CDD） |
|------|------|---------------|--------------------|
| *TP53* | 肿瘤抑制、DNA 损伤应答 | ~30% | P53 DNA-binding (cd08367) |
| *CTNNB1* | Wnt 信号 | ~25% | Armadillo repeats |
| *AXIN1* | Wnt 信号负调节 | ~10% | RGS, DIX |
| *ARID1A* | SWI/SNF 染色质重塑 | ~10% | ARID, BAF250-C |
| *ARID2* | SWI/SNF 染色质重塑 | ~5% | RFX-like, ZF |
| *KEAP1* | NRF2 通路 | ~5% | BTB, Kelch |
| *NFE2L2* (*NRF2*) | 氧化应激响应 | ~5% | bZIP |
| *RB1* | 细胞周期 | ~3% | RBP-like, A/B box |

---

## 三、研究流程

### 阶段 A：文献综合与假设构建

| 步骤 | Skill / Agent | 任务 | 产出 |
|------|--------------|------|------|
| A1 | `research` | 综述 ΔΔG 与表型关联的实验证据（TP53、KRAS、BRAF 的饱和突变研究） | 已验证的 ΔΔG-表型关系证据表 |
| A2 | `research` | 调研体细胞变异调用最佳实践（Mutect2 + PoN）、配对 vs 单样本调用、过滤策略 | 变异调用决策树 |
| A3 | `research` | 调研 FoldX / Rosetta / AlphaMissense 在 TCGA 队列的应用与局限 | 工具选择与误差预算文档 |
| A4 | `research` | 调研 TCGA-LIHC 数据访问规范、临床终点定义、随访截尾处理 | 数据使用与统计协议 |

### 阶段 B：环境与数据获取

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| B1 | `bioinformatics-env-setup` | conda 环境固化（GATK4、STAR、Salmon、FoldX、Scanpy/PyMC 等） | environment.yml + 锁文件 |
| B2 | `search-ncbi-datasets` | 锁定 GRCh38（GENCODE v44）参考基因组与注释版本 | 参考资产清单 |
| B3 | `download-gdc` | 下载 LIHC 全量 MAF、STAR counts、临床表（Tier 1） | 主分析数据集 |
| B4 | `download-gdc` | 下载 30 例配对 WXS BAM（Tier 2，需 dbGaP 授权） | 工具链验证数据集 |
| B5 | `search-ena` | 检索 ICGC-LIRI-JP 等亚洲 HCC 验证队列（可选） | 外部验证队列样本表 |
| B6 | `search-gsa` | 检索 NGDC GSA 中的中国 HCC 队列（可选） | 跨人群验证候选清单 |
| B7 | `ncbi-eutilities-assistant` | 查询 8 个驱动基因的 NCBI Gene / UniProt 记录，固化基因符号与转录本 | 基因/蛋白 ID 映射表（HGNC + UniProt + Ensembl） |

**检查点**：所有下载数据通过 MD5 校验；基因 ID 在 MAF、counts、UniProt 间无歧义。

### 阶段 C：变异调用与质控（Tier 2 子集）

由 `ngs-analysis-expert` agent 协调；目的是验证端到端工具链，并与 GDC MAF 交叉比对。

| 步骤 | Skill | 任务 | 关键参数 |
|------|-------|------|----------|
| C1 | `ngs-quality-control` | 30 例 WXS BAM 的 FastQC + MultiQC | 单端/双端、读长、Q30 |
| C2 | `ngs-read-preprocessing` | （从 BAM 反向提取 FASTQ 后）fastp 适配器/低质量过滤 | 默认 |
| C3 | `genome-read-alignment` | BWA-MEM2 比对 GRCh38 + MarkDuplicates | -K 100000000，标记重复 |
| C4 | `genome-alignment-qc` | mosdepth 覆盖度 + picard CollectHsMetrics | 外显子目标 BED |
| C5 | `genome-variant-calling` | GATK Mutect2 体细胞调用（配对模式） + PoN | 默认 PoN + GnomAD AF |
| C6 | `genome-variant-filtering` | FilterMutectCalls + 自定义 LIHC PASS 标准 | tumor LOD ≥ 6.3，AF ≥ 0.05 |
| C7 | `genome-variant-annotation` | VEP/SnpEff 注释 + 与 GDC MAF 比对 | 优先 canonical transcript |

**检查点**：30 例子集与 GDC MAF 的 PASS 错义变异一致率 > 85%；不一致变异分类记录原因（PoN 差异、AF 阈值差异、过滤差异）。

**Tier 1 主分析直接使用 GDC MAF**，跳过 C1–C7；Tier 2 仅用于工具链验证与一致性评估。

### 阶段 D：蛋白结构与稳定性分析

由 `ngs-analysis-expert` agent 与 `research` 协同；这是本课题的核心创新部分。

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| D1 | `rpsblast-assistant` | 对 8 个驱动基因 UniProt 序列做 CDD 注释，得到结构域边界 | 基因 → 结构域 → 位点范围表 |
| D2 | `predict-protein-heat-stability` (Path A) | 每个 WT 蛋白的基线热稳定性预测（sequence-only） | 蛋白基线稳定性参考 |
| D3 | `predict-protein-heat-stability` (Path C) | 对每个观察到的错义突变做 FoldX BuildModel + Stability：ΔΔG 估计 | 突变 → ΔΔG 表 |
| D4 | `design-thermostable-mutations` (反向用法) | 用 consensus_stability_rank 把多工具 ΔΔG 聚合为方向感知共识分数 | 多工具共识 ΔΔG |
| D5 | 自定义脚本 | 把 ΔΔG 映射回 MAF：为每位患者计算「功能负荷分数」FLS = Σ \|ΔΔG\| × allele fraction | 患者 × FLS 表 |

**关键工程细节**：
- 结构来源优先级：实验结构（RCSB）> AlphaFold（pLDDT > 70 区域）> 截断分析（pLDDT ≤ 70 的位点报告为"低置信度 ΔΔG"，不纳入主结论）。
- FoldX RepairPDB 在所有突变前对每个 WT 结构跑一次，作为后续 BuildModel 的统一基线。
- 同义/无义/移码不进入 ΔΔG 流程；无义/移码单独标记为「LoF」纳入下游对照。
- 反向用法说明：`design-thermostable-mutations` 的 consensus 模块本质是方向感知的 ΔΔG 聚合器，把"稳定化候选"反向用于"去稳定化筛查"完全符合工具能力。

### 阶段 E：转录组分析

由 `ngs-analysis-expert` agent 协调。Tier 1 主分析直接使用 GDC STAR counts；Tier 2 在 30 例子集上端到端重跑。

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| E1 | `rnaseq-read-alignment` | STAR two-pass 比对（Tier 2 子集） | 排序 BAM + SJ.out |
| E2 | `rnaseq-alignment-qc` | RSeQC + Qualimap | 比对率、5′/3′ 偏倚、链特异性 |
| E3 | `rnaseq-read-counting` | featureCounts 基因层计数 | 计数矩阵（与 GDC counts 比对） |
| E4 | `rnaseq-transcript-quantification` | Salmon 转录本层 TPM（用于跨样本归一） | TPM 矩阵 |
| E5 | `rnaseq-differential-expression` | DESeq2：分层比较 ①肿瘤 vs 配对正常 ②高 FLS vs 低 FLS（基因特异） ③突变携带 vs WT（基因特异） | DE 表 + MA/火山图 |
| E6 | `rnaseq-functional-enrichment` | clusterProfiler/fgsea：GO、KEGG、Hallmark | 富集表 + 网络图 |

**DE 分析设计要点**：
- 协变量：HBV/HCV 状态、性别、年龄分箱、肿瘤分化等级、批次（plate / TSS）。
- 配对正常仅 ~50 例，用 paired DE；剩余 ~320 例肿瘤做 unpaired tumor-only 分析。
- 高/低 FLS 分组：取该基因 FLS 分布的上四分位 vs WT（FLS = 0）患者，避免中间区段稀释信号。

### 阶段 F：统计建模与生存分析

由 `statistical-analysis-expert` agent 协调。这是把蛋白稳定性、表达、临床三层数据耦合起来的核心阶段。

#### F1. 数据质量与探索

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| F1.1 | `stat-assess-data-quality` | 检查 MAF、counts、临床表的缺失与不一致 | 数据质量报告 |
| F1.2 | `stat-analyze-distribution` | FLS 的分布形态（按基因分面） | 密度图 + 多峰性检验 |
| F1.3 | `stat-pca` | RNA-seq VST 表达谱 PCA：按 HBV/HCV、性别、分级着色 | 批次评估 |
| F1.4 | `stat-nonlinear-embedding` | UMAP 表达可视化 | 患者亚群初探 |

#### F2. ΔΔG-表达的剂量-反应关系（子问题 2）

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| F2.1 | `stat-pairwise-correlation` | 对每个驱动基因，相关性分析：FLS_g vs 该基因所在通路签名分数 | 每基因相关性 + 散点图 |
| F2.2 | `stat-fit-linear-model` | 通路签名分数 ~ FLS_g + HBV + age + sex + grade | 系数表 + 残差诊断 |
| F2.3 | `stat-fit-glm` | 高/低通路扰动二元结局 ~ FLS_g + 协变量（logistic 链接） | OR、Wald CI |
| F2.4 | `stat-bayesian-estimation` | 对 F2.2 的核心系数做贝叶斯估计（PyMC） | 后验分布 + 95% HDI |

**关键决策点**：若 F2.1 的 Spearman 在 ≥4/8 驱动基因中显著（FDR < 0.1），认为"剂量-反应"假设获得初步支持。

#### F3. 基因调控网络（探索性）

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| F3.1 | `stat-learn-bayesian-network` | 构建小型有向无环图（DAG）：节点 = {FLS_g, 通路签名, HBV, 分级, 生存事件}；学习条件独立结构 | DAG + 边强度表 |
| F3.2 | `stat-pairwise-correlation` | 跨驱动基因的 FLS 相关与共突变模式 | 共突变热图 |
| F3.3 | `stat-cluster-samples` | 基于 8 个 FLS 的患者无监督聚类，识别"功能负荷亚型" | 聚类热图 + 最优 K |

**警告**：F3.1 的 DAG 是观察性数据上的结构学习，**不可解读为因果**，仅作为假设生成。

#### F4. 生存分析（子问题 3）

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| F4.1 | `stat-survival-analysis` | KM 曲线：高 FLS（top 25%）vs 低 FLS vs WT，分基因绘制 | KM 图 × 8 + log-rank p |
| F4.2 | `stat-survival-analysis` | Cox 模型对比：① 仅二元突变状态 ② 仅 FLS ③ FLS + 二元状态 + 协变量 | C-index + 似然比检验 |
| F4.3 | `stat-survival-analysis` | 验证比例风险假设（Schoenfeld 残差）；时变 Cox 备选 | PH 假设诊断报告 |
| F4.4 | `stat-bayesian-estimation` | 关键 HR 的贝叶斯后验估计 | 后验分布 + 95% HDI |

**主假设检验**：模型 ③ 的 C-index 显著高于模型 ① 即支持子问题 3。要求 Δ C-index ≥ 0.02 且 bootstrap CI 不跨零。

#### F5. 外部验证（可选）

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| F5.1 | `stat-logistic-regression` | 用 ICGC-LIRI-JP 数据复现 F2.2 的关键剂量关系 | 跨队列一致性表 |
| F5.2 | `stat-survival-analysis` | LIRI-JP 上 FLS-Cox 模型验证 | 外部 C-index |

### 阶段 G：结论综合与工具评估

| 步骤 | Skill | 任务 | 产出 |
|------|-------|------|------|
| G1 | `research` | 整合：三个子问题的结论、与已发表证据的对比、对临床分层的潜在意义 | 结论综合文档 |
| G2 | `research` | 工具链评估：每个 skill 的运行成功率、参数调整、改进建议；两个 agent 的协调表现 | 工具评估报告 |

---

## 四、混杂因素与偏倚控制

### 技术混杂

| 因素 | 风险 | 控制策略 |
|------|------|----------|
| TCGA 测序批次（TSS / plate） | 中 | 作为 Cox / DE 模型协变量；ComBat-seq 备选 |
| GDC 已 call MAF 的过滤策略不可见 | 中 | Tier 2 子集端到端复跑，记录一致率 |
| AlphaFold 模型质量异质性（pLDDT） | 高 | 仅在 pLDDT > 70 区域信任 ΔΔG；其余标记低置信度 |
| FoldX 单次运行的随机性 | 中 | RepairPDB 后每个 mutation 跑 ≥ 3 次取均值 |
| 多工具 ΔΔG 量纲不一致 | 中 | consensus_stability_rank 做方向感知 z-score 聚合 |

### 生物学混杂

| 因素 | 风险 | 控制策略 |
|------|------|----------|
| 病因学异质性（HBV vs HCV vs 酒精 vs NASH） | 高 | 模型协变量 + 亚组敏感性分析 |
| 肿瘤纯度与 TME 组成 | 高 | 使用 ESTIMATE/CIBERSORTx 推断纯度并作为协变量 |
| 共突变（如 TP53 + CTNNB1 几乎互斥） | 中 | F3.2 共突变分析；多变量 Cox 内显式建模 |
| 拷贝数变异未在 MAF 中体现 | 中 | 仅作为 limitation 声明，未来工作整合 GISTIC |
| 转录组样本与外显子样本的患者交集 | 低 | 仅在交集患者上做整合分析（预计 ~330 例） |

### 统计偏倚

| 因素 | 风险 | 控制策略 |
|------|------|----------|
| 多重比较（8 基因 × 多通路 × 多终点） | 高 | 预登记主分析（焦点 = TP53 与 CTNNB1）；其余为探索性 |
| 选择性报告 | 中 | 全部模型与未达显著的结果均写入产出 |
| 生存终点截尾不平衡 | 中 | KM 比较中报告 number-at-risk 表 |
| 模型过拟合（小样本 + 多协变量） | 高 | bootstrap 重抽样估 C-index CI；regularized Cox（glmnet）备选 |
| FLS 与突变频率混淆 | 中 | 在 Cox 中同时纳入"突变数"与 FLS，确认 FLS 独立效应 |

---

## 五、计算资源需求

| 资源 | 需求量 | 说明 |
|------|--------|------|
| 存储 | **Tier 1 ~50 GB；Tier 2 额外 ~3 TB** | 主分析 + 子集端到端验证 |
| 内存 | **64 GB 推荐** | Mutect2 + STAR + FoldX 高峰 |
| CPU | **16-32 核** | BWA-MEM2、STAR、Mutect2、FoldX 批量 |
| GPU | **不强制** | AlphaFold 已用云端模型；FoldX 是 CPU |
| 耗时（Tier 1 主分析） | **~3 天** | 见下方分解 |
| 耗时（Tier 2 端到端） | **额外 ~5-7 天** | 30 例 WXS + 配对 RNA-seq |

### 耗时分解（Tier 1）

| 阶段 | 预估时间 | 瓶颈 |
|------|----------|------|
| B 数据获取 | 半天 | GDC API 限速 |
| D 蛋白稳定性 | 1-2 天 | FoldX 在 ~500-2000 突变上的批量运行 |
| E 转录组（Tier 1 直接用 GDC counts） | 半天 | DE 分析 |
| F 统计建模 | 1 天 | 贝叶斯 MCMC 采样 |
| G 综合 | 半天 | 文献交叉比对 |

### 软件依赖

| 包 | 版本建议 | 用途 |
|----|----------|------|
| GATK | 4.5+ | Mutect2 |
| BWA-MEM2 | 2.2+ | DNA 比对 |
| STAR | 2.7+ | RNA 比对 |
| Salmon | 1.10+ | 转录本定量 |
| FoldX | 5.0+ | ΔΔG 估计 |
| BLAST+ (rpsblast) | 2.15+ | CDD 结构域注释 |
| DESeq2 | ≥1.42 | 差异表达 |
| clusterProfiler | ≥4.10 | 富集分析 |
| lifelines / survival | latest | Cox / KM |
| PyMC | ≥5.0 | 贝叶斯估计 |
| scikit-learn | ≥1.3 | 重采样、C-index |
| pgmpy | ≥0.1.24 | 贝叶斯网络结构学习 |

---

## 六、预期产出清单

| 编号 | 产出物 | 格式 | 验证标准 |
|------|--------|------|----------|
| O1 | 数据获取与一致性报告 | Markdown | Tier 2 vs GDC MAF 一致率 > 85% |
| O2 | 基因 → 结构域映射表 | TSV | 8 个驱动基因全部覆盖 |
| O3 | 突变 → ΔΔG 表 | TSV | 至少 80% 的错义突变可评分（其余标记低置信度） |
| O4 | 患者 × FLS 矩阵 | TSV | 8 列 FLS + 临床列 |
| O5 | DE 表（三种比较） | TSV × 3 + 火山图 PDF × 3 | 肿瘤 vs 正常的经典 HCC 通路（细胞周期、Wnt）富集 |
| O6 | 功能富集表 | TSV + 网络图 PDF | KEGG/Hallmark 显著通路与文献一致 |
| O7 | ΔΔG-通路签名剂量散点图 | PDF | 每基因一图 |
| O8 | 关键剂量关系系数贝叶斯后验图 | PDF | 95% HDI 报告 |
| O9 | 共突变热图与 FLS 聚类 | PDF | 至少识别 2 个功能负荷亚型 |
| O10 | KM 曲线（高/低/WT 三组）× 8 基因 | PDF | log-rank p 与 HR 报告 |
| O11 | Cox 模型对比表（二元 vs FLS vs 联合） | TSV + bootstrap CI | C-index 提升 ≥ 0.02 视为支持 |
| O12 | DAG 假设生成图 | PDF + edge list | 标注"探索性、非因果" |
| O13 | 外部队列验证报告（若数据可得） | Markdown | 关键剂量关系方向一致 |
| O14 | 工具链评估报告 | Markdown | 每个 skill 的运行日志、耗时、改进建议 |

---

## 七、Skill/Agent 完整调用映射

```
阶段A (文献)     research × 4 ──────────────────────────────────────────┐
                                                                        │
阶段B (环境)     bioinformatics-env-setup                                │
                  search-ncbi-datasets                                   │
                  download-gdc × 2 (Tier1 + Tier2)                       │
                  search-ena (可选)                                      │
                  search-gsa (可选)                                      │
                  ncbi-eutilities-assistant                              │
                                                                        │
阶段C (变异)     ngs-quality-control                                     │
  Tier 2 子集    ngs-read-preprocessing                                  │
                  genome-read-alignment                                   │
                  genome-alignment-qc                                     │
                  genome-variant-calling                                  │
                  genome-variant-filtering                                │
                  genome-variant-annotation                               │
                                                                        │
阶段D (蛋白)     rpsblast-assistant                                      │
                  predict-protein-heat-stability                          │
                  design-thermostable-mutations  ← consensus 模块反向用法 │
                  ↑                                                      │
                  └── ngs-analysis-expert (协调 C1-E6) ────────────────┤
                                                                        │
阶段E (转录组)   rnaseq-read-alignment                                   │
                  rnaseq-alignment-qc                                    │
                  rnaseq-read-counting                                   │
                  rnaseq-transcript-quantification                       │
                  rnaseq-differential-expression                         │
                  rnaseq-functional-enrichment                           │
                                                                        │
阶段F (统计)     stat-assess-data-quality                                │
                  stat-analyze-distribution                              │
                  stat-pca                                               │
                  stat-nonlinear-embedding                               │
                  stat-pairwise-correlation                              │
                  stat-fit-linear-model                                  │
                  stat-fit-glm                                           │
                  stat-logistic-regression                               │
                  stat-bayesian-estimation                               │
                  stat-learn-bayesian-network                            │
                  stat-cluster-samples                                   │
                  stat-survival-analysis                                 │
                  ↑                                                      │
                  └── statistical-analysis-expert (协调 F1-F5) ────────┤
                                                                        │
阶段G (综合)     research × 2 ──────────────────────────────────────────┘
```

### 覆盖统计

- **Agent**：2/2（100%）
- **Skill**：30/54（≈56%）—— 是三个课题中覆盖率最高的。
- **新覆盖的 skill（之前两个课题未用）**：
  - 数据获取：`download-gdc`、`search-ncbi-datasets`、`bioinformatics-env-setup`
  - WGS/WES 全链路：`genome-read-alignment`、`genome-alignment-qc`、`genome-variant-calling`、`genome-variant-filtering`、`genome-variant-annotation`
  - 蛋白工程全链路：`rpsblast-assistant`、`predict-protein-heat-stability`、`design-thermostable-mutations`
  - RNA-seq 批量全链路：`rnaseq-read-alignment`、`rnaseq-alignment-qc`、`rnaseq-read-counting`、`rnaseq-transcript-quantification`、`rnaseq-differential-expression`、`rnaseq-functional-enrichment`
  - 统计补完：`stat-fit-linear-model`、`stat-fit-glm`、`stat-learn-bayesian-network`、`stat-survival-analysis`
- **三个课题合计覆盖率**：~46/54（85%+）。剩余未覆盖主要是 `structured-intelligence-skill-creator`（meta-skill）、`download-sra`/`download-geo`（已在另两课题用过）、部分 scRNA-seq 与宏基因组（属于另两课题主战场）。

---

## 八、风险与缓解

| 风险 | 严重性 | 概率 | 缓解策略 |
|------|--------|------|----------|
| dbGaP 审批延误导致 BAM 数据不可得 | 高 | 中 | 主分析仅依赖开放 MAF + counts，BAM 仅用于工具链验证 |
| AlphaFold 模型在驱动基因关键区域 pLDDT 低 | 中 | 中 | 仅在 pLDDT > 70 区报告，其余降级为"低置信度" |
| FoldX ΔΔG 在 HCC 队列上的预测误差大 | 中 | 中 | 多工具共识聚合（D4）；与 AlphaMissense 公开预测对照 |
| 高 FLS 与"突变多"混淆 | 中 | 中 | 在 Cox 中同时纳入突变计数与 FLS，做嵌套模型检验 |
| HBV/HCV 病因层导致剂量关系失效 | 中 | 中 | 病因分层分析；预登记 HBV+ 亚组作为主分析 |
| 多重比较稀释信号 | 中 | 中 | 主分析锁定 *TP53* + *CTNNB1*，其余 6 基因为探索性 |
| 贝叶斯网络结构不稳健 | 中 | 高 | bootstrap 重采样评估边稳定性；仅报告稳定性 > 0.8 的边 |
| 计算资源不足（FoldX 批量） | 低 | 中 | 用 `run_foldx_chunked.py` 分块；必要时云端 burst |
| 外部验证队列（ICGC-LIRI-JP）样本量不足或元数据缺失 | 低 | 中 | 验证为"加分项"，不阻塞主结论 |

---

## 九、成功标准

### 科学维度

- [ ] 在 ≥6/8 驱动基因上完成 ΔΔG 量化（覆盖率 > 80% 错义突变）
- [ ] 至少 1 个驱动基因（最有可能是 *TP53*）观测到显著的 ΔΔG-通路扰动剂量关系（FDR < 0.05）
- [ ] 联合 FLS 模型的 C-index 比二元突变模型提升 Δ ≥ 0.02 且 bootstrap CI 不跨零
- [ ] 关键贝叶斯估计的 95% HDI 不跨零，R-hat < 1.01，ESS > 400
- [ ] 至少识别 2 个"功能负荷亚型"并与临床特征建立关联

### 方法学维度

- [ ] Tier 2 子集端到端工具链与 GDC MAF 一致率 > 85%
- [ ] 多重比较策略预登记并完整报告（含未达显著的结果）
- [ ] 比例风险假设违反时启用时变 Cox，并报告诊断
- [ ] 所有结构-序列编号问题（UniProt vs canonical transcript）有显式映射记录

### 工具评估维度

- [ ] 30 个 skill 在真实数据上的运行成功率、平均耗时、错误次数
- [ ] 识别至少 5 个 skill 的改进方向（参数默认、错误提示、文档补充）
- [ ] 两个 agent（`ngs-analysis-expert`、`statistical-analysis-expert`）在多步协调中的人工干预次数统计
- [ ] 总结跨课题（本课题 + CRC + scRNA）的 skill 重复使用率与稳定性

---

## 十、时间规划

| 阶段 | 预估周期 | 前置依赖 |
|------|----------|----------|
| A：文献与方法 | 第 1-2 天 | 无 |
| B：环境与数据 | 第 2-3 天 | A4 完成（数据使用协议） |
| C：Tier 2 变异调用 | 第 3-5 天 | B4（BAM 下载完成）|
| D：蛋白稳定性 | 第 4-6 天 | B7（基因/蛋白 ID 表）；D 与 C 可并行 |
| E：转录组 | 第 5-7 天 | B3（counts）|
| F1-F2：探索与剂量关系 | 第 6-8 天 | D5 + E5 |
| F3：网络分析 | 第 8-9 天 | F2 |
| F4：生存分析 | 第 9-10 天 | F2 |
| F5：外部验证（可选） | 第 10-11 天 | F4 |
| G：综合与工具评估 | 第 11-12 天 | 所有阶段 |

**关键路径**：B → D → F4，约 8-10 天。Tier 2 变异调用与 Tier 1 主分析可并行。
