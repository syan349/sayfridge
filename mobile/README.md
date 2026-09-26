# SayFridge Mobile

SayFridge 的 Flutter 手机端，面向 Android 和 iOS，包含登录注册、首页、库存、AI Assistant 和 Profile 页面。

## 环境要求

- Flutter SDK
- Android Studio / Android SDK（Android 开发）
- Xcode（iOS 开发，仅 macOS）

## 本地运行

```bash
flutter pub get
flutter run
```

## 基础检查

```bash
flutter analyze
flutter test
```

应用包名：`com.appix.sayfridge`。

## Profile 页面

- 游客和登录用户均可从 Home / AI Assistant 的底部导航进入 Profile。
- 游客点击锁定菜单或登录按钮会进入登录页；登录成功返回 Profile。
- 登录后可进入个人资料、密码重置、提醒设置、语音用量页；子页返回 Profile。
- 姓名、头像、提醒开关、提前天数和时间通过 `ProfilePreferencesRepository` 按用户 ID 保存在本机，未同步到后端。保存失败会提示，取消编辑不覆盖已保存的资料。
- 登录邮箱由后端管理；当前没有邮箱或密码修改 API，界面不会伪造修改成功。密码只存在于表单内存中。
- 提醒偏好可保存，但当前版本没有系统通知权限及通知调度实现；设备通知行显示 `Not available`。
- 效果图以 requests 统计语音额度；当前后端模型的 `voice_*_seconds` 以秒计量，且 `/auth/me` 不返回这些字段。生产页面显示用量暂不可用，待确认请求次数接口后传入 `VoiceUsage`。测试中的 12 / 50 仅用于效果图核对。

Profile 跳转、表单校验、本地保存、账号切换隔离和小屏布局测试在 `test/screens/profile_flow_test.dart` 与 `test/state/profile_controller_test.dart`。
