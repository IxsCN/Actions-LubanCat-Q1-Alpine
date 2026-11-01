# Actions LubanCat Q1 Alpine

为野火 **LubanCat Q1（RK3528A）** 准备的独立 Alpine Linux 3.23 ARM64 镜像构建原型，输出 TF 卡镜像和 Rockchip USB 线刷 eMMC 固件。与 FriendlyElec 的 NanoPi 构建仓库独立，使用 [LubanCat 内核及 Q1 设备树](https://github.com/LubanCat/kernel)、[U-Boot](https://github.com/LubanCat/u-boot) 和 [rkbin](https://github.com/LubanCat/rkbin)。

**状态：SD 镜像和线刷 `update.img` 均已在 GitHub Actions 构建成功，尚未在 Q1 上验证启动或实际刷写。请把首次产物当作实验固件，保留原来的可启动系统和恢复方法。**

## 构建内容

- 野火 Linux 6.1 `lubancat_linux_rk3528_defconfig`，编译 `rk3528-lubancat-q1.dtb`；合并 `configs/dae.config` 并检查最终 eBPF、BTF 和 TC 配置及 vmlinux 的 `.BTF`。
- 野火 U-Boot `rk3528` 配置，使用同仓库的 rkbin 构建 loader。
- Alpine 3.23 aarch64 minirootfs，OpenRC、SSH、DHCP、`htop`、`tio`、`kitty-terminfo`、`tailscale`；内核模块与内核版本配套。
- SD 镜像包含 Rockchip loader（LBA 64）、GPT 分区 `uboot`（LBA `0x4000`）、`boot`（`0x8000`）和 `rootfs`（`0x48000`），根分区 UUID 与野火 `parameter-extboot.txt` 一致。
- `boot` 是 ext2 分区，放置野火的启动脚本、Image、Q1 DTB、uEnv；无 initrd，直接从 ext4 挂载 Alpine rootfs。

构建工作流先上传两份 GitHub Actions Artifact（保留 14 天）。成功后由独立发布工作流将镜像与 SHA256 校验文件发布到 [Releases](https://github.com/IxsCN/Actions-LubanCat-Q1-Alpine/releases)，标记为预发布版本：

- `lubancat-q1-alpine-sd`：`*.img.gz`，解压后写入 TF 卡启动。
- `lubancat-q1-alpine-emmc-update`：`*.update.img` 和 SHA256 文件，通过兼容 Rockchip 的 USB 线刷工具写入内部 eMMC。**不能把 `update.img` 当作 SD 卡镜像写入 TF 卡。** 线刷会覆盖 eMMC 上的现有数据，请先备份并确认设备进入 Loader/Maskrom 模式。

## 使用

在 [Actions 页面](https://github.com/IxsCN/Actions-LubanCat-Q1-Alpine/actions) 选择 **Build LubanCat Q1 Alpine images → Run workflow**。Linux x86_64 Ubuntu 22.04 runner 构建 SD 镜像后，使用野火 SDK 对应的 `package-file-extboot`、`parameter-extboot.txt`、`afptool` 和 `rkImageMaker` 打包 Rockchip `update.img`。两个附件都成功上传后，发布工作流才会创建预发布 Release；构建失败不会发布不完整镜像。若线刷打包失败，SD Artifact 仍可从构建页面下载。已有成功构建也可手动运行 **Publish LubanCat Q1 Alpine images** 并填写原构建 run ID 发布，无需重新编译。

启动串口：**1500000 8N1，3.3V TTL**。root 默认密码 `fa`，SSH 禁止 root 登录；首次从物理串口登录后立即修改密码，再按需配置 SSH。Tailscale 只预装，不自动登录。

## 第一次上板重点核对

1. 串口输出有没有进入 U-Boot、显示的启动设备和 DTB 是否正确。
2. Linux 是否找到 `rootfs` PARTUUID，`mount` 与 `lsblk` 是否显示正确分区。
3. 网口、DHCP、USB、eMMC（只读检查）、Wi-Fi 的识别和驱动状态。
4. `/sys/kernel/btf/vmlinux`、`zcat /proc/config.gz` 与 `bpftool feature probe kernel`。
5. 再安装并启动 dae 做真实流量测试；本项目暂不预装 dae。

**尚未验证的风险**：板上启动路径是否选择该 extboot 分区、Alpine 无 initramfs 时必需的存储驱动是否内建、Rockchip 线刷包是否适配你的 eMMC 配置，以及供应商 BSP 与 dae 的真实运行兼容性。构建通过不等于可启动；出现故障请从上电开始保存完整串口日志。

## 代码入口

- `.github/workflows/build.yml`：手动构建并分别上传 SD 和线刷 Artifact。
- `.github/workflows/release.yml`：成功构建后自动发布预发布 Release，也支持通过构建 run ID 补发。
- `scripts/pack-emmc.sh`：使用野火原厂分区描述与打包工具生成 USB 线刷 `update.img`。
- `scripts/build-image.sh`：下载、编译、rootfs 和文件系统生成。
- `scripts/pack-sd.py`：按 Q1 参数分区布局生成 GPT SD 镜像。
- `configs/dae.config`：内核增量配置。

上游参数参考：[Q1 硬件文档](https://doc.embedfire.com/linux/rk352x/quick_start/zh/latest/quick_start/lubancat/lubancat-q1.html) · [野火 RK3528 分区参数](https://github.com/LubanCat/device_rockchip/blob/main/.chips/rk3528/parameter-extboot.txt)。
