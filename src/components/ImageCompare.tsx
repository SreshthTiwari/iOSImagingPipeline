import React from 'react';
import {Image, StyleSheet, Text, View} from 'react-native';

type Props = {
  leftUri: string;
  rightUri: string | null;
};

export default function ImageCompare({leftUri, rightUri}: Props) {
  return (
    <View style={styles.container}>
      <View style={styles.column}>
        <Text style={styles.label}>Original</Text>
        <Image source={{uri: leftUri}} style={styles.image} resizeMode="cover" />
      </View>

      <View style={styles.column}>
        <Text style={styles.label}>Processed</Text>
        {rightUri ? (
          <Image source={{uri: rightUri}} style={styles.image} resizeMode="cover" />
        ) : (
          <View style={[styles.image, styles.empty]}>
            <Text style={styles.emptyText}>No processed image</Text>
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    flexDirection: 'row',
  },
  column: {
    flex: 1,
  },
  label: {
    color: '#fff',
    padding: 10,
    fontWeight: '600',
    backgroundColor: '#22232c',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  empty: {
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1b1b24',
  },
  emptyText: {
    color: '#aaa',
  },
});