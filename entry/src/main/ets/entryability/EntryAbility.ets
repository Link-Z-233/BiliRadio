/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { Appearance } from '../service/Appearance';
import { Constants } from '../service/Constants';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 读取持久化外观偏好（自行 getPreferencesSync，不依赖 AppStore.init 时机）并应用应用层颜色模式；
    // 无偏好或读取失败时回退为跟随系统（COLOR_MODE_NOT_SET，与原固定行为一致）
    Appearance.init(this.context);
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 1. 获取应用主窗口
    const mainWindow: window.Window = windowStage.getMainWindowSync();
    this.mainWindow = mainWindow;

    // 注册全局避让区变化监听（旋转/折叠/窗口模式切换时动态刷新）
    this.registerAvoidAreaListener(mainWindow);

    // 2. 沉浸式方式二：全屏布局 + 系统栏透明；窗口背景与状态栏/导航栏前景色按当前生效外观设置
    mainWindow.setWindowLayoutFullScreen(true)
      .then(() => {
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Succeeded in setting the window layout to full-screen mode.');
        // 全屏布局生效后窗口背景色才能设置成功（过早调用会报 1300002）；
        // 窗口层颜色无法用资源目录自动匹配，由 Appearance 按生效外观手动映射深/浅色值
        Appearance.attachWindow(mainWindow);
        // 全屏布局生效后再同步避让区（过早查询会得到 0）
        this.syncAvoidArea(mainWindow);
      })
      .catch((err: BusinessError) => {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to setup immersive window. Code: %{public}d, message: %{public}s',
          err.code, err.message);
        // 沉浸式失败时回退为非全屏布局：页面内容交由系统避让，不再手动留白
        AppStorage.setOrCreate<number>(Constants.AS_STATUS_BAR_HEIGHT, 0);
        AppStorage.setOrCreate<number>(Constants.AS_NAV_BAR_HEIGHT, 0);
      });

    // 3. 加载沉浸式窗口的具体内容
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow !== undefined) {
      try {
        this.mainWindow.off('avoidAreaChange');
      } catch (err) {
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to off avoidAreaChange. Cause: %{public}s', JSON.stringify(err));
      }
      this.mainWindow = undefined;
    }
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onBackground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', 'Ability onConfigurationUpdate');
    // 系统深浅色变化：仅「跟随系统」外观时联动窗口层颜色；
    // 强制浅/深时保持用户选择不变，但窗口层始终与当前生效外观一致
    Appearance.handleConfiguration(newConfig, this.context);
  }

  private registerAvoidAreaListener(mainWindow: window.Window): void {
    try {
      mainWindow.on('avoidAreaChange', () => {
        this.syncAvoidArea(mainWindow);
      });
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to register avoidAreaChange. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private syncAvoidArea(mainWindow: window.Window): void {
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels;
      if (density <= 0) {
        return;
      }
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicatorArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx: number = systemArea.topRect.height;
      const bottomPx: number = indicatorArea.bottomRect.height > 0 ?
        indicatorArea.bottomRect.height : systemArea.bottomRect.height;
      if (topPx > 0) {
        AppStorage.setOrCreate<number>(Constants.AS_STATUS_BAR_HEIGHT, topPx / density);
      }
      AppStorage.setOrCreate<number>(Constants.AS_NAV_BAR_HEIGHT, bottomPx > 0 ? bottomPx / density : 0);
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'AvoidArea synced: topPx=%{public}d, bottomPx=%{public}d, density=%{public}s',
        topPx, bottomPx, `${density}`);
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Failed to sync avoid area. Cause: %{public}s', JSON.stringify(err));
    }
  }
};
