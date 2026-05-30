# 项目改进路线图（Improvement Roadmap）

> 本文档汇总了对 `docker-android` 项目在以下几个方面的分析与建议，便于团队**按需推进**：
>
> 1. 是否适合引入 / 重构为 Zig
> 2. 如何系统性提升代码质量（lint / 格式化 / 测试 / 门禁）
> 3. 哪些 Shell 脚本值得迁移到 Python、哪些应保留 Shell
> 4. 已落地的改动与后续可推进项
>
> **结论先行**：质量提升的最大杠杆**不在“换语言”**，而在**给占比最大的 Shell 脚本补上静态检查（shellcheck）**，再用 **pre-commit + mypy + 统一 Makefile** 把检查链固化，并把**有逻辑、需测试的脚本**逐步收敛到 Python。

---

## 0. 项目定位与代码盘点

本项目本质是一个 **DevOps 编排项目**（Docker 镜像构建 + Android 模拟器启动），代码基本都是 **I/O 密集型的“胶水代码”**。

| 类别 | 代表文件 | 性质 |
|------|----------|------|
| Shell 脚本（约 2300 行，~20 个 `*.sh`） | `travis.sh` `release.sh` `release_real.sh` `release_geny.sh` `src/utils.sh` `src/record.sh` `appium.sh` `build-optimized.sh` 等 | 调用 `docker`/`avdmanager`/`adb`/`ffmpeg`，纯流程编排 |
| Python（约 400 行） | `src/app.py` `src/log.py` `src/versions.py` | 读环境变量、拼命令、`subprocess` 启动 emulator/appium |
| 资源 / 配置 | `rc.xml` `*.png` `docker-compose.yml` `*.tf` | 非代码 |

这些代码做的事就是：**读环境变量 → 拼字符串命令 → 调用外部进程 → 等待 I/O**。瓶颈完全在外部进程（Docker 构建、模拟器启动）上。

---

## 1. 是否适合重构为 Zig？——不建议

**这个项目几乎没有真正适合用 Zig 重构的地方。**

### 不建议的原因

- **没有热点**：全文没有循环计算、数据处理、解析大文件等 CPU/内存密集逻辑。`app.py` 里最“重”的操作只是逐行读 `config.ini`（`is_initialized`）。
- **强依赖 shell 生态**：`record.sh` 用 `curl`/`jq`/`ffmpeg`，Bash 调用这些工具是最自然的；Zig 反而要手写一堆 `std.process.Child` 样板代码。
- **可读性/可维护性会下降**：DevOps 团队更熟悉 Shell/Python；Zig 还需要编译步骤，与“脚本即改即用”的工作流冲突。
- **Zig 生态缺位**：没有成熟的 Docker SDK、Selenium/Appium 客户端，等于自己重造轮子。

### 仅供参考的边缘场景（价值有限）

1. **小型 CLI 工具替代部分纯函数逻辑**：如版本号映射、UDID 解析等，可编译成静态无依赖小二进制。但这点逻辑用 Shell/Python 几行就够了，**收益不成比例**。
2. **未来若出现高频低延迟处理**（如自定义视频帧抓取、二进制日志解析），那时 Zig 才有用武之地。**目前不存在**这种需求。

> 一句话：**Zig 适合“写工具/写底层”，本项目是“用工具/编排流程”，两者错位，不建议重构。**

---

## 2. 质量提升建议（按性价比从高到低）

### 当前质量基线（已具备）

- ✅ Python 测试体系：`pytest` + `coverage` + `pytest-xdist`（配置见 `setup.cfg`，测试在 `src/tests/{unit,e2e}`）
- ✅ `flake8`（max-line-length=120）
- ✅ GitHub Actions（`.github/workflows/build-emulator*.yml`）
- ✅ PR/Issue 模板

### 🥇 第一优先级：给 Shell 脚本加防护（收益最大）

项目主体是 Shell，但历史上完全没有静态检查，这是最大风险点。

