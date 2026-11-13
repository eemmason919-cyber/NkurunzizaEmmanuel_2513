// POS Retail Pro - Flutter (Android + iOS)
// Screens: 1 Splash, 2 Login, 3 Dashboard, 4 Products, 5 New Sale, 6 Payment,
// 7 Inventory, 8 Customers, 9 Reports, 10 Settings, 11 Offline, 12 Business Profile
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBlue = Color(0xFF1F6FEB);
const kNavy = Color(0xFF1B3A6B);
const kBorder = Color(0xFFE3E8F0);

// ───────────────────────── Helpers ─────────────────────────
String fmt(num v) => v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
String ugx(num v) => 'UGX ${fmt(v)}';
String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

IconData methodIcon(String m) => switch (m) {
      'Cash' => Icons.payments_outlined,
      'Card' => Icons.credit_card,
      'Mobile Money' => Icons.phone_android,
      _ => Icons.account_balance,
    };

String saleLabel(String m) => switch (m) {
      'Cash' => 'Cash Sale',
      'Card' => 'Card Payment',
      'Mobile Money' => 'Mobile Money',
      _ => 'Bank Transfer',
    };

void snack(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

Widget box(Widget child, {EdgeInsets padding = const EdgeInsets.all(14), Color color = Colors.white}) => Container(
      padding: padding,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: child,
    );

Widget chips(List<String> labels, int selected, ValueChanged<int> onTap) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(labels[i]), selected: selected == i, onSelected: (_) => onTap(i)),
            ),
        ],
      ),
    );

Widget searchField(String hint, ValueChanged<String> onChanged) => TextField(
      onChanged: onChanged,
      decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search), isDense: true),
    );

// ───────────────────────── Models ─────────────────────────
class Product {
  final String id, name, category;
  final int price, reorder;
  int stock;
  final IconData icon;
  Product(this.id, this.name, this.category, this.price, this.stock, this.reorder, this.icon);
}

class Customer {
  String name, phone;
  Customer(this.name, this.phone);
}

class Sale {
  final DateTime time;
  final int total, items;
  final String method, customer;
  bool synced;
  Sale(this.time, this.total, this.method, this.customer, this.items, this.synced);
  Map<String, dynamic> toJson() =>
      {'t': time.toIso8601String(), 'a': total, 'm': method, 'c': customer, 'i': items, 's': synced};
  factory Sale.fromJson(Map<String, dynamic> j) =>
      Sale(DateTime.parse(j['t']), j['a'], j['m'], j['c'], j['i'], j['s']);
}

// ───────────────────────── App state (works fully offline) ─────────────────────────
class AppState extends ChangeNotifier {
  final List<Product> products = [
    Product('p1', 'Coca Cola 500ml', 'Beverages', 2500, 50, 20, Icons.local_drink),
    Product('p2', 'Sprite 500ml', 'Beverages', 2500, 40, 20, Icons.local_drink),
    Product('p3', 'Water 500ml', 'Beverages', 1500, 100, 30, Icons.water_drop),
    Product('p4', 'Bread', 'Groceries', 3000, 30, 10, Icons.bakery_dining),
    Product('p5', 'Chips', 'Snacks', 2000, 45, 15, Icons.fastfood),
    Product('p6', 'Biscuits', 'Snacks', 1000, 8, 10, Icons.cookie),
    Product('p7', 'Milk 1L', 'Groceries', 3500, 25, 10, Icons.egg_alt),
    Product('p8', 'Sugar 1kg', 'Groceries', 5000, 6, 10, Icons.shopping_basket),
  ];
  List<Customer> customers = [
    Customer('John Mwangi', '+256 700 123 456'),
    Customer('Sarah Nakato', '+256 772 987 654'),
    Customer('Peter Okello', '+256 701 555 010'),
  ];
  List<Sale> sales = _seedSales();
  final Map<String, int> cart = {};
  Customer? customer;
  String method = 'Cash';
  final Set<String> enabledMethods = {'Cash', 'Card', 'Mobile Money', 'Bank Transfer'};
  bool offline = false;
  String rememberedId = '';
  String ownerName = 'Business Owner', email = 'owner@business.com';
  String businessName = 'My Store', businessType = 'Retail Store', businessPhone = '', businessAddress = '';
  double taxRate = 18;

  static List<Sale> _seedSales() {
    final n = DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    final list = <Sale>[
      Sale(day.add(const Duration(hours: 9, minutes: 15)), 80000, 'Mobile Money', 'Walk-in Customer', 6, true),
      Sale(day.add(const Duration(hours: 9, minutes: 50)), 120000, 'Card', 'John Mwangi', 9, true),
      Sale(day.add(const Duration(hours: 10, minutes: 24)), 45000, 'Cash', 'Walk-in Customer', 4, true),
    ];
    for (var d = 1; d < 30; d++) {
      list.add(Sale(day.subtract(Duration(days: d)).add(const Duration(hours: 14)), 600000 + ((d * 7919) % 9) * 100000,
          ['Cash', 'Card', 'Mobile Money'][d % 3], d % 4 == 0 ? 'Sarah Nakato' : 'Walk-in Customer', 10 + d % 7, true));
    }
    return list;
  }

  Product byId(String id) => products.firstWhere((p) => p.id == id);
  int qty(Product p) => cart[p.id] ?? 0;
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  int get subtotal => cart.entries.fold(0, (s, e) => s + byId(e.key).price * e.value);
  int get tax => (subtotal * taxRate / 100).round();
  int get total => subtotal + tax;
  List<Sale> get todaySales => sales.where((s) => sameDay(s.time, DateTime.now())).toList();
  int get pendingSync => sales.where((s) => !s.synced).length;

  bool add(Product p) {
    if (qty(p) >= p.stock) return false;
    cart[p.id] = qty(p) + 1;
    notifyListeners();
    return true;
  }

  void removeOne(Product p) {
    final q = qty(p);
    if (q <= 1) {
      cart.remove(p.id);
    } else {
      cart[p.id] = q - 1;
    }
    notifyListeners();
  }

  void discard(Product p) {
    cart.remove(p.id);
    notifyListeners();
  }

  void setCustomer(Customer? c) {
    customer = c;
    notifyListeners();
  }

  void setMethod(String m) {
    method = m;
    notifyListeners();
  }

  void setOffline(bool v) {
    offline = v;
    if (!v) {
      for (final s in sales) {
        s.synced = true; // simulated sync when back online
      }
    }
    save();
    notifyListeners();
  }

  Future<Sale> completeSale() async {
    final sale = Sale(DateTime.now(), total, method, customer?.name ?? 'Walk-in Customer', cartCount, !offline);
    for (final e in cart.entries) {
      byId(e.key).stock -= e.value;
    }
    sales.add(sale);
    cart.clear();
    customer = null;
    await save();
    notifyListeners();
    return sale;
  }

  void addStock(Product p, int n) {
    p.stock += n;
    save();
    notifyListeners();
  }

  void addCustomer(String n, String p) {
    customers.add(Customer(n, p));
    save();
    notifyListeners();
  }

  void toggleMethod(String m, bool on) {
    if (on) {
      enabledMethods.add(m);
    } else if (enabledMethods.length > 1) {
      enabledMethods.remove(m);
    }
    notifyListeners();
  }

  void saveProfile({required String name, required String type, required String phone, required String address, required double tax}) {
    businessName = name;
    businessType = type;
    businessPhone = phone;
    businessAddress = address;
    taxRate = tax;
    save();
    notifyListeners();
  }

