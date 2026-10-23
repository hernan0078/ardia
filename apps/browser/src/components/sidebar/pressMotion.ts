import { useEffect, useRef } from "react";
import { AccessibilityInfo, Animated } from "react-native";

let reduceMotion = true;
const moving = new Set<Animated.Value>();
const setReduceMotion = (on: boolean) => {
  reduceMotion = on;
  if (!on) return;
  for (const value of moving) {
    value.stopAnimation();
    value.setValue(1);
  }
  moving.clear();
};
AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion, () => {});
AccessibilityInfo.addEventListener("reduceMotionChanged", setReduceMotion);

export function usePressMotion(disabled = false) {
  const scale = useRef(new Animated.Value(1)).current;
  useEffect(() => () => {
    scale.stopAnimation();
    moving.delete(scale);
  }, [scale]);
  const release = () => {
    scale.stopAnimation();
    if (reduceMotion || disabled) {
      scale.setValue(1);
      moving.delete(scale);
      return;
    }
    Animated.spring(scale, { toValue: 1, speed: 24, bounciness: 5, useNativeDriver: true }).start(({ finished }) => {
      if (finished) moving.delete(scale);
    });
  };
  return {
    style: { transform: [{ scale }] },
    onPressIn: () => {
      if (reduceMotion || disabled) return;
      scale.stopAnimation();
      moving.add(scale);
      Animated.timing(scale, { toValue: 0.97, duration: 80, useNativeDriver: true }).start();
    },
    onPressOut: release,
  };
}
