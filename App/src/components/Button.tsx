import React from 'react';
import {Pressable, StyleSheet, Text, ViewStyle} from 'react-native';

type Props = {
  title: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary';
  style?: ViewStyle;
};

export default function Button({
  title,
  onPress,
  variant = 'primary',
  style,
}: Props) {
  const isSecondary = variant === 'secondary';

  return (
    <Pressable
      onPress={onPress}
      style={({pressed}) => [
        styles.button,
        isSecondary ? styles.secondary : styles.primary,
        pressed && styles.pressed,
        style,
      ]}>
      <Text style={[styles.text, isSecondary && styles.secondaryText]}>
        {title}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primary: {
    backgroundColor: '#4f7cff',
  },
  secondary: {
    backgroundColor: '#262633',
    borderWidth: 1,
    borderColor: '#3a3a4a',
  },
  pressed: {
    opacity: 0.85,
    transform: [{scale: 0.99}],
  },
  text: {
    color: '#fff',
    fontWeight: '700',
  },
  secondaryText: {
    color: '#eaeaea',
  },
});