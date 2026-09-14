import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const RinaAdminApp());
}

class RinaAdminApp extends StatelessWidget {
  const RinaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Rina's Collection Admin",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7B3F51)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoginScreen();
        }
        return const _AdminGate();
      },
    );
  }
}

class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('adminUsers')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AccessDeniedScreen(
            message: 'Unable to verify admin access. Check Firestore rules.',
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isAdmin =
            snapshot.data!.exists && snapshot.data!.data()?['enabled'] == true;
        if (!isAdmin) {
          return const AccessDeniedScreen();
        }
        return const DashboardScreen();
      },
    );
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _sortFilter = 'Newest first';
  String _dateFilter = 'All time';

  static const _dateFilters = [
    'All time',
    'Today',
    'Last 7 days',
    'Last 30 days',
  ];

  @override
  Widget build(BuildContext context) {
    final orders = FirebaseFirestore.instance.collection('orders').snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: orders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load orders.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final documents =
              snapshot.data!.docs.where((document) {
                final data = document.data();
                final customer =
                    data['customer'] as Map<String, dynamic>? ?? {};
                final query = _searchQuery.trim().toLowerCase();
                final searchable = [
                  data['orderNumber'],
                  customer['name'],
                  customer['email'],
                  customer['phone'],
                ].whereType<String>().join(' ').toLowerCase();
                final status = data['status'] as String? ?? 'pending';
                final createdAt = _createdAt(data['createdAt']);
                return (query.isEmpty || searchable.contains(query)) &&
                    (_statusFilter == 'All' || status == _statusFilter) &&
                    _matchesDateFilter(createdAt);
              }).toList()..sort((a, b) {
                final aDate = _createdAt(a.data()['createdAt']);
                final bDate = _createdAt(b.data()['createdAt']);
                final comparison = aDate.compareTo(bDate);
                if (_sortFilter == 'Oldest first') return comparison;
                if (_sortFilter == 'Total: low to high') {
                  return _total(a).compareTo(_total(b));
                }
                if (_sortFilter == 'Total: high to low') {
                  return _total(b).compareTo(_total(a));
                }
                return -comparison;
              });
          if (documents.isEmpty) {
            return Column(
              children: [
                _buildFilters(),
                const Expanded(
                  child: Center(child: Text('No matching orders.')),
                ),
              ],
            );
          }
          return Column(
            children: [
              _buildFilters(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    final data = document.data();
                    final customer =
                        data['customer'] as Map<String, dynamic>? ?? {};
                    final orderNumber =
                        data['orderNumber'] as String? ?? document.id;
                    final status = data['status'] as String? ?? 'pending';
                    final address =
                        data['shippingAddress'] as Map<String, dynamic>? ?? {};
                    return Card(
                      child: ExpansionTile(
                        title: Text(orderNumber),
                        subtitle: Text(
                          '${customer['name'] ?? 'Customer'} • '
                          '€${data['totalPrice'] ?? 0} • $status',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${customer['email'] ?? ''}\n'
                              '${customer['phone'] ?? ''}\n\n'
                              'Delivery address:\n'
                              '${address['address'] ?? ''}, '
                              '${address['city'] ?? ''}, '
                              '${address['postalCode'] ?? ''}\n\n'
                              '${_formatItems(data['items'])}',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Order status',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pending'),
                              ),
                              DropdownMenuItem(
                                value: 'confirmed',
                                child: Text('Confirmed'),
                              ),
                              DropdownMenuItem(
                                value: 'shipped',
                                child: Text('Shipped'),
                              ),
                              DropdownMenuItem(
                                value: 'completed',
                                child: Text('Completed'),
                              ),
                              DropdownMenuItem(
                                value: 'cancelled',
                                child: Text('Cancelled'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              _updateOrderStatus(document, customer, value);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateOrderStatus(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
    Map<String, dynamic> customer,
    String status,
  ) async {
    final data = document.data();
    final orderNumber = data['orderNumber'] as String? ?? document.id;
    final email = customer['email'] as String?;
    final batch = FirebaseFirestore.instance.batch();
    batch.update(document.reference, {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (email != null && email.isNotEmpty) {
      batch.set(FirebaseFirestore.instance.collection('mail').doc(), {
        'to': email,
        'orderId': document.id,
        'customerId': data['customerId'],
        'type': 'order_status',
        'message': {
          'subject': 'Order $orderNumber is ${_statusLabel(status)}',
          'text': 'Your order $orderNumber is now ${_statusLabel(status)}.',
          'html':
              '<h2>Order update</h2>'
              '<p>Your order <strong>$orderNumber</strong> is now '
              '<strong>${_statusLabel(status)}</strong>.</p>',
        },
      });
    }
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Unable to update order.')),
        );
      }
    }
  }

  String _statusLabel(String status) =>
      '${status[0].toUpperCase()}${status.substring(1)}';

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search orders',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                DropdownMenuItem(value: 'shipped', child: Text('Shipped')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _statusFilter = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _sortFilter,
              decoration: const InputDecoration(labelText: 'Sort'),
              items: const [
                DropdownMenuItem(
                  value: 'Newest first',
                  child: Text('Newest first'),
                ),
                DropdownMenuItem(
                  value: 'Oldest first',
                  child: Text('Oldest first'),
                ),
                DropdownMenuItem(
                  value: 'Total: low to high',
                  child: Text('Total: low to high'),
                ),
                DropdownMenuItem(
                  value: 'Total: high to low',
                  child: Text('Total: high to low'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sortFilter = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 155,
            child: DropdownButtonFormField<String>(
              initialValue: _dateFilter,
              decoration: const InputDecoration(labelText: 'Date'),
              items: _dateFilters
                  .map(
                    (filter) =>
                        DropdownMenuItem(value: filter, child: Text(filter)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _dateFilter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  DateTime _createdAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _matchesDateFilter(DateTime createdAt) {
    if (_dateFilter == 'All time') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_dateFilter == 'Today') return !createdAt.isBefore(today);
    final days = _dateFilter == 'Last 7 days' ? 7 : 30;
    return !createdAt.isBefore(now.subtract(Duration(days: days)));
  }

  num _total(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final value = document.data()['totalPrice'];
    return value is num ? value : 0;
  }

  String _formatItems(dynamic rawItems) {
    if (rawItems is! List) return 'No item details';
    return rawItems
        .map((item) {
          if (item is! Map) return '';
          return '${item['name']} • ${item['size']} • '
              '${item['quantity']} × €${item['unitPrice']}';
        })
        .join('\n');
  }
}

class AccessDeniedScreen extends StatelessWidget {
  final String message;

  const AccessDeniedScreen({
    super.key,
    this.message =
        'This account is signed in but is not approved to manage products.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Admin access required',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    if (!_isValidEmail(_emailController.text)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message ?? 'Unable to sign in.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Rina's Collection",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text('Admin dashboard'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final products = FirebaseFirestore.instance
        .collection('products')
        .orderBy('name')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              onPressed: () => _showCategories(context),
              icon: const Icon(Icons.category_outlined),
              label: const Text('Categories'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Orders',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: products,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load products.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final documents = snapshot.data!.docs.where((document) {
            final data = document.data();
            final name = (data['name'] as String? ?? '').toLowerCase();
            final category = (data['category'] as String? ?? '').toLowerCase();
            final query = _searchQuery.trim().toLowerCase();
            final matchesQuery =
                query.isEmpty ||
                name.contains(query) ||
                category.contains(query);
            final matchesStatus =
                _statusFilter == 'All' ||
                (_statusFilter == 'Published'
                    ? data['published'] == true
                    : data['published'] != true);
            return matchesQuery && matchesStatus;
          }).toList();
          if (documents.isEmpty) {
            return Column(
              children: [
                _buildFilters(),
                const Expanded(
                  child: Center(child: Text('No matching products.')),
                ),
              ],
            );
          }
          return Column(
            children: [
              _buildFilters(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    final data = document.data();
                    final imageUrl = data['imageUrl'] as String? ?? '';
                    return Card(
                      child: ListTile(
                        leading: imageUrl.isEmpty
                            ? const Icon(Icons.image_outlined)
                            : Image.network(
                                imageUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.broken_image_outlined),
                              ),
                        title: Text(
                          data['name'] as String? ?? 'Unnamed product',
                        ),
                        subtitle: Text(
                          '${data['category'] ?? 'Uncategorized'} • €${data['price'] ?? 0}',
                        ),
                        trailing: Wrap(
                          children: [
                            Icon(
                              data['published'] == true
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () =>
                                  _showProductForm(context, document.id, data),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () =>
                                  _deleteProduct(context, document.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search products',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(labelText: 'Visibility'),
              items: const [
                DropdownMenuItem(value: 'All', child: Text('All')),
                DropdownMenuItem(value: 'Published', child: Text('Published')),
                DropdownMenuItem(
                  value: 'Unpublished',
                  child: Text('Unpublished'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _statusFilter = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct(BuildContext context, String id) async {
    await FirebaseFirestore.instance.collection('products').doc(id).delete();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Product deleted.')));
    }
  }

  Future<void> _showCategories(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Manage categories'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('categories')
                .orderBy('order')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Unable to load categories.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final document in snapshot.data!.docs)
                    ListTile(
                      leading:
                          (document.data()['imageUrl'] as String? ?? '').isEmpty
                          ? const Icon(Icons.category_outlined)
                          : Image.network(
                              document.data()['imageUrl'] as String,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                      title: Text(document.data()['name'] as String? ?? ''),
                      subtitle: Text(
                        document.data()['published'] == true
                            ? 'Published'
                            : 'Unpublished',
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _showCategoryForm(
                              context,
                              document.id,
                              document.data(),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => FirebaseFirestore.instance
                                .collection('categories')
                                .doc(document.id)
                                .delete(),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  if (snapshot.data!.docs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Add your first custom category.'),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () => _showCategoryForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Add category'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryForm(
    BuildContext context, [
    String? id,
    Map<String, dynamic>? existing,
  ]) async {
    final name = TextEditingController(text: existing?['name'] as String?);
    final imageUrl = TextEditingController(
      text: existing?['imageUrl'] as String? ?? '',
    );
    final order = TextEditingController(text: '${existing?['order'] ?? 0}');
    var published = existing?['published'] != false;
    var uploading = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(id == null ? 'Add category' : 'Edit category'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Category name'),
                ),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Display order'),
                ),
                TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Image URL (optional)',
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            final selected = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                            );
                            if (selected == null) return;
                            setState(() {
                              uploading = true;
                              error = null;
                            });
                            try {
                              final bytes = await selected.readAsBytes();
                              final extension = selected.name.contains('.')
                                  ? selected.name.split('.').last
                                  : 'jpg';
                              final reference = FirebaseStorage.instance
                                  .ref()
                                  .child(
                                    'category-images/${DateTime.now().millisecondsSinceEpoch}.$extension',
                                  );
                              await reference.putData(
                                bytes,
                                SettableMetadata(
                                  contentType:
                                      selected.mimeType ?? 'image/$extension',
                                ),
                              );
                              imageUrl.text = await reference.getDownloadURL();
                            } on FirebaseException catch (uploadError) {
                              setState(
                                () => error =
                                    uploadError.message ?? 'Upload failed.',
                              );
                            } finally {
                              setState(() => uploading = false);
                            }
                          },
                    icon: uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      uploading ? 'Uploading...' : 'Upload tile image',
                    ),
                  ),
                ),
                if (error != null)
                  Text(error!, style: TextStyle(color: Colors.red.shade700)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published'),
                  value: published,
                  onChanged: (value) => setState(() => published = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final data = {
                  'name': name.text.trim(),
                  'imageUrl': imageUrl.text.trim(),
                  'order': int.tryParse(order.text.trim()) ?? 0,
                  'published': published,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                final collection = FirebaseFirestore.instance.collection(
                  'categories',
                );
                if (id == null) {
                  await collection.add({
                    ...data,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await collection.doc(id).update(data);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductForm(
    BuildContext context, [
    String? id,
    Map<String, dynamic>? existing,
  ]) async {
    final name = TextEditingController(text: existing?['name'] as String?);
    final category = TextEditingController(
      text: existing?['category'] as String?,
    );
    final price = TextEditingController(text: '${existing?['price'] ?? ''}');
    final description = TextEditingController(
      text: existing?['description'] as String?,
    );
    final imageUrl = TextEditingController(
      text: existing?['imageUrl'] as String? ?? '',
    );
    var published = existing?['published'] == true;
    var isNew = existing?['isNew'] == true;
    var uploadingImage = false;
    String? imageError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(id == null ? 'Add product' : 'Edit product'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Price (€)'),
                  ),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  TextField(
                    controller: imageUrl,
                    decoration: const InputDecoration(
                      labelText: 'Image URL (optional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: uploadingImage
                          ? null
                          : () async {
                              final selected = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                              );
                              if (selected == null) return;

                              setDialogState(() {
                                uploadingImage = true;
                                imageError = null;
                              });
                              try {
                                final bytes = await selected.readAsBytes();
                                final extension = selected.name.contains('.')
                                    ? selected.name.split('.').last
                                    : 'jpg';
                                final fileName =
                                    '${DateTime.now().millisecondsSinceEpoch}.$extension';
                                final reference = FirebaseStorage.instance
                                    .ref()
                                    .child('product-images/$fileName');
                                await reference.putData(
                                  bytes,
                                  SettableMetadata(
                                    contentType:
                                        selected.mimeType ?? 'image/$extension',
                                  ),
                                );
                                final url = await reference.getDownloadURL();
                                imageUrl.text = url;
                              } on FirebaseException catch (error) {
                                setDialogState(() {
                                  imageError =
                                      error.message ?? 'Image upload failed.';
                                });
                              } finally {
                                if (context.mounted) {
                                  setDialogState(() => uploadingImage = false);
                                }
                              }
                            },
                      icon: uploadingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        uploadingImage ? 'Uploading...' : 'Upload image',
                      ),
                    ),
                  ),
                  if (imageError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        imageError!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Published'),
                    value: published,
                    onChanged: (value) =>
                        setDialogState(() => published = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('New arrival'),
                    value: isNew,
                    onChanged: (value) => setDialogState(() => isNew = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final parsedPrice = double.tryParse(price.text.trim());
                if (name.text.trim().isEmpty ||
                    category.text.trim().isEmpty ||
                    parsedPrice == null ||
                    description.text.trim().isEmpty) {
                  return;
                }
                final data = {
                  'name': name.text.trim(),
                  'category': category.text.trim(),
                  'price': parsedPrice,
                  'description': description.text.trim(),
                  'imageUrl': imageUrl.text.trim(),
                  'published': published,
                  'isNew': isNew,
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                final collection = FirebaseFirestore.instance.collection(
                  'products',
                );
                if (id == null) {
                  await collection.add({
                    ...data,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  await collection.doc(id).update(data);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
