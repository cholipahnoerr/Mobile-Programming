// lib/models/expense_model.dart

class CategoryModel {
  final int? id;
  final String name;
  final String icon;

  CategoryModel({this.id, required this.name, required this.icon});

  // Konversi dari Map (SQLite) ke Object
  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
    );
  }

  // Konversi dari Object ke Map (Untuk Simpan ke SQLite)
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'icon': icon};
  }
}

class TransactionModel {
  final int? id;
  final String title;
  final String amount;
  final String imagePath;
  final int? categoryId;
  final String? categoryName; // Helper untuk join query

  TransactionModel({
    this.id,
    required this.title,
    required this.amount,
    required this.imagePath,
    this.categoryId,
    this.categoryName,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      title: map['title'],
      amount: map['amount'],
      imagePath: map['imagePath'],
      categoryId: map['category_id'],
      categoryName: map['categoryName'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'imagePath': imagePath,
      'category_id': categoryId,
    };
  }
}