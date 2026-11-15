# dsh_sui

我的 DSH（DeepSeek Harness）相关配置与笔记。

## 这是什么

一个长期的个人仓库，用来存放我在 DSH 上的所有东西：配置、自定义人格、脚本、踩坑记录。
内容基本都是 DSH 相关，不打算放别的类型。

## 目录

| 目录 | 内容 |
|---|---|
| `docs/` | 配置说明、操作记录、踩坑笔记 |
| `scripts/` | 可复用的小脚本（备份、检查、同步） |
| `private/` | **只在本机用、不推送的私人内容**（见下） |

## 重要：private/ 不进仓库

`private/` 在 `.gitignore` 里被整目录挡住。人格卡、凭据备忘、本机路径这类东西放进去，
**永远不会被 commit、更不会被 push**。

需要同步到别的机器时，手动拷这个目录，不走 git。

## 环境

- Windows，DSH 桌面版（nightly 通道）
- profile：`dsh-profile-desktop`，18 个 bundle
- 主要插件：surfcore（QQ × B站 桥接）、dsh-bilibili、dsh-memewiki、dsh-free-search

## 约定

- 提交信息写「现象 + 修法」，不写 `update` / `fix` 这种空话
- 改动前先看清楚影响面，别顺手重构无关的东西
- 这个仓库是**公开**的，提交前确认没有私人信息混进去
