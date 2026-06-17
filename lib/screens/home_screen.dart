import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/prefs_service.dart';
import '../widgets/settings_modal.dart';
import 'tabs/income_tab.dart';
import 'tabs/edit_tab.dart';

class HomeScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final GoogleSignIn googleSignIn;

  const HomeScreen({super.key, required this.user, required this.googleSignIn});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  bool _showIncome = true;
  bool _showExpense = true;
  bool _showWarehouse = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final income = await PrefsService.getModuleState('mod_income', defaultState: true);
    final expense = await PrefsService.getModuleState('mod_expense', defaultState: true);
    final warehouse = await PrefsService.getModuleState('mod_warehouse', defaultState: false);
    
    setState(() {
      _showIncome = income;
      _showExpense = expense;
      _showWarehouse = warehouse;
      _isLoading = false;
    });
  }

  void _openSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SettingsModal(
        googleSignIn: widget.googleSignIn,
        initialIncome: _showIncome,
        initialExpense: _showExpense,
        initialWarehouse: _showWarehouse,
        onSettingsChanged: _loadSettings, // Оновлюємо екран, якщо змінили тумблер
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Збираємо вкладки
    List<Widget> activeTabs = [];
    List<BottomNavigationBarItem> navItems = [];

    if (_showIncome) {
      activeTabs.add(IncomeTab(user: widget.user)); // Підключаємо наш новий незалежний файл!
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.trending_up), label: 'Доходи'));
    }
    if (_showExpense) {
      activeTabs.add(const Center(child: Text("Витрати у розробці 🛠")));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.trending_down), label: 'Витрати'));
    }
    if (_showWarehouse) {
      activeTabs.add(const Center(child: Text("Склад у розробці 🛠")));
      navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Склад'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FinLapa', style: TextStyle(fontWeight: FontWeight.w900)),
        elevation: 2,
        actions: [
          GestureDetector(
            onTap: _openSettingsMenu,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16), 
              child: CircleAvatar(
                radius: 18, 
                backgroundImage: widget.user.photoUrl != null ? NetworkImage(widget.user.photoUrl!) : null, 
                child: widget.user.photoUrl == null ? const Icon(Icons.person) : null
              )
            ),
          )
        ],
      ),
      body: activeTabs.isEmpty 
          ? const Center(child: Text("Увімкніть модулі в налаштуваннях")) 
          : activeTabs[_currentIndex >= activeTabs.length ? 0 : _currentIndex],
          
      bottomNavigationBar: navItems.length > 1 
          ? BottomNavigationBar(
              currentIndex: _currentIndex >= navItems.length ? 0 : _currentIndex, 
              onTap: (index) => setState(() => _currentIndex = index), 
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold), 
              items: navItems
            ) 
          : null,
    );
  }
}