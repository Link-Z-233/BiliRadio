import { uiEffect } from '@kit.ArkGraphics2D';
import { liquidLightEffect, lightSourceEffect, illuminatedEffect } from './LightEffect';

// 按钮点光源交互辅助：收敛各页面重复的「按压状态 → 点光源效果」映射逻辑。
// 页面仍持有 @State litBtn / pressForce（保证状态变化触发重渲染），仅在此复用效果工厂与按压状态计算。
export class LitButton {
  // 非液态按压状态计算：Down 点亮该按钮，Up/Cancel 熄灭，返回切换后的 litBtn 值
  static press(id: string, current: string, event: TouchEvent): string {
    if (event.type === TouchType.Down) {
      return id;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (current === id) {
        return '';
      }
    }
    return current;
  }

  // 根据按压按钮 id 与当前点亮 id 返回对应点光源效果；liquid 时使用液态点光源（强度 pressForce 连续可调）
  static effectFor(pressedId: string, litBtn: string, liquid: boolean, pressForce: number): uiEffect.VisualEffect {
    if (litBtn === pressedId) {
      return liquid ? liquidLightEffect(pressForce) : lightSourceEffect();
    }
    return illuminatedEffect();
  }
}