import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:math';
import 'hovercard.dart';
import 'login.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String _baseUrl = "https://saferoute-intelligence-api.onrender.com";

  final DateTime _yesterday = DateTime.now().subtract(const Duration(days: 1));
  final MapController _mapController = MapController();
  static const LatLng _germanyCenter = LatLng(51.1657, 10.4515);
  List<Marker> _accidentMarkers = [];
  List<LatLng> _polygonPoints = [];
  List<List<dynamic>> _accidentCoordinates = [];

  List<Map<String, dynamic>> _accidentsTypes = [];
  List<Map<String, dynamic>> _categories = [];
  int? _selectedAccidentType;
  int? _selectedCategory;

  bool get _hasFilters =>
      _selectedState != 0 ||
      _selectedCity != 1000000 ||
      _selectedYear != 'All Years' ||
      _selectedMonth != 'All Months' ||
      _selectedDay != 'All Days' ||
      _selectedHour != 'All Hours' ||
      _selectedVehicles.isNotEmpty ||
      _selectedCategory != 0 ||
      _selectedAccidentType != -1;

  @override
  void initState() {
    super.initState();
    _selectedState = 0;

    _cityOptions = [
      {'id': 1000000, 'name': 'All Cities'},
    ];

    _selectedCity = 1000000;
    _selectedYear = 'All Years';
    _selectedMonth = 'All Months';
    _selectedDay = 'All Days';
    _selectedHour = 'All Hours';

    _loadVehiclesType();
    _loadAccidentsType();
    _states();
    _loadAccidentsCategories();
    _loadAccidentsFilter(); // Seed the map with initial unfiltered data on boot
  }

  late final List<String> _yearOptions = [
    'All Years',
    for (var y = 2018; y <= _yesterday.year; y++) y.toString(),
  ];

  final List<String> _monthOptions = [
    'All Months',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  List<Map<String, dynamic>> _vehicles = [];
  List<int> _selectedVehicles = [];
  Map<int, List<int>> _citiesByState = {};

  final Map<String, LatLng> _cityCenters = {
    'Stuttgart': const LatLng(48.775846, 9.182932),
    'Karlsruhe': const LatLng(49.006890, 8.403653),
    'Chemnitz': const LatLng(50.827845, 12.921370),
    'Leipzig': const LatLng(51.339695, 12.373075),
    'Dresden': const LatLng(51.050407, 13.737262),
    'Munich': const LatLng(48.137154, 11.576124),
    'Berlin': const LatLng(52.520008, 13.404954),
    'Hamburg': const LatLng(53.551086, 9.993682),
  };

  List<Map<String, dynamic>> _stateOptions = [];
  List<Map<String, dynamic>> _cityOptions = [];
  int? _selectedState;
  int? _selectedCity;

  List<int> get _visibleCityOptions => _citiesByState[_selectedState] ?? [];

  bool _isWithinThreshold(LatLng a, LatLng b, {double threshold = 0.18}) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy <= threshold * threshold;
  }

  bool get _selectedCityHasMarkers => _selectedCity != null;
  bool get _selectedStateHasMarkers =>
      _selectedState != null && _selectedState != 0;

  List<String> get _visibleMonthOptions {
    if (_selectedYear == _yesterday.year.toString()) {
      return _monthOptions.take(_yesterday.month + 1).toList();
    }
    return _monthOptions;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  List<String> get _visibleHourOptions {
    return [
      'All Hours',
      for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0'),
    ];
  }

  List<String> get _visibleDayOptions {
    final selectedYear = int.tryParse(_selectedYear);
    if (selectedYear == null) return ['All Days'];
    final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth);
    if (selectedMonthIndex <= 0) return ['All Days'];

    final dayCount = _daysInMonth(selectedYear, selectedMonthIndex);
    return ['All Days', for (var d = 1; d <= dayCount; d++) d.toString()];
  }

  String _selectedYear = 'All Years';
  String _selectedMonth = 'All Months';
  String _selectedDay = 'All Days';
  String _selectedHour = 'All Hours';

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (shouldLogout == true) await _logout();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _loadAccidentsFilter() async {
    // 1. Build normal URL with clean fallback structures
    String urlString = '$_baseUrl/accidents/filter?';
    final List<String> params = [];

    if (_selectedState != null && _selectedState != 0)
      params.add('state=$_selectedState');
    if (_selectedCity != null && _selectedCity != 1000000)
      params.add('city=$_selectedCity');
    if (_selectedYear != 'All Years') params.add('year=$_selectedYear');
    if (_selectedMonth != 'All Months')
      params.add('month=${_monthOptions.indexOf(_selectedMonth)}');
    if (_selectedDay != 'All Days') params.add('day=$_selectedDay');
    if (_selectedHour != 'All Hours') params.add('hour=$_selectedHour');
    if (_selectedCategory != null && _selectedCategory != 0)
      params.add('category=$_selectedCategory');
    if (_selectedAccidentType != null && _selectedAccidentType != -1)
      params.add('accident_type=$_selectedAccidentType');

    // 2. Append vehicle items repeatedly for proper parsing
    for (final vId in _selectedVehicles) {
      params.add('vehicle_type=$vId');
    }

    final finalUrl = Uri.parse(urlString + params.join('&'));

    try {
      final response = await http.get(finalUrl);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final markers = <Marker>[];
        final polygonPoints = <LatLng>[];

        for (final item in data) {
          final lat = (item['lat'] as num).toDouble();
          final lon = (item['lon'] as num).toDouble();
          final point = LatLng(lat, lon);
          polygonPoints.add(point);

          markers.add(
            Marker(
              point: point,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 30),
            ),
          );
        }

        setState(() {
          _accidentMarkers = markers;
          _polygonPoints = polygonPoints;

          if (polygonPoints.isNotEmpty && _mapController != null) {
            final bounds = LatLngBounds.fromPoints(polygonPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(50),
              ),
            );
          }
        });
      }
    } catch (e) {
      print('HTTP MAP RETRIEVAL ERROR: $e');
    }
  }

  Future<void> _loadAccidentsType() async {
    final url = Uri.parse('$_baseUrl/accidentTypes');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _accidentsTypes = List<Map<String, dynamic>>.from(
            json.decode(utf8.decode(response.bodyBytes)),
          );
          _selectedAccidentType = -1;
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _loadVehiclesType() async {
    final url = Uri.parse('$_baseUrl/vehicleTypes');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _vehicles = List<Map<String, dynamic>>.from(
            json.decode(utf8.decode(response.bodyBytes)),
          );
          _selectedVehicles = [];
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _loadAccidentsCategories() async {
    final url = Uri.parse('$_baseUrl/categories');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(
            json.decode(utf8.decode(response.bodyBytes)),
          );
          _selectedCategory = 0;
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _states() async {
    final url = Uri.parse('$_baseUrl/states');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _stateOptions = [
            {'id': 0, 'name': 'All States'},
            ...List<Map<String, dynamic>>.from(
              json.decode(utf8.decode(response.bodyBytes)),
            ),
          ];
          _selectedState = 0;
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _cities() async {
    if (_selectedState == 0) {
      setState(() {
        _cityOptions = [
          {'id': 1000000, 'name': 'All Cities'},
        ];
        _selectedCity = 1000000;
      });
      return;
    }
    final url = Uri.parse('$_baseUrl/cities?state=$_selectedState');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _cityOptions = [
            {'id': 1000000, 'name': 'All Cities'},
            ...List<Map<String, dynamic>>.from(
              json.decode(utf8.decode(response.bodyBytes)),
            ),
          ];
          _selectedCity = 1000000;
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  LatLng? _stateCentroid(String state) => null;
  double _stateRadius(String state) => 0.0;

  Widget _buildDrawerDropdown<T>(
    String label,
    T value,
    List<T> options,
    void Function(T?) onChanged, {
    bool highlight = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: highlight
                    ? const Color(0xFF38BDF8)
                    : const Color(0xFF334155),
              ),
            ),
            child: DropdownButton<T>(
              value: options.contains(value) ? value : null,
              dropdownColor: const Color(0xFF1E293B),
              isExpanded: true,
              underline: const SizedBox(),
              items: options
                  .map(
                    (option) => DropdownMenuItem<T>(
                      value: option,
                      child: Text(
                        option.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      endDrawer: Drawer(
        width: 450,
        backgroundColor: const Color(0xFF0B1329),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'QUERY FILTERS',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade300,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(45),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedState = 0;
                      _selectedCity = 1000000;
                      _selectedYear = 'All Years';
                      _selectedMonth = 'All Months';
                      _selectedDay = 'All Days';
                      _selectedHour = 'All Hours';
                      _selectedVehicles.clear();
                      _selectedCategory = 0;
                      _selectedAccidentType = -1;
                    });
                    _loadAccidentsFilter();
                  },
                  child: const Text(
                    'Clear Filters',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'German Region Selection',
                  Icons.location_city_outlined,
                ),
                const SizedBox(height: 10),
                _buildDropdownRow('State', _selectedState, _stateOptions, (
                  val,
                ) {
                  setState(() {
                    _selectedState = val;
                  });
                  _cities();
                  _loadAccidentsFilter();
                }),
                const SizedBox(height: 12),
                _buildDropdownRow('Cities', _selectedCity, _cityOptions, (val) {
                  setState(() {
                    _selectedCity = val;
                  });
                  _loadAccidentsFilter();
                }),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'Date & Time Selection',
                  Icons.date_range_outlined,
                ),
                const SizedBox(height: 10),
                _buildDrawerDropdown('Year', _selectedYear, _yearOptions, (
                  value,
                ) {
                  setState(() {
                    _selectedYear = value ?? _selectedYear;
                    _loadAccidentsFilter();
                  });
                }),
                const SizedBox(height: 12),
                _buildDrawerDropdown(
                  'Month',
                  _selectedMonth,
                  _visibleMonthOptions,
                  (value) {
                    setState(() {
                      _selectedMonth = value ?? _selectedMonth;
                      _loadAccidentsFilter();
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildDrawerDropdown('Day', _selectedDay, _visibleDayOptions, (
                  value,
                ) {
                  setState(() {
                    _selectedDay = value ?? _selectedDay;
                    _loadAccidentsFilter();
                  });
                }),
                const SizedBox(height: 12),
                _buildDrawerDropdown(
                  'Hour',
                  _selectedHour,
                  _visibleHourOptions,
                  (value) {
                    setState(() {
                      _selectedHour = value ?? _selectedHour;
                      _loadAccidentsFilter();
                    });
                  },
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'Accident Types',
                  Icons.assignment_turned_in_outlined,
                ),
                _buildToggleList(_accidentsTypes, _selectedAccidentType, (id) {
                  setState(() {
                    _selectedAccidentType = id;
                  });
                  _loadAccidentsFilter();
                }, Colors.green),
                const SizedBox(height: 20),
                _buildSectionHeader('Categories', Icons.lan_outlined),
                _buildToggleList(_categories, _selectedCategory, (id) {
                  setState(() {
                    _selectedCategory = id;
                  });
                  _loadAccidentsFilter();
                }, Colors.orange),
                const SizedBox(height: 20),
                _buildSectionHeader('Vehicles Type', Icons.directions_car),
                _buildMultiVehicleList(),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _showLogoutDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      appBar: AppBar(
        title: const Text('Saferoute Accident Integration Hub'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildSectionHeader('Germany Traffic Incident Layout', Icons.map),
            const SizedBox(height: 10),
            Expanded(child: _buildMapPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownRow(
    String label,
    int? selectedValue,
    List<Map<String, dynamic>> options,
    ValueChanged<int?> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButton<int>(
              value: options.any((e) => e['id'] == selectedValue)
                  ? selectedValue
                  : null,
              dropdownColor: const Color(0xFF1E293B),
              isExpanded: true,
              underline: const SizedBox(),
              items: options
                  .map(
                    (opt) => DropdownMenuItem<int>(
                      value: opt['id'] as int,
                      child: Text(
                        opt['name'].toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleList(
    List<Map<String, dynamic>> source,
    int? selectedId,
    ValueChanged<int> onSelected,
    Color activeColor,
  ) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: source.length,
      itemBuilder: (context, idx) {
        final id = source[idx]['id'] as int;
        final name = source[idx]['name'] as String;
        final bool isCurrent = selectedId == id;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: HoverTranslateCard(
            route: name,
            isActive: isCurrent,
            color: activeColor,
            onTap: () => onSelected(id),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMultiVehicleList() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _vehicles.length,
      itemBuilder: (context, idx) {
        final id = _vehicles[idx]['id'] as int;
        final name = _vehicles[idx]['name'] as String;
        final isSelected = _selectedVehicles.contains(id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: HoverTranslateCard(
            route: name,
            isActive: isSelected,
            color: Colors.blueAccent,
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedVehicles.remove(id);
                } else {
                  _selectedVehicles.add(id);
                }
              });
              _loadAccidentsFilter();
            },
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(name, style: const TextStyle(color: Colors.white)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF38BDF8)),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF38BDF8),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildMapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _germanyCenter,
            initialZoom: 6,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.myapp',
            ),
            MarkerLayer(
              markers: _accidentMarkers.isNotEmpty
                  ? _accidentMarkers
                  : [
                      const Marker(
                        width: 32,
                        height: 32,
                        point: _germanyCenter,
                        child: Icon(
                          Icons.location_city,
                          color: Color(0xFF38BDF8),
                          size: 32,
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}