  Future<void> setRemember(String id) async {
    rememberedId = id;
    try {
      (await SharedPreferences.getInstance()).setString('rememberedId', id);
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('sales', jsonEncode(sales.map((s) => s.toJson()).toList()));
      await p.setString('stock', jsonEncode({for (final x in products) x.id: x.stock}));
      await p.setString('customers', jsonEncode(customers.map((c) => {'n': c.name, 'p': c.phone}).toList()));
      await p.setString('profile', jsonEncode({'name': businessName, 'type': businessType, 'phone': businessPhone, 'addr': businessAddress, 'tax': taxRate, 'offline': offline}));
    } catch (_) {}
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    rememberedId = p.getString('rememberedId') ?? '';
    final s = p.getString('sales');
    if (s != null) sales = (jsonDecode(s) as List).map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
    final st = p.getString('stock');
    if (st != null) {
      final m = jsonDecode(st) as Map<String, dynamic>;
      for (final x in products) {
        if (m[x.id] != null) x.stock = m[x.id] as int;
      }
    }
    final c = p.getString('customers');
    if (c != null) customers = (jsonDecode(c) as List).map((e) => Customer(e['n'] as String, e['p'] as String)).toList();
    final b = p.getString('profile');
    if (b != null) {
      final m = jsonDecode(b) as Map<String, dynamic>;
      businessName = m['name'] ?? businessName;
      businessType = m['type'] ?? businessType;
      businessPhone = m['phone'] ?? '';
      businessAddress = m['addr'] ?? '';
      taxRate = (m['tax'] as num?)?.toDouble() ?? 18;
      offline = m['offline'] ?? false;
    }
  }
}

final app = AppState();

// ───────────────────────── Entry ─────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await app.load();
  } catch (e) {
    debugPrint('Could not load saved data: $e');
  }
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});
  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder));
    return MaterialApp(
      title: 'POS Retail Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0, scrolledUnderElevation: 0),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: border, enabledBorder: border),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ───────────────────────── 1. Splash ─────────────────────────
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(Icons.shopping_cart, size: 90, color: kBlue),
                const SizedBox(height: 12),
                const Text('POS Retail Pro', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Manage your business\nanytime, anywhere', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Get Started'),
                ),
                const SizedBox(height: 16),
                const Text('Version 1.0.0', style: TextStyle(color: Colors.black38, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

// ───────────────────────── 2. Login ─────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController(text: app.rememberedId);
  final _pw = TextEditingController();
  bool _hide = true;
  late bool _remember = app.rememberedId.isNotEmpty;
  String? _error;

  Future<void> _login() async {
    if (_id.text.trim().isEmpty) return setState(() => _error = 'Enter your email or phone number');
    if (_pw.text.length < 6) return setState(() => _error = 'Password must be at least 6 characters');
    await app.setRemember(_remember ? _id.text.trim() : '');
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              const Text('Login', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Sign in to your account', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              TextField(controller: _id, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'Email or Phone', prefixIcon: Icon(Icons.email_outlined))),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                obscureText: _hide,
                decoration: InputDecoration(
                  hintText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              Row(
                children: [
                  Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false)),
                  const Text('Remember me'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Forgot password?'),
                        content: const Text('Contact your business administrator to reset your password.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                      ),
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
              FilledButton(onPressed: _login, child: const Text('Login')),
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('OR', style: TextStyle(color: Colors.black45)))),
              OutlinedButton.icon(onPressed: () => snack(context, 'Google sign-in coming soon'), icon: const Icon(Icons.g_mobiledata, size: 30), label: const Text('Continue with Google')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: () => snack(context, 'Apple sign-in coming soon'), icon: const Icon(Icons.apple), label: const Text('Continue with Apple')),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? "),
                GestureDetector(onTap: () => snack(context, 'Sign up coming soon'), child: const Text('Sign Up', style: TextStyle(color: kBlue, fontWeight: FontWeight.w600))),
              ]),
            ],
          ),
        ),
      );
}

// ───────────────────────── Home shell (bottom nav) ─────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _i, children: const [
          DashboardPage(),
          ProductsPage(root: true),
          InventoryPage(root: true),
          CustomersPage(root: true),
          SettingsPage(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Sales'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
            NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Customers'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      );
}

