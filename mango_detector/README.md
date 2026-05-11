# Mango Maturity Detector - Edge AI Application

Aplikasi Android Flutter untuk deteksi kematangan mangga secara real-time menggunakan **TensorFlow Lite** dengan processing langsung di device (Edge AI).

## Visualisasi Hasil Deteksi
Berikut adalah tampilan aplikasi dan hasil pengujian terhadap berbagai kondisi kematangan mangga:
<img width="400" alt="Screenshot_2026-05-11-19-38-19-15_e05d74172ce9f6b75495cf07afa51f25" src="https://github.com/user-attachments/assets/21279202-a531-4f83-87a3-c3bef3184f55" />
<img width="400" alt="Screenshot_2026-05-11-19-40-06-59_e05d74172ce9f6b75495cf07afa51f25" src="https://github.com/user-attachments/assets/e0b6d2b1-c638-4e69-92ae-6a0abe9b927e" />
<img width="400" alt="Screenshot_2026-05-11-19-38-35-61_e05d74172ce9f6b75495cf07afa51f25" src="https://github.com/user-attachments/assets/297c119e-9af7-4e6c-ba08-4c7b91279abf" />
<img width="400" alt="Screenshot_2026-05-11-19-37-52-13_e05d74172ce9f6b75495cf07afa51f25" src="https://github.com/user-attachments/assets/718fcbf0-72c3-4afc-9058-16d3e4da4ce8" />


## Fitur Utama

### Live Detection Preview
- Kamera secara otomatis melakukan deteksi real-time
- Hasil deteksi ditampilkan di layar atas dengan:
  - Label hasil (kategori mangga atau "Bukan Mangga")
  - Confidence score dalam persen
  - Warna indicator: Hijau = Mangga, Merah = Bukan Mangga

### Smart "Bukan Mangga" Detection
- Threshold confidence **60%** untuk mengklasifikasi object
- Jika confidence < 60% → "Bukan Mangga" (merah)
- Jika confidence ≥ 60% → Kategori mangga spesifik (hijau)

### Galeri Photo Picker
- Tombol **"Galeri"** untuk mengambil foto dari storage
- Deteksi otomatis pada foto yang dipilih
- Menampilkan hasil dalam dialog dengan preview gambar

### Capture & Report
- Tombol **"Capture"** untuk ambil foto langsung dari kamera
- Hasil deteksi detail dengan confidence score tinggi
- Dialog dengan preview gambar terambil

### Optimized Performance
- Inference berjalan **asinkron** tanpa mengganggu UI
- Live detection tidak menghentikan camera stream
- Cocok untuk penggunaan di smartphone biasa

## Tech Stack

- **Framework**: Flutter 3.41.2
- **Language**: Dart 3.11.0
- **AI/ML**: TensorFlow Lite (model_mangga.tflite)
- **Camera**: camera ^0.11.0
- **Image Processing**: image ^4.1.3, image_picker ^1.0.7
- **Permissions**: permission_handler ^11.3.0

## Quick Start

### Prerequisites
- Flutter SDK ≥ 3.11.0
- Android SDK ≥ API 21
- Java JDK 17+

### Installation

```bash
# Clone atau download project
cd D:\mango_detector

# Install dependencies
flutter pub get

# Run di emulator/device
flutter run

# Build APK
flutter build apk --debug

# Build Release
flutter build apk --release
```

### APK Output
```
Debug:   build/app/outputs/flutter-apk/app-debug.apk
Release: build/app/outputs/flutter-apk/app-release.apk
```

## Cara Menggunakan

1. **Buka Aplikasi**
   - Izinkan akses kamera saat diminta

2. **Live Preview**
   - Arahkan kamera ke mangga atau object
   - Hasil deteksi update otomatis di bagian atas layar

3. **Ambil Foto (Capture)**
   - Tekan tombol orange **"Capture"**
   - Lihat hasil detail dalam dialog

4. **Dari Galeri**
   - Tekan tombol biru **"Galeri"**
   - Pilih foto dari storage
   - Lihat hasil deteksi otomatis

## Model Information

### Kategori Deteksi:
1. **ripeMango** - Mangga matang
2. **RawMango ripeMango** - Mangga yang sedang masak
3. **RawMango** - Mangga mentah
4. **RawMango bad mango** - Mangga mentah rusak
5. **bad mango** - Mangga rusak
6. **non_mango** - Bukan mangga (auto-reject)

### Confidence Threshold
- Saat ini: **60%** (dapat disesuaikan di `_confidenceThreshold`)
- Lebih tinggi (0.8) = Lebih ketat
- Lebih rendah (0.5) = Lebih permisif

## Customization

### Ubah Confidence Threshold
```dart
// Di _MangoDetectorState class
static const double _threshold = 0.6; // Ubah ke nilai lain
```

### Ubah Resolusi Kamera
```dart
// Di initState()
_controller = CameraController(
  widget.camera, 
  ResolutionPreset.medium // Ubah ke high/low sesuai kebutuhan
);
```

## Permissions

Aplikasi memerlukan:
- **CAMERA**: Akses kamera perangkat
- **READ_EXTERNAL_STORAGE**: Baca foto dari galeri (Android ≤ 12)
- **READ_MEDIA_IMAGES**: Akses foto dari galeri (Android 13+)

Semua permission sudah dikonfigurasi di `AndroidManifest.xml`.

## File Penting

- `lib/main.dart` - Seluruh kode aplikasi + logic deteksi
- `assets/model_mangga.tflite` - Model TFLite terlatih
_- `assets/labels.txt` - Daftar label kelas deteksi_
- `manggodetection.ipynb` - Notebook pengembangan model