1. **引入 `shellcheck`**——Shell 界的“编译器+linter”，能抓出未引用变量、`$(...)` 误用、`[ ]` vs `[[ ]]` 等经典坑。
2. **引入 `shfmt`**——统一 Shell 格式（缩进/换行），消除风格争论。
3. **推广 `set -euo pipefail`**——`travis.sh` 已采用，应推广到 `release.sh`/`utils.sh`/`appium.sh` 等所有脚本。
4. **拆分巨型脚本**——`utils.sh`（~489 行）、`release.sh`（~451 行）、`appium.sh`（~376 行）偏大，可按职责拆成小函数库文件。
5. **(进阶) Shell 单元测试**——用 `bats-core` 对纯逻辑函数写测试。

### 🥈 第二优先级：统一门禁 pre-commit

新建 `.pre-commit-config.yaml`，把检查前移到提交时（而非等 CI 失败）：

```yaml
repos:
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks: [{ id: shellcheck }]
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.10.0-2
    hooks: [{ id: shfmt }]
  - repo: https://github.com/pycqa/flake8
    rev: 7.1.1
    hooks: [{ id: flake8 }]
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks: [{ id: mypy }]
```

### 🥉 第三优先级：强化 Python 侧

1. **类型检查 `mypy`**——`app.py` 已有类型注解，加 mypy 几乎零成本，能进一步把关 `os.getenv` 返回 `None` 的场景。
2. **格式化 `black` + import 排序 `isort`**——消除手工格式问题。
3. **覆盖率门槛**——CI 里设 `--cov-fail-under=70`（先定现实基线再逐步提高），防止覆盖率倒退。
4. **补测试**——`prepare_avd`/`appium_run`/`create_node_config` 这类拼命令逻辑值得加单元测试（mock `subprocess`）。

### 🏗️ 第四优先级：工程化与可维护性

1. **加 `Makefile`（或 `justfile`）** 作为统一入口：

   ```makefile
   lint:    ; shellcheck *.sh src/*.sh && flake8 src && mypy src
   test:    ; pytest src/tests/unit --cov=src
   fmt:     ; shfmt -w *.sh src/*.sh && black src && isort src
   ```

2. **CI 增加独立 lint 阶段**——在构建镜像前加独立 `lint` job（shellcheck + flake8 + mypy），快速失败、节省构建时间。
3. **配置集中化**——避免 Shell 与 Python 两边各维护一份版本/镜像映射导致漂移。
4. **文档**——补 `CONTRIBUTING.md` 说明如何跑 lint/test/格式化。

### 落地路线图（建议顺序）

| 阶段 | 动作 | 成本 | 收益 | 状态 |
|------|------|------|------|------|
| 1 | CI 加 `shellcheck` + 全脚本 `set -euo pipefail` | 低 | 🔥 高 | ✅ 已落地（部分推广待续） |
| 2 | `.pre-commit-config.yaml`（shellcheck/shfmt/flake8/mypy） | 低 | 高 | ✅ 已落地 |
| 3 | `mypy` + `black`/`isort` 接入 Python | 低 | 中高 | ⏳ 部分（flake8 已绿，mypy/black/isort 配置就绪待启用） |
| 4 | `Makefile` 统一入口 + CI 独立 lint job | 中 | 中 | ✅ 已落地 |
| 5 | 拆分大脚本 + 补 `app.py` 单元测试 + `bats` Shell 测试 | 中高 | 中 | ✅ 已落地（首批，见 §4） |
| 6 | 配置集中化（消除 Shell/Python 重复） | 中 | 中 | ✅ 已落地（版本映射 + per-version 构建配置全部收敛到 `src/versions.py`，见 §4） |

---

## 3. Shell 是否应迁移到 Python？——分类处理，而非全量重写

正确的判断标准不是“哪个语法更清晰”，而是**“这段脚本主要在做什么”**：

- **脚本主要是“拼命令 + 跑外部进程 + 等 I/O”** → 留在 Shell 最自然（Python 反而要写一堆 `subprocess` 样板）。
- **脚本里有“逻辑/数据/解析/状态判断”** → 改 Python 更清晰、更好测试、更好维护。

### 🟢 适合迁移到 Python（有真实收益）

| 文件 / 逻辑 | 为什么值得迁移 | 状态 |
|------------|----------------|------|
| `travis.sh` 的 `map_android_version`、`ANDROID_VERSION_MAP` | 纯版本映射 + 字符串判断；与 `src/app.py` 版本逻辑重叠，Shell/Python 各维护一份有漂移风险。收敛到 Python 一处 + 单测最划算。 | ✅ 已完成（见 §4） |
| `src/utils.sh` 的 `parse_android_version_and_device`、`enable_proxy_if_needed`（解析 proxy URL、`IFS` 切分） | 字符串/URL 解析在 Bash 里很易错（引号、`sed`、`IFS`），Python 三行 `urllib.parse` 就清楚且可测。 | ⏳ 待推进 |
| `app.py` 里残留的 shell 内联（如 `os.popen('ifconfig … \| grep … \| awk …')` 取 IP） | 已经在 Python 里了，却用 shell 管道实现，可换成原生 Python，顺手消除一处 shell 依赖。 | ✅ 已完成（见 §4 阶段 7） |

### 🟡 可迁可不迁（收益有限，看团队偏好）

| 文件 | 说明 |
|------|------|
| `release.sh` / `release_real.sh` / `release_geny.sh` | 主体是 `docker build/push` 编排，但夹杂参数解析和分支。若团队 Python 更熟可迁；否则保持 Shell + `shellcheck` 即可。注：`release.sh` / `build-optimized.sh` 中的 **per-version 配置已收敛到 `src/versions.py`**（见 §4 阶段 6），编排主体仍保留 Shell。 |

### 🔴 建议保持 Shell（改 Python 是负收益）

| 文件 | 为什么留在 Shell |
|------|------------------|
| `src/record.sh`（`ffmpeg` / `curl` / `jq` / `kill $(ps … \| awk …)`） | 全是调外部工具 + 管道，Bash 一行 = Python 一段 `subprocess` 样板。 |
| `src/utils.sh` 里大量 `adb …` 调用（`wait_emulator_to_be_ready`、`install_google_play`、`change_language_if_needed`） | 就是连续调命令行工具，Bash 最直观。 |
| `docker login/logout`、各种一次性 entrypoint 胶水 | 容器启动脚本用 Shell 是行业惯例。 |

### 迁移时要避免的陷阱

- 把 `subprocess.check_call('… | grep … | awk …', shell=True)` 搬过去，**只是把 Bash 塞进 Python 字符串**，既没更安全也没更清晰，纯属换皮。
- 调一堆 `adb`/`ffmpeg` 的流程，用 Python 反而**啰嗦**（每个命令一个 `subprocess` + 错误处理）。
- 引入 Python 还多一层运行时/依赖，对“容器启动即用”的入口脚本不划算。

---

## 4. 已落地的改动（本系列工作成果）

### 阶段 1 & 2：Shell 静态检查与统一门禁

- 新增 `.shellcheckrc`：统一 shellcheck 规则（bash 模式、external-sources、合理禁用 SC1091）。
- 新增 `.github/workflows/lint.yml`：CI 独立 Lint 工作流（shellcheck + shfmt 一个 job，flake8 + mypy 一个 job），push/PR 触发。
- 新增 `.pre-commit-config.yaml`：提交前门禁（通用 hygiene + shellcheck/shfmt + isort/black/flake8/mypy）。
- 新增 `Makefile` 与 `CONTRIBUTING.md`：提供 `make lint/fmt/test/install-hooks` 统一入口与贡献指南。
- 修复 `src/` 既有 flake8 违规（`app.py`、`test_app.py`、`test_appium.py`）：由 17 处降为 0（纯格式/无用代码清理，不改变行为）。

### 第 6 项（部分）：版本映射收敛到 Python

- 新增 `src/versions.py`：作为版本映射**单一数据源**（`ANDROID_VERSION_MAP` 字典 + `map_android_version()`），并提供 `python3 -m src.versions map <ver>` CLI；**刻意不 import `src.app`**，避免触发 emulator 环境变量校验。
- 修改 `travis.sh`：删除内联的 `declare -A ANDROID_VERSION_MAP` 与 bash 版 `map_android_version`，改为 `python3 -m src.versions map "$1"`，调用契约与行为保持不变。
- 新增 `src/tests/unit/test_versions.py`：覆盖完整版本透传、短版本映射、`_16k` 变体保留、未知版本回退，及 CLI 成功/非法用法返回码。

**验证**：`flake8 src` = 0；`pytest src/tests/unit` 全绿（29 passed）；CLI 对 8 个代表性输入的输出与原 bash 映射逐项一致。

### 阶段 5（首批）：拆分大脚本 + 补单测 + bats Shell 测试

- 新增 `src/utils_lib.sh`：从 `src/utils.sh`（运行时入口，被 supervisord 以 `./src/utils.sh` 启动）抽出**纯逻辑函数** `parse_android_version_and_device`、`get_capability_register_alert_threshold`；`utils.sh` 顶部 `source` 引入，**入口契约与行为保持不变**（用 `bash -n` + source 调用验证一致）。
- 新增 `src/tests/unit/test_helpers.py`：补 `app.py` 纯函数单测——`get_env_int`、`get_env_port_from_udid`、`get_avd_abi`（标准 + `_ps16k`）、`create_node_config`（校验 JSON 内容）。
- 新增 `src/tests/shell/test_utils_lib.bats`：用 bats 覆盖抽出的两个纯函数（解析 `_16k`/普通版本、阈值 valid/非数字/0/未设默认）。
- 接入工具链：`Makefile` 新增 `test-shell` 并并入 `test`；`.github/workflows/lint.yml` 新增 `shell-tests`（bats）job；`CONTRIBUTING.md` 补 bats 安装与测试布局说明。

**验证**：`flake8 src` = 0；`pytest src/tests/unit` 全绿（38 passed，新增 9）；6 条 bats 断言用等价 bash 逐条校验通过（本地未装 bats，CI 已配 bats-action）。

> 说明：`utils.sh` 因含 `while true` 主循环 + 硬编码 token + 大量 `adb`/`curl` 副作用，**不宜整体拆分**；本批仅抽离可安全测试的纯逻辑函数，其余编排逻辑按 §3 红色分类保留 Shell。

### 阶段 6：配置集中化（消除 Shell/Python 版本配置重复）

把所有 **per-version 构建配置**收敛到 `src/versions.py` 这一**单一数据源**，彻底消除 Shell 与 Python（以及 Shell 之间）的重复维护与漂移：

- 扩展 `src/versions.py`：在既有 `ANDROID_VERSION_MAP`（短→长映射）之外，新增 `API_LEVEL_MAP`、`CHROMEDRIVER_MAP`、`SUPPORTED_VERSIONS` 及查询函数 `get_api_level`/`get_chromedriver_version`/`get_img_type`/`get_browser`/`get_processor`/`get_sys_img`/`is_supported_version`；CLI 增加 `api_level|chromedriver|img_type|browser|processor|sys_img` 子命令与 `supported`（管道分隔）/`list`（空格分隔）。**仍刻意不 import `src.app`**。
- 改造 `release.sh`：删除内联的 `get_api_level`/`get_chromedriver_version`/`get_img_type`/`get_browser`/`get_processor`/`get_sys_img` 的 bash `case`、硬编码的支持版本列表与 `ANDROID_VERSIONS=(...)` 全量数组，统一改为 `versions_cli`（`python3 -m src.versions ...`）；函数名/调用契约保持不变。
- 改造 `build-optimized.sh`：删除“copied from release.sh”的重复 bash `case`（**该副本已漂移**——缺少 `16.0` / `16.0_16k` 条目），同样改为调用 `src/versions.py`。
- 补单测 `src/tests/unit/test_versions.py`：覆盖全部新查询函数、`supported`/`list` 内容（断言 `16.0`/`16.0_16k` 在列、每个支持版本都有 API level）及新增 CLI 子命令的返回码。

**验证**：`flake8 src` = 0；`pytest src/tests/unit` 全绿（48 passed，新增 10）；对全部 17 个版本的 6 项配置 CLI 输出与原 `release.sh` bash `case` 逐项一致；`release.sh` 包装函数经 `source` 调用验证行为不变。

> 说明：`release.sh` 是最完整/权威的副本，故以其取值为准；这次顺带修正了 `build-optimized.sh` 已漂移的缺项。

### 阶段 7：清理 `app.py` shell 内联 + 推广 `set -euo pipefail`

**(b) 清理 `app.py` 的 shell 内联取 IP**：

