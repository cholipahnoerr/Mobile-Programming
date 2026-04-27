import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;

import 'login_screen.dart';
import '../models/expense_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TransactionModel> _transactions = [];
  List<CategoryModel> _categories = [];
  final DatabaseService _dbService = DatabaseService();
  final NotificationService _notifService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notifService.init(); // Inisialisasi notif lewat service
    _refreshData();

  }

  Future<void> _setupTimeZone() async {
    tz.initializeTimeZones();
    try {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZone.toString()));
    } catch (e) {
      debugPrint("TimeZone Error: $e");
    }
  }

  Future<void> _refreshData() async {
    final txData = await _dbService.getTransactions();
    final catData = await _dbService.getCategories();
    if (!mounted) return;
    setState(() {
      _transactions = txData;
      _categories = catData;
    });
  }

  // ================= FORM INPUT =================
  Future<void> _showForm(TransactionModel? model) async {
    final titleController = TextEditingController(text: model?.title ?? '');
    final amountController = TextEditingController(text: model?.amount ?? '');
    int? selectedCategoryId = model?.categoryId;
    String? imagePath = model?.imagePath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Nama Pengeluaran')),
              TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Nominal'), keyboardType: TextInputType.number),
              DropdownButton<int>(
                hint: const Text("Pilih Kategori"),
                value: selectedCategoryId,
                isExpanded: true,
                items: _categories.map((c) => DropdownMenuItem<int>(
                  value: c.id,
                  child: Text(c.name),
                )).toList(),
                onChanged: (v) => setModalState(() => selectedCategoryId = v),
              ),
              const SizedBox(height: 10),
              imagePath != null && imagePath != ''
                  ? Image.file(File(imagePath!), height: 80)
                  : const Text("Belum ada struk"),
              TextButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text("Ambil Foto Struk"),
                onPressed: () async {
                  final file = await ImagePicker().pickImage(source: ImageSource.camera);
                  if (file != null) setModalState(() => imagePath = file.path);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final data = TransactionModel(
                    id: model?.id,
                    title: titleController.text,
                    amount: amountController.text,
                    imagePath: imagePath ?? '',
                    categoryId: selectedCategoryId,
                  );
                  if (model == null) {
                    await _dbService.insertTransaction(data);
                  } else {
                    await _dbService.updateTransaction(data);
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                  await _refreshData();
                  _backupToCloud();
                },
                child: Text(model == null ? 'Simpan' : 'Update'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      }),
    );
  }

  // ================= BACKUP CLOUD =================
  Future<void> _backupToCloud() async {
    // 1. Munculkan loading (tutup ini nanti di akhir)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) Navigator.pop(context);
        debugPrint("Backup dibatalkan: User belum login");
        return;
      }

      List<Map<String, dynamic>> cloudData = [];

      for (var tx in _transactions) {
        String remoteUrl = "";

        // Try-catch kecil khusus buat Storage
        // Supaya kalau 1 gambar gagal, data teks lainnya tetep bisa ke-backup
        if (tx.imagePath.isNotEmpty && File(tx.imagePath).existsSync()) {
          try {
            final ref = FirebaseStorage.instance.ref().child('receipts/${p.basename(tx.imagePath)}');
            await ref.putFile(File(tx.imagePath));
            remoteUrl = await ref.getDownloadURL();
          } catch (storageError) {
            debugPrint("Error uploading image for ${tx.title}: $storageError");
          }
        }

        cloudData.add({
          ...tx.toMap(),
          'categoryName': tx.categoryName ?? 'Tanpa Kategori',
          'cloudImageUrl': remoteUrl,
        });
      }

      // 2. Tembak ke Firestore
      await FirebaseFirestore.instance.collection('backups').doc(user.uid).set({
        'transactions': cloudData,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint("✅ Backup Berhasil ke Firebase!");

      // 3. Berhasil: Tutup loading dan kasih snackbar
      if (!mounted) return;
      Navigator.pop(context); // Tutup loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Backup Berhasil!"), backgroundColor: Colors.green),
      );

    } catch (e) {
      // 4. Gagal: Log error, tutup loading, dan kasih snackbar gagal
      debugPrint("❌ Backup Gagal total: $e");

      if (!mounted) return;
      Navigator.pop(context); // Pastikan loading ditutup meski error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Backup Gagal!"), backgroundColor: Colors.red),
      );
    }
  }

  // ================= UI BUILDER =================
  @override
  Widget build(BuildContext context) {
    double totalSpending = _transactions.fold(0.0, (acc, item) => acc + (double.tryParse(item.amount) ?? 0.0));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Money Manager Lite"),
        actions: [
          IconButton(icon: const Icon(Icons.category), onPressed: _manageCategoriesDialog),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async {
            await FirebaseAuth.instance.signOut();
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          }),
        ],
      ),
      body: Column(
        children: [
          _buildTotalCard(totalSpending),
          _buildChart(),
          Expanded(child: _buildTransactionList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showForm(null), child: const Icon(Icons.add)),
    );
  }

  Widget _buildTotalCard(double total) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.blue.shade800, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Total Pengeluaran", style: TextStyle(color: Colors.white70)),
          Text("Rp ${total.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return SizedBox(
      height: 150,
      child: _transactions.isEmpty
          ? const Center(child: Text("Belum ada data"))
          : PieChart(PieChartData(sections: _transactions.map((tx) {
        return PieChartSectionData(
          value: double.tryParse(tx.amount) ?? 0,
          title: tx.title, radius: 30,
          color: Colors.primaries[_transactions.indexOf(tx) % Colors.primaries.length],
        );
      }).toList())),
    );
  }

  Widget _buildTransactionList() {
    return ListView.builder(
      itemCount: _transactions.length,
      itemBuilder: (context, i) {
        final tx = _transactions[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.payments)),
          title: Text(tx.title),
          subtitle: Text("Rp ${tx.amount} - ${tx.categoryName ?? 'Tanpa Kategori'}"),
          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
            await _dbService.deleteTransaction(tx.id!);
            _refreshData();
          }),
          onTap: () => _showForm(tx),
        );
      },
    );
  }

  // ================= DIALOGS =================
  Future<void> _manageCategoriesDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Kelola Kategori"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return ListTile(
                  title: Text(cat.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.orange), onPressed: () async {
                        await _showCategoryDialog(model: cat);
                        setDialogState(() {});
                      }),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                        await _dbService.deleteCategory(cat.id!);
                        await _refreshData();
                        setDialogState(() {});
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup")),
            ElevatedButton(onPressed: () async {
              await _showCategoryDialog();
              setDialogState(() {});
            }, child: const Text("Tambah Baru")),
          ],
        ),
      ),
    );
  }

  Future<void> _showCategoryDialog({CategoryModel? model}) async {
    final controller = TextEditingController(text: model?.name ?? '');
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(model == null ? 'Tambah Kategori' : 'Edit Kategori'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nama Kategori')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final cat = CategoryModel(id: model?.id, name: controller.text.trim(), icon: 'category');
                if (model == null) {
                  await _dbService.insertCategory(cat);
                } else {
                  await _dbService.updateCategory(cat);
                }
                await _refreshData();
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }
}