import { common } from '@kit.AbilityKit';

export class AppContext {
  private static context: common.UIAbilityContext | undefined = undefined;

  static init(context: common.UIAbilityContext): void {
    AppContext.context = context;
  }

  static require(): common.UIAbilityContext {
    if (AppContext.context === undefined) {
      throw new Error('AppContext not initialized');
    }
    return AppContext.context;
  }
}
