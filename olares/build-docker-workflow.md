# build-docker.yml 工作流解读

本文档解读 YT-Navigator 仓库中的 **GitHub Actions 工作流**：  
`.github/workflows/build-docker.yml`  
用于在 **GitHub 上手动选择分支或 Tag**，**并行构建 amd64 / arm64 两种架构**的 Docker 镜像，并推送到 **GitHub Container Registry (ghcr.io)**。

---

## 一、整体流程概览

```
手动触发（输入 branch 或 tag）
        │
        ▼
┌───────────────┐
│   prepare     │  算出版本号、镜像名、是否打 latest
└───────┬───────┘
        │
        ▼
┌───────────────────────────────────────┐
│   build（matrix 并行）                 │
│   ├── amd64  → ubuntu-latest           │  构建并推送 xxx:版本-amd64
│   └── arm64  → ubuntu-24.04-arm        │  构建并推送 xxx:版本-arm64
└───────┬───────────────────────────────┘
        │
        ▼
┌───────────────┐
│   merge       │  把 amd64 + arm64 合并成一个多架构 manifest，推送 xxx:版本 和（可选）xxx:latest
└───────────────┘
```

- **prepare**：只跑一次，为后续 job 提供“版本号”“镜像名”“是否打 latest”。
- **build**：跑两次（两台机器并行），分别构建并推送 `镜像:版本-amd64` 和 `镜像:版本-arm64`。
- **merge**：等 build 都成功后，用 `docker manifest` 把两个单架构镜像合并成“多架构镜像”，推送 `镜像:版本`（以及选中的 `镜像:latest`）。

---

## 二、触发方式（`on`）

```yaml
on:
  workflow_dispatch:
    inputs:
      ref:
        description: 'Branch 或 Tag（例如 main、v0.1.2）'
        required: true
        default: 'main'
        type: string
```

- **仅手动触发**：没有 `push`、`release` 等自动触发。
- **`workflow_dispatch`**：在 GitHub 仓库的 **Actions** 页里，选择 “Build and Push Docker Image”，点 **Run workflow**。
- **输入 `ref`**：你要基于哪个 **分支** 或 **Tag** 构建，就填什么（如 `main`、`feat/olares-deploy-v0.0.1`、`v0.1.2`）。默认是 `main`。

之后所有 job 的 **checkout** 和 **镜像版本/tag** 都基于这个 `ref`。

---

## 三、全局环境（`env`）

```yaml
env:
  REGISTRY: ghcr.io
```

- 镜像推送到 **GitHub Container Registry**，地址为 `ghcr.io`。
- 最终镜像名形如：`ghcr.io/<你的用户名或组织>/yt-navigator:<版本>`。

---

## 四、Job 1：prepare（准备）

**作用**：在“你要构建的 ref”上，算出版本号、镜像名、是否打 `latest`，并把这些结果通过 **outputs** 传给后面的 `build` 和 `merge`。

### 4.1 运行环境与输出

```yaml
prepare:
  runs-on: ubuntu-latest
  outputs:
    version: ${{ steps.version.outputs.version }}
    image: ${{ steps.image.outputs.image }}
    add_latest: ${{ steps.version.outputs.add_latest }}
```

- 跑在 **一台** `ubuntu-latest` 上。
- **outputs**：后面 job 用 `needs.prepare.outputs.version`、`needs.prepare.outputs.image`、`needs.prepare.outputs.add_latest` 读取。

### 4.2 步骤 1：Checkout

```yaml
- name: Checkout repository
  uses: actions/checkout@v4
  with:
    ref: ${{ inputs.ref }}
```

- 按你输入的 **branch 或 tag**（`inputs.ref`）拉取代码，后续“版本号”和“用哪份代码构建”都基于这次 checkout。

### 4.3 步骤 2：Set version and image（算版本与是否 latest）

```yaml
- name: Set version and image
  id: version
  run: |
    REF="${{ inputs.ref }}"
    V=$(echo "$REF" | tr -d ' \n\r' | sed 's/[^a-zA-Z0-9_.-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
    echo "version=${V:-dev}" >> $GITHUB_OUTPUT
    [ "$REF" = "main" ] || [ "$REF" = "master" ] && echo "add_latest=true" >> $GITHUB_OUTPUT || echo "add_latest=false" >> $GITHUB_OUTPUT
```

- **版本号 `version`**：把 `ref` 转成合法 Docker tag（只保留字母数字、`_`、`.`、`-`，非法字符换成 `-`，去首尾 `-`）。若为空则用 `dev`。
- **add_latest**：当 `ref` 为 `main` 或 `master` 时为 `true`，merge 阶段会多推一个 `镜像:latest`。

### 4.4 步骤 3：Set image name（算镜像名）

```yaml
- name: Set image name
  id: image
  run: |
    OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
    echo "image=${{ env.REGISTRY }}/${OWNER}/yt-navigator" >> $GITHUB_OUTPUT
```

- **image**：`ghcr.io/<owner>/yt-navigator`，其中 `<owner>` 为仓库所有者（小写），满足 ghcr.io 命名要求。

---

## 五、Job 2：build（并行构建两个架构）

**作用**：在 **两台机器** 上分别构建 **amd64** 和 **arm64** 镜像，并推送到 ghcr.io，tag 为 `镜像:版本-amd64` 和 `镜像:版本-arm64`。

### 5.1 依赖与矩阵

```yaml
build:
  needs: prepare
  strategy:
    fail-fast: false
    matrix:
      include:
        - platform: linux/amd64
          runner: ubuntu-latest
          suffix: amd64
        - platform: linux/arm64
          runner: ubuntu-24.04-arm
          suffix: arm64
  runs-on: ${{ matrix.runner }}
```

- **needs: prepare**：等 prepare 成功后再跑，并使用其 outputs。
- **matrix**：两个“组合”并行跑：
  - **amd64**：`platform=linux/amd64`，`runs-on: ubuntu-latest`（x86 机器，本机构建 amd64）。
  - **arm64**：`platform=linux/arm64`，`runs-on: ubuntu-24.04-arm`（ARM 机器，本机构建 arm64）。
- **fail-fast: false**：一个架构失败不会立刻取消另一个，方便看两边结果。

所以是 **两台机器同时跑**，不是在一台机器上用 QEMU 模拟另一种架构。

### 5.2 权限

```yaml
permissions:
  contents: read
  packages: write
```

- 读仓库代码、向 GitHub Packages（ghcr.io）写镜像。

### 5.3 步骤概览

1. **Checkout**：同样按 `inputs.ref` checkout，保证和 prepare 同一份代码。
2. **Set up Docker Buildx**：启用 Buildx，支持多平台和缓存。
3. **Log in to Container Registry**：用 `GITHUB_TOKEN` 登录 ghcr.io。
4. **Build and push**：
   - `platforms: ${{ matrix.platform }}`：当前 job 只构建一个架构。
   - `tags: ...:${{ needs.prepare.outputs.version }}-${{ matrix.suffix }}`：推送为 `镜像:版本-amd64` 或 `镜像:版本-arm64`。
   - `cache-from/cache-to: type=gha`：使用 GitHub Actions 缓存，加快重复构建。

---

## 六、Job 3：merge（合并多架构 manifest）

**作用**：等两个 build 都成功后，用 **Docker manifest** 把 `镜像:版本-amd64` 和 `镜像:版本-arm64` 合并成**一个多架构镜像**，推送为 `镜像:版本`；若 prepare 里 `add_latest=true`，再推送 `镜像:latest`。

### 6.1 依赖与环境

```yaml
merge:
  needs: [prepare, build]
  runs-on: ubuntu-latest
```

- **needs: [prepare, build]**：等 prepare 和 **所有** matrix 的 build 都成功后才跑。
- 只做 manifest 的创建与推送，不需要 checkout 代码，跑在普通 `ubuntu-latest` 即可。

### 6.2 步骤 1：登录 ghcr.io

与 build 相同，用 `GITHUB_TOKEN` 登录，以便后续 `docker manifest push`。

### 6.3 步骤 2：Create and push manifest

```yaml
IMAGE="${{ needs.prepare.outputs.image }}"
V="${{ needs.prepare.outputs.version }}"
docker manifest create "${IMAGE}:${V}" \
  "${IMAGE}:${V}-amd64" \
  "${IMAGE}:${V}-arm64"
docker manifest push "${IMAGE}:${V}"
```

- **manifest create**：创建一个“多架构 manifest”，指向已推送的 `-amd64` 和 `-arm64` 两个镜像。
- **manifest push**：把这个 manifest 推送到 ghcr.io，这样 `镜像:版本` 就变成多架构 tag。

若 `add_latest` 为 true，再对 `latest` 做一次同样的 create + push，这样 `镜像:latest` 也是多架构。

用户执行 `docker pull ghcr.io/xxx/yt-navigator:版本`（或 `:latest`）时，Docker 会按当前机器架构自动选 amd64 或 arm64。

---

## 七、如何手动跑一次

1. 打开仓库：**GitHub → 你的 YT-Navigator 仓库**。
2. 进入 **Actions**，左侧选 **“Build and Push Docker Image”**。
3. 右侧点 **Run workflow**。
4. 在 **“Branch 或 Tag”** 里填要构建的 ref（如 `main`、`feat/olares-deploy-v0.0.1`、`v0.1.2`）。
5. 再点 **Run workflow**。

跑完后在 **Packages** 里可以看到 `yt-navigator`，拉取示例：

```bash
docker pull ghcr.io/<你的用户名或组织>/yt-navigator:main
# 或具体版本
docker pull ghcr.io/<你的用户名或组织>/yt-navigator:feat-olares-deploy-v0-0-1
```

---

## 八、和本地 build.sh 的对应关系

| 本地 (build.sh)              | CI (build-docker.yml)                          |
|-----------------------------|-------------------------------------------------|
| `./olares/build.sh <版本>`   | 手动输入 branch/tag，自动得到“版本”和镜像名     |
| 单机 `docker build` 一个 tag | 两台机并行 build，再 merge 成多架构一个 tag     |
| 推送到本地/自建 registry    | 推送到 ghcr.io                                  |
| 单架构（通常是你本机架构）  | 固定 amd64 + arm64 双架构                       |

逻辑上等价于：在 GitHub 上选一个 ref，用该 ref 的代码、按 amd64/arm64 各建一次镜像，再合并成一个多架构镜像并打上你选的“版本”和可选的 `latest`。
