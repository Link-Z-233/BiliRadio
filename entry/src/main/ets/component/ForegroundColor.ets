// 前景取色工具：直接映射到随资源目录自动切换的文字颜色资源。
// 深色目录 text_primary=白、浅色目录 text_primary=黑，由系统按当前颜色模式自动匹配，
// 与页面背景同一套机制，不再依赖 coverIsDark 布尔探测（冷启动「跟随系统」时探测过早会深浅误判，
// 曾导致深色模式下文字用了浅色前景）。
// 保留 isDark 形参仅为了不改动各调用页面；本工具已不使用该参数。

export class ForegroundColor {
  static primary(isDark: boolean): Resource {
    return $r('app.color.text_primary');
  }

  static secondary(isDark: boolean): Resource {
    return $r('app.color.text_secondary');
  }

  static disabled(isDark: boolean): Resource {
    return $r('app.color.text_disabled');
  }
}