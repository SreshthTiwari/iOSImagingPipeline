import React from 'react';
import {Image, Modal, StyleSheet, TouchableOpacity, View, Text} from 'react-native';

type Props = {
  visible: boolean;
  imageUri: string | null;
  onClose: () => void;
};

export default function FullscreenImageModal({visible, imageUri, onClose}: Props) {
  return (
    <Modal
      visible={visible}
      transparent={false}
      animationType="fade"
      onRequestClose={onClose}>
      <View style={styles.container}>
        {imageUri ? (
          <Image source={{uri: imageUri}} style={styles.image} resizeMode="contain" />
        ) : (
          <View style={styles.emptyContainer}>
            <Text style={styles.emptyText}>No image to display</Text>
          </View>
        )}
        <TouchableOpacity style={styles.closeButton} onPress={onClose}>
          <Text style={styles.closeText}>✕ Close</Text>
        </TouchableOpacity>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    color: '#fff',
    fontSize: 16,
  },
  closeButton: {
    position: 'absolute',
    top: 50,
    right: 20,
    backgroundColor: 'rgba(0,0,0,0.7)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
  },
  closeText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
});
