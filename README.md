# Actions LubanCat Q1 Alpine

为野火 **LubanCat Q1（RK3528A）** 准备的独立 Alpine Linux 3.23 ARM64 SD 卡镜像构建原型。与 FriendlyElec 的 NanoPi 构建仓库独立，使用 [LubanCat 内核及 Q1 设备树](https://github.com/LubanCat/kernel)、[U-Boot](https://github.com/LubanCat/u-boot) 和 [rkbin](https://github.com/LubanCat/rkbin)。

**状态：本地构建脚本及镜像打包器已实现，尚未在 GitHub Actions 全程编译，也未上板验证。请把首次产物当作实验镜像，不要覆盖原来的可启动系统。**

## 构建内容

- 野火 Linux 6.1 `lubancat_linux_rk3528_defconfig`，编译 `rk3528-lubancat-q1.dtb`；合并 `configs/dae.config` 并检查最终 eBPF、BTF 和 TC 配置及 vmlinux 的 `.BTF`。
- 野火 U-Boot `rk3528` 配置，使用同仓库的 rkbin 构建 loader。
- Alpine 3.23 aarch64 minirootfs，OpenRC、SSH、DHCP、`htop`、`tio`、`kitty-terminfo`、`tailscale`；内核模块与内核版本配套。
- SD 镜像包含 Rockchip loader（LBA 64）、GPT 分区 `uboot`（LBA `0x4000`）、`boot`（`0x8000`）和 `rootfs`（`0x48000`），根分区 UUID 与野火 `parameter-extboot.txt` 一致。
- `boot` 是 ext2 分区，放置野火的启动脚本、Image、Q1 DTB、uEnv；无 initrd，直接从 ext4 挂载 Alpine rootfs。

**首次测试先用 TF 卡，不生成自动刷 eMMC 镜像。** 当前工作流仅上传 GitHub Actions Artifact（保留 14 天），不创建 Release。

## 使用

在自己创建的新 GitHub 仓库中提交本项目并启用 Actions，通过 **Build LubanCat Q1 Alpine SD image → Run workflow** 手动运行。Linux x86_64 Ubuntu 22.04 runner 会安装构建工具，随后执行 `scripts/build-image.sh`。成功后从运行页面的 Artifact 下载 `lubancat-q1-alpine-sd`。

启动串口：**1500000 8N1，3.3V TTL**。root 默认密码 `fa`，SSH 禁止 root 登录；首次从物理串口登录后立即修改密码，再按需配置 SSH。Tailscale 只预装，不自动登录。

## 第一次上板重点核对

1. 串口输出有没有进入 U-Boot、显示的启动设备和 DTB 是否正确。
2. Linux 是否找到 `rootfs` PARTUUID，`mount` 与 `lsblk` 是否显示正确分区。
3. 网口、DHCP、USB、eMMC（只读检查）、Wi-Fi 的识别和驱动状态。
4. `/sys/kernel/btf/vmlinux`、`zcat /proc/config.gz` 与 `bpftool feature probe kernel`。
5. 再安装并启动 dae 做真实流量测试；本项目暂不预装 dae。

**尚未验证的风险**：野火 U-Boot 与 rkbin 在 GitHub runner 上的工具依赖、板上启动路径是否选择该 extboot 分区、Alpine 无 initramfs 时必需的存储驱动是否内建，以及供应商 BSP 与 dae 的真实运行兼容性。构建通过不等于可启动；出现故障请从上电开始保存完整串口日志。

## 代码入口

- `.github/workflows/build.yml`：手动构建并上传 Artifact。
- `scripts/build-image.sh`：下载、编译、rootfs 和文件系统生成。
- `scripts/pack-sd.py`：按 Q1 参数分区布局生成 GPT SD 镜像。
- `configs/dae.config`：内核增量配置。

上游参数参考：[Q1 硬件文档](https://doc.embedfire.com/linux/rk352x/quick_start/zh/latest/quick_start/lubancat/lubancat-q1.html) · [野火 RK3528 分区参数](https://github.com/LubanCat/device_rockchip/blob/main/.chips/rk3528/parameter-extboot.txt)。