- 新增纯函数 `src/app.py::get_local_ip()`：用 `socket`（UDP-connect 到公共地址、不实际发包，由 OS 选出出站接口）取本机 IP，替换原 `os.popen('ifconfig eth0 | grep \'inet\' | cut -d: -f2 | awk ...')`；失败时回退空串并 `logger.warning`，不再依赖容器内是否安装 `ifconfig`。
- 补单测 `test_helpers.py::TestGetLocalIp`（成功路径 + `OSError` 回退，均校验 socket 被关闭）；同步把 `test_appium.py` 两个用例由 mock `os.popen` 改为 mock `src.app.get_local_ip`（保持「grid 路径需解析本机 IP」的断言意图）。

**(a) 推广 `set -euo pipefail`（分级处理，避免负收益）**：

- **build 脚本**（低风险）：`release_real.sh`、`release_geny.sh` 加 `set -euo pipefail`，并把 `set -u` 下会报错的未保护引用改为安全形式（`[ -z "${1:-}" ]`、`--build-arg TOKEN=${TOKEN:-}`），对齐 `release.sh` 既有写法。
- **小型运行时脚本**：`src/record.sh` 加 `set -eo pipefail`（**不加 `-u`**——它由可空环境变量 `VIDEO_PATH`/`AUTO_RECORD`/`DISPLAY` 驱动）；并把 `stop()` 的 `kill $(...)` 改为「无 ffmpeg 进程时不调用 kill」，避免空参在 `set -e` 下中止脚本；`$@` → `"$@"`。
- **复杂运行时入口刻意保留**：`src/appium.sh`（大量 `[ "$X" = true ]` 依赖可空变量 + `gmsaas`/`terraform`/`curl` 容错执行）与 `src/utils.sh`（`while true` 主循环 + 大量 `adb`/`curl` 副作用）若强加 `set -e`/`-u` 会改变生产入口行为且无法在容器外验证，按 §3🔴 分类**不强加严格模式**。

**验证**：`flake8 src` = 0；`pytest src/tests/unit` 全绿（50 passed，新增 2）；`bash -n` 校验 `release_real.sh`/`release_geny.sh`/`record.sh` 通过；`py_compile` 通过。

---

## 5. 后续可按需推进项（Backlog）

按建议优先级排列，团队可按需挑选：

1. **清理 `app.py` 内 shell 内联**：✅ 已落地（见 §4 阶段 7）——`os.popen('ifconfig ...')` 取 IP 改为纯 Python `socket` 实现 `get_local_ip()` 并补单测。
2. **迁移解析类逻辑到 Python + 单测**：`src/utils.sh` 的 `parse_android_version_and_device`、`enable_proxy_if_needed`（proxy URL 解析）→ `src/` 下的 Python 函数。
3. **推广 `set -euo pipefail`**：⏳ 部分落地（见 §4 阶段 7）——`release_real.sh`/`release_geny.sh` 已加 `set -euo pipefail`、`src/record.sh` 已加 `set -eo pipefail`；`src/utils.sh`、`src/appium.sh` 因属复杂运行时入口（可空变量 + 容错副作用），刻意保留以免负收益。
4. **拆分巨型脚本（续）**：`utils.sh` 已抽出纯逻辑到 `src/utils_lib.sh`（见 §4）；`release.sh` / `appium.sh` 仍可按职责进一步拆分。
5. **启用 mypy / black / isort 门禁**：当前配置已就绪，待团队约定基线后在 CI 开启强制。
6. **设置覆盖率门槛**：`--cov-fail-under=N`，从现实基线起步逐步提高。
7. **补 Python 单测**：`prepare_avd` / `appium_run` / `create_node_config`（mock `subprocess`）。
8. **(进阶) bats Shell 测试（续）**：已对 `src/utils_lib.sh` 两个纯函数加 bats 测试（见 §4）；可继续为其它脚本中析出的纯逻辑补测。
9. **配置集中化**：✅ 已落地——版本短→长映射与 per-version 构建配置（api_level/chromedriver/img_type/browser/processor/sys_img/支持版本列表）已全部收敛到 `src/versions.py`（见 §4）；`release.sh`、`build-optimized.sh` 均改为调用其 CLI。剩余可选项：设备/skin 等信息亦可按需收敛。

---

> 维护说明：本路线图是“按需推进”的活文档。每完成一项，请更新对应表格/列表的状态标记（✅ 已落地 / ⏳ 待推进 / 🟡 可选）。