// ───────────────────────── 3. Dashboard ─────────────────────────
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  Widget _tile(IconData i, String t, VoidCallback f) => InkWell(
        onTap: f,
        borderRadius: BorderRadius.circular(12),
        child: box(Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(i, color: kBlue, size: 30),
          const SizedBox(height: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
        ])),
      );

  void _go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final h = DateTime.now().hour;
          final greet = h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
          final today = app.todaySales;
          final recent = ([...app.sales]..sort((a, b) => b.time.compareTo(a.time))).take(5).toList();
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    Expanded(child: Text('$greet,\n${app.ownerName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    const Icon(Icons.notifications_none),
                    const SizedBox(width: 12),
                    const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
                  ]),
                  const SizedBox(height: 14),
                  if (app.offline)
                    InkWell(
                      onTap: () => _go(context, const OfflineScreen()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          const Icon(Icons.wifi_off, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Offline mode · ${app.pendingSync} sale(s) waiting to sync', style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text("Today's Sales", style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(ugx(today.fold<int>(0, (s, e) => s + e.total)), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('${today.length} transactions', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.bar_chart, color: Colors.white, size: 36),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.7,
                    children: [
                      _tile(Icons.add_shopping_cart, 'New Sale', () => _go(context, const ProductsPage())),
                      _tile(Icons.inventory_2_outlined, 'Inventory', () => _go(context, const InventoryPage())),
                      _tile(Icons.people_outline, 'Customers', () => _go(context, const CustomersPage())),
                      _tile(Icons.insights, 'Reports', () => _go(context, const ReportsScreen())),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Recent Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  for (final s in recent)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(backgroundColor: const Color(0xFFE8F0FE), child: Icon(methodIcon(s.method), color: kBlue, size: 20)),
                      title: Text(saleLabel(s.method)),
                      subtitle: Text(s.customer),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(ugx(s.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(sameDay(s.time, DateTime.now()) ? hm(s.time) : '${s.time.day}/${s.time.month}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                      ]),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

// ───────────────────────── 4. Products ─────────────────────────
class ProductsPage extends StatefulWidget {
  final bool root;
  const ProductsPage({super.key, this.root = false});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _q = '';
  int _cat = 0;
  static const cats = ['All', 'Beverages', 'Snacks', 'Groceries'];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = app.products.where((p) => (_cat == 0 || p.category == cats[_cat]) && p.name.toLowerCase().contains(_q.toLowerCase())).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Products', style: TextStyle(fontWeight: FontWeight.bold)), automaticallyImplyLeading: !widget.root),
            body: Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: searchField('Search products...', (v) => setState(() => _q = v))),
                Padding(padding: const EdgeInsets.only(left: 16), child: Align(alignment: Alignment.centerLeft, child: chips(cats, _cat, (i) => setState(() => _cat = i)))),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      final q = app.qty(p);
                      return box(
                        Row(children: [
                          Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFE8F0FE), borderRadius: BorderRadius.circular(8)), child: Icon(p.icon, color: kBlue)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(ugx(p.price), style: const TextStyle(color: kBlue)),
                              Text('Stock: ${p.stock}', style: TextStyle(fontSize: 12, color: p.stock <= p.reorder ? Colors.red : Colors.black45)),
                            ]),
                          ),
                          if (q > 0) Padding(padding: const EdgeInsets.only(right: 6), child: Text('×$q', style: const TextStyle(fontWeight: FontWeight.bold))),
                          IconButton.filled(
                            onPressed: p.stock == 0 ? null : () {
                              if (!app.add(p)) snack(context, 'No more stock for ${p.name}');
                            },
                            icon: const Icon(Icons.add),
                          ),
                        ]),
                        padding: const EdgeInsets.all(10),
                      );
                    },
                  ),
                ),
                if (app.cartCount > 0)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: FilledButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen())),
                        icon: const Icon(Icons.shopping_cart_checkout),
                        label: Text('View Cart (${app.cartCount}) · ${ugx(app.total)}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── 5. New Sale / Checkout ─────────────────────────
class NewSaleScreen extends StatelessWidget {
  const NewSaleScreen({super.key});

  void _pickCustomer(BuildContext context) => showModalBottomSheet(
        context: context,
        builder: (_) => ListView(
          children: [
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Walk-in Customer'), onTap: () { app.setCustomer(null); Navigator.pop(context); }),
            for (final c in app.customers)
              ListTile(leading: const Icon(Icons.person), title: Text(c.name), subtitle: Text(c.phone), onTap: () { app.setCustomer(c); Navigator.pop(context); }),
          ],
        ),
      );

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 16 : 14)),
          const Spacer(),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 16 : 14)),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final items = app.cart.keys.map(app.byId).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('New Sale', style: TextStyle(fontWeight: FontWeight.bold))),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                box(Row(children: [
                  const Icon(Icons.person_outline),
                  const SizedBox(width: 10),
                  Expanded(child: Text(app.customer?.name ?? 'Walk-in Customer')),
                  TextButton(onPressed: () => _pickCustomer(context), child: const Text('Change')),
                ]), padding: const EdgeInsets.fromLTRB(14, 4, 6, 4)),
                const SizedBox(height: 12),
                if (items.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Cart is empty. Add products first.', style: TextStyle(color: Colors.black45)))),
                for (final p in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: box(Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(ugx(p.price), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ]),
                      ),
                      IconButton(onPressed: () => app.removeOne(p), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${app.qty(p)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () { if (!app.add(p)) snack(context, 'No more stock for ${p.name}'); }, icon: const Icon(Icons.add_circle_outline)),
                      SizedBox(width: 84, child: Text(ugx(p.price * app.qty(p)), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ]), padding: const EdgeInsets.fromLTRB(12, 4, 12, 4)),
                  ),
                const SizedBox(height: 8),
                box(Column(children: [
                  _row('Subtotal', ugx(app.subtotal)),
                  _row('Tax (${app.taxRate.toStringAsFixed(app.taxRate % 1 == 0 ? 0 : 1)}%)', ugx(app.tax)),
                  const Divider(),
                  _row('Total', ugx(app.total), bold: true),
                ])),
                const SizedBox(height: 14),
                const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                chips(['Cash', 'Card', 'Mobile Money'].where(app.enabledMethods.contains).toList(),
                    ['Cash', 'Card', 'Mobile Money'].where(app.enabledMethods.contains).toList().indexOf(app.method),
                    (i) => app.setMethod(['Cash', 'Card', 'Mobile Money'].where(app.enabledMethods.contains).toList()[i])),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: items.isEmpty ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen())),
                  child: const Text('Complete Sale'),
                ),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── 6. Payment ─────────────────────────
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late String _m = app.enabledMethods.contains(app.method) ? app.method : app.enabledMethods.first;
  final _cash = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  static const order = ['Cash', 'Card', 'Mobile Money', 'Bank Transfer'];

  int? get _received => int.tryParse(_cash.text.replaceAll(',', '').trim());

  Future<void> _pay() async {
    if (_m == 'Cash' && _received != null && _received! < app.total) return snack(context, 'Amount received is less than the total');
    if (_m == 'Mobile Money' && _phone.text.trim().length < 9) return snack(context, "Enter the customer's mobile money number");
    setState(() => _busy = true);
    final received = _received;
    app.method = _m;
    final sale = await app.completeSale();
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Payment Successful'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ugx(sale.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('${sale.method} · ${sale.items} item(s)'),
          if (_m == 'Cash' && received != null && received > sale.total) Text('Change: ${ugx(received - sale.total)}'),
          if (!sale.synced) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Saved offline – will sync later', style: TextStyle(color: Colors.orange, fontSize: 12))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ),
    );
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment', style: TextStyle(fontWeight: FontWeight.bold))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: Column(children: [
              const Text('Total Amount', style: TextStyle(color: Colors.black54)),
              Text(ugx(app.total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: kBlue)),
            ])),
            const SizedBox(height: 16),
            for (final m in order.where(app.enabledMethods.contains))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _m = m),
                  child: box(
                    Row(children: [
                      Icon(methodIcon(m), color: kBlue),
                      const SizedBox(width: 12),
                      Expanded(child: Text(m)),
                      Icon(_m == m ? Icons.radio_button_checked : Icons.radio_button_off, color: _m == m ? kBlue : Colors.black38),
                    ]),
                    color: _m == m ? const Color(0xFFE8F0FE) : Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_m == 'Cash') TextField(controller: _cash, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Amount received (optional)', helperText: _received != null && _received! >= app.total ? 'Change: ${ugx(_received! - app.total)}' : null)),
            if (_m == 'Mobile Money') TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile money number', hintText: '+256 7xx xxx xxx')),
            if (_m == 'Card') const Text('Tap/insert the card on your card terminal, then press Pay Now.', style: TextStyle(color: Colors.black54)),
            if (_m == 'Bank Transfer') const Text('Confirm the transfer has been received before pressing Pay Now.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            FilledButton(onPressed: _busy ? null : _pay, child: Text(_busy ? 'Processing...' : 'Pay Now')),
          ],
        ),
      );
}

