import { motion } from '@kit.MultimodalAwarenessKit';
import { Constants } from './Constants';

const LEFT_ZONE_MAX_RATIO: number = 0.4;
const RIGHT_ZONE_MIN_RATIO: number = 0.6;
const SWITCH_VOTE_COUNT: number = 2;
const MAX_VOTES: number = 9;

export class GripDetector {
  private static leftVotes: number = 0;
  private static rightVotes: number = 0;
  private static listening: boolean = false;
  private static holdingActive: boolean = false;
  private static operatingActive: boolean = false;
  // 已有明确的单手握持结果时，操作手结果不参与定位
  private static holdingKnown: boolean = false;

  private static holdingCallback: Callback<motion.HoldingHandStatus> =
    (status: motion.HoldingHandStatus): void => {
      GripDetector.onHoldingHand(status);
    };

  private static operatingCallback: Callback<motion.OperatingHandStatus> =
    (status: motion.OperatingHandStatus): void => {
      GripDetector.onOperatingHand(status);
    };

  static isRightHanded(): boolean {
    const stored: boolean | undefined = AppStorage.get<boolean>(Constants.AS_GRIP_ON_RIGHT);
    return stored !== undefined ? stored : true;
  }

  static start(): void {
    if (GripDetector.listening) {
      return;
    }
    GripDetector.listening = true;
    try {
      motion.on('holdingHandChanged', GripDetector.holdingCallback);
      GripDetector.holdingActive = true;
    } catch (e) {
      // 设备不支持智感握姿（错误码801）时降级
      GripDetector.holdingActive = false;
    }
    try {
      motion.on('operatingHandChanged', GripDetector.operatingCallback);
      GripDetector.operatingActive = true;
    } catch (e) {
      GripDetector.operatingActive = false;
    }
    if (GripDetector.operatingActive) {
      try {
        GripDetector.applyOperatingHand(motion.getRecentOperatingHandStatus());
      } catch (e) {
        // 暂无缓存结果，等待感知事件上报
      }
    }
  }

  static stop(): void {
    if (!GripDetector.listening) {
      return;
    }
    try {
      motion.off('holdingHandChanged');
    } catch (e) {
      GripDetector.holdingActive = false;
    }
    try {
      motion.off('operatingHandChanged');
    } catch (e) {
      GripDetector.operatingActive = false;
    }
    GripDetector.holdingActive = false;
    GripDetector.operatingActive = false;
    GripDetector.holdingKnown = false;
    GripDetector.listening = false;
  }

  static reportTouch(x: number, pageWidth: number): void {
    if (GripDetector.holdingActive || GripDetector.operatingActive) {
      return;
    }
    if (pageWidth <= 0) {
      return;
    }
    const ratio: number = x / pageWidth;
    if (ratio > LEFT_ZONE_MAX_RATIO && ratio < RIGHT_ZONE_MIN_RATIO) {
      return;
    }
    const onRight: boolean = ratio >= RIGHT_ZONE_MIN_RATIO;
    if (onRight) {
      GripDetector.rightVotes = Math.min(GripDetector.rightVotes + 1, MAX_VOTES);
      GripDetector.leftVotes = 0;
    } else {
      GripDetector.leftVotes = Math.min(GripDetector.leftVotes + 1, MAX_VOTES);
      GripDetector.rightVotes = 0;
    }
    if (GripDetector.isRightHanded() === onRight) {
      return;
    }
    const votes: number = onRight ? GripDetector.rightVotes : GripDetector.leftVotes;
    if (votes >= SWITCH_VOTE_COUNT) {
      AppStorage.setOrCreate(Constants.AS_GRIP_ON_RIGHT, onRight);
    }
  }

  private static onHoldingHand(status: motion.HoldingHandStatus): void {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      GripDetector.holdingKnown = true;
      GripDetector.applySide(false);
    } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      GripDetector.holdingKnown = true;
      GripDetector.applySide(true);
    } else {
      // 未握持/双手/未知：保持当前侧，改由操作手结果接管
      GripDetector.holdingKnown = false;
    }
  }

  private static onOperatingHand(status: motion.OperatingHandStatus): void {
    if (GripDetector.holdingKnown) {
      return;
    }
    GripDetector.applyOperatingHand(status);
  }

  private static applyOperatingHand(status: motion.OperatingHandStatus): void {
    if (status === motion.OperatingHandStatus.LEFT_HAND_OPERATED) {
      GripDetector.applySide(false);
    } else if (status === motion.OperatingHandStatus.RIGHT_HAND_OPERATED) {
      GripDetector.applySide(true);
    }
  }

  private static applySide(onRight: boolean): void {
    if (GripDetector.isRightHanded() !== onRight) {
      AppStorage.setOrCreate(Constants.AS_GRIP_ON_RIGHT, onRight);
    }
  }
}