// ───────────────────────── 7. Inventory ─────────────────────────
class InventoryPage extends StatefulWidget {
  final bool root;
  const InventoryPage({super.key, this.root = false});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  int _tab = 0;
  String _q = '';

  void _addStock(Product p) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add stock · ${p.name}'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Quantity received')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () {
              final n = int.tryParse(c.text.trim());
              if (n != null && n > 0) app.addStock(p, n);
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final all = app.products.where((p) => p.name.toLowerCase().contains(_q.toLowerCase())).toList();
          final list = _tab == 1 ? all.where((p) => p.stock <= p.reorder).toList() : all;
          final cats = <String, int>{};
          for (final p in app.products) {
            cats[p.category] = (cats[p.category] ?? 0) + 1;
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Inventory', style: TextStyle(fontWeight: FontWeight.bold)), automaticallyImplyLeading: !widget.root),
            body: Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Align(alignment: Alignment.centerLeft, child: chips(['Stock', 'Low Stock', 'Categories'], _tab, (i) => setState(() => _tab = i)))),
                if (_tab != 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: searchField('Search inventory...', (v) => setState(() => _q = v))),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_tab == 2)
                        for (final e in cats.entries)
                          Padding(padding: const EdgeInsets.only(bottom: 8), child: box(Row(children: [const Icon(Icons.category_outlined, color: kBlue), const SizedBox(width: 12), Expanded(child: Text(e.key)), Text('${e.value} items')])))
                      else ...[
                        if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nothing here', style: TextStyle(color: Colors.black45)))),
                        for (final p in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: box(Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('Stock: ${p.stock}   Reorder: ${p.reorder}', style: TextStyle(fontSize: 12, color: p.stock <= p.reorder ? Colors.red : Colors.black54)),
                                ]),
                              ),
                              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(70, 36)), onPressed: () => _addStock(p), child: const Text('+ Stock')),
                            ])),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── 8. Customers ─────────────────────────
class CustomersPage extends StatefulWidget {
  final bool root;
  const CustomersPage({super.key, this.root = false});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String _q = '';

  void _add() {
    final n = TextEditingController(), p = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add customer'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () {
              if (n.text.trim().isNotEmpty) app.addCustomer(n.text.trim(), p.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = app.customers.where((c) => c.name.toLowerCase().contains(_q.toLowerCase()) || c.phone.contains(_q)).toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Customers', style: TextStyle(fontWeight: FontWeight.bold)), automaticallyImplyLeading: !widget.root),
            floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.person_add_alt_1)),
            body: Column(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: searchField('Search customers...', (v) => setState(() => _q = v))),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final mine = app.sales.where((s) => s.customer == c.name).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: box(
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(c.phone),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showModalBottomSheet(
                              context: context,
                              builder: (_) => Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  Text(c.phone),
                                  const SizedBox(height: 12),
                                  Text('Purchases: ${mine.length}'),
                                  Text('Total spent: ${ugx(mine.fold<int>(0, (s, e) => s + e.total))}'),
                                ]),
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
}

// ───────────────────────── 9. Reports ─────────────────────────
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _tab = 0, _r = 0;
  DateTimeRange? _custom;

  DateTimeRange get _span {
    final n = DateTime.now();
    final end = DateTime(n.year, n.month, n.day);
    if (_r == 0) return DateTimeRange(start: end.subtract(const Duration(days: 6)), end: end);
    if (_r == 1) return DateTimeRange(start: end.subtract(const Duration(days: 29)), end: end);
    return _custom ?? DateTimeRange(start: end.subtract(const Duration(days: 6)), end: end);
  }

  List<Sale> get _sales => app.sales.where((s) {
        final d = DateTime(s.time.year, s.time.month, s.time.day);
        return !d.isBefore(_span.start) && !d.isAfter(_span.end);
      }).toList();

  Future<void> _pickRange(int i) async {
    if (i == 2) {
      final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now());
      if (r == null) return;
      _custom = r;
    }
    setState(() => _r = i);
  }

  Widget _stat(String l, String v) => Expanded(child: box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: Colors.black54, fontSize: 12)), const SizedBox(height: 4), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))])));

  Widget _salesTab() {
    final s = _sales;
    final total = s.fold<int>(0, (a, e) => a + e.total);
    final n = _span.end.difference(_span.start).inDays + 1;
    final days = [for (var i = 0; i < n; i++) DateTime(_span.start.year, _span.start.month, _span.start.day + i)];
    final sums = [for (final d in days) s.where((x) => sameDay(x.time, d)).fold<int>(0, (a, e) => a + e.total)];
    final mx = sums.fold<int>(1, (a, b) => b > a ? b : a);
    final byMethod = <String, int>{};
    for (final x in s) {
      byMethod[x.method] = (byMethod[x.method] ?? 0) + x.total;
    }
    return Column(children: [
      box(Row(children: [
        const Icon(Icons.trending_up, color: kBlue),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Sales'), Text(ugx(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))])),
      ])),
      const SizedBox(height: 10),
      Row(children: [_stat('Transactions', '${s.length}'), const SizedBox(width: 10), _stat('Average sale', ugx(s.isEmpty ? 0 : total / s.length))]),
      const SizedBox(height: 10),
      box(SizedBox(
        height: 150,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(height: 3 + 100 * sums[i] / mx, decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(3))),
                  if (days.length <= 14) Padding(padding: const EdgeInsets.only(top: 4), child: Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][days[i].weekday - 1], style: const TextStyle(fontSize: 10))),
                ]),
              ),
            ),
        ]),
      )),
      const SizedBox(height: 10),
      box(Column(children: [
        for (final e in byMethod.entries) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(methodIcon(e.key), color: kBlue), title: Text(e.key), trailing: Text(ugx(e.value))),
        if (byMethod.isEmpty) const Text('No sales in this period'),
      ])),
    ]);
  }

  Widget _inventoryTab() {
    final value = app.products.fold<int>(0, (a, p) => a + p.price * p.stock);
    final low = app.products.where((p) => p.stock <= p.reorder).toList();
    return Column(children: [
      Row(children: [_stat('Stock value', ugx(value)), const SizedBox(width: 10), _stat('Low stock items', '${low.length}')]),
      const SizedBox(height: 10),
      box(Column(children: [
        for (final p in low) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(p.name), trailing: Text('${p.stock} left', style: const TextStyle(color: Colors.red))),
        if (low.isEmpty) const Text('All items are well stocked'),
      ])),
    ]);
  }

  Widget _customersTab() {
    final spend = <String, int>{};
    for (final s in _sales.where((s) => s.customer != 'Walk-in Customer')) {
      spend[s.customer] = (spend[s.customer] ?? 0) + s.total;
    }
    final top = spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      Row(children: [_stat('Customers', '${app.customers.length}'), const SizedBox(width: 10), _stat('Active in period', '${spend.length}')]),
      const SizedBox(height: 10),
      box(Column(children: [
        for (final e in top) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline), title: Text(e.key), trailing: Text(ugx(e.value))),
        if (top.isEmpty) const Text('No customer purchases in this period'),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              chips(['Sales', 'Inventory', 'Customers'], _tab, (i) => setState(() => _tab = i)),
              if (_tab != 1) ...[const SizedBox(height: 6), chips(['7 Days', '30 Days', 'Custom'], _r, _pickRange)],
              const SizedBox(height: 10),
              [_salesTab, _inventoryTab, _customersTab][_tab](),
            ],
          ),
        ),
      );
}

// ───────────────────────── 10. Settings ─────────────────────────
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _tile(IconData i, String t, VoidCallback f, {Widget? trailing}) => ListTile(leading: Icon(i, color: kBlue), title: Text(t), trailing: trailing ?? const Icon(Icons.chevron_right), onTap: f);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)), automaticallyImplyLeading: false),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              box(Row(children: [
                const CircleAvatar(radius: 26, child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(app.ownerName, style: const TextStyle(fontWeight: FontWeight.bold)), Text(app.email, style: const TextStyle(color: Colors.black54, fontSize: 12)), Text(app.businessName, style: const TextStyle(color: kBlue, fontSize: 12))]),
              ])),
              const SizedBox(height: 12),
              box(Column(children: [
                _tile(Icons.store_outlined, 'Business Profile', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessProfileScreen()))),
                _tile(Icons.payment, 'Payment Settings', () => showModalBottomSheet(
                      context: context,
                      builder: (_) => ListenableBuilder(
                        listenable: app,
                        builder: (_, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                          const Padding(padding: EdgeInsets.all(16), child: Text('Accepted payment methods', style: TextStyle(fontWeight: FontWeight.bold))),
                          for (final m in ['Cash', 'Card', 'Mobile Money', 'Bank Transfer'])
                            SwitchListTile(title: Text(m), secondary: Icon(methodIcon(m)), value: app.enabledMethods.contains(m), onChanged: (v) => app.toggleMethod(m, v)),
                          const SizedBox(height: 12),
                        ]),
                      ),
                    )),
                _tile(Icons.insights, 'Reports', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))),
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_off, color: kBlue),
                  title: const Text('Offline mode'),
                  subtitle: Text(app.pendingSync > 0 ? '${app.pendingSync} sale(s) pending sync' : 'Sales are saved on this device'),
                  value: app.offline,
                  onChanged: (v) {
                    app.setOffline(v);
                    if (v) Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineScreen()));
                  },
                ),
                _tile(Icons.lock_outline, 'Security & Privacy', () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Security & Privacy'),
                        content: const Text('Your sales data is stored only on this device and is never shared without your consent. Always log out on shared devices.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                      ),
                    )),
              ])),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  app.cart.clear();
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Log out', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );
}

// ───────────────────────── 11. Offline ─────────────────────────
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(radius: 56, backgroundColor: Color(0xFFEEF1F6), child: Icon(Icons.wifi_off, size: 56, color: Colors.black54)),
                const SizedBox(height: 20),
                const Text("You're offline", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('You can keep making sales. Everything is saved on this device and will sync when you are back online.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                Text('${app.pendingSync} sale(s) waiting to sync', style: const TextStyle(color: Colors.orange)),
                const SizedBox(height: 28),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Continue Offline')),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    app.setOffline(false);
                    Navigator.pop(context);
                    snack(context, 'Back online – data synced');
                  },
                  child: const Text('Go Online & Sync'),
                ),
              ],
            ),
          ),
        ),
      );
}

// ───────────────────────── 12. Business Profile ─────────────────────────
class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});
  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _name = TextEditingController(text: app.businessName);
  final _phone = TextEditingController(text: app.businessPhone);
  final _addr = TextEditingController(text: app.businessAddress);
  final _tax = TextEditingController(text: app.taxRate.toString());
  String _type = app.businessType;
  static const types = ['Retail Store', 'Supermarket', 'Pharmacy', 'Restaurant', 'Wholesale', 'Other'];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Business Profile', style: TextStyle(fontWeight: FontWeight.bold))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Business Type'),
              items: [for (final t in types) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 12),
            TextField(controller: _tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Tax rate (%)')),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final tax = double.tryParse(_tax.text.trim());
                if (_name.text.trim().isEmpty || tax == null || tax < 0 || tax > 100) return snack(context, 'Enter a business name and a tax rate between 0 and 100');
                app.saveProfile(name: _name.text.trim(), type: _type, phone: _phone.text.trim(), address: _addr.text.trim(), tax: tax);
                Navigator.pop(context);
                snack(context, 'Business profile saved');
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      );
}