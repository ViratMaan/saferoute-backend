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
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';

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

  // Toggles and Options Arrays
  List<Map<String, dynamic>> _accidentsTypes = [];
  List<Map<String, dynamic>> _categories = [];
  int? _selectedAccidentType;
  int? _selectedCategory;

  String _selectedYear = 'All Years';
  String _selectedMonth = 'All Months';
  String _selectedDay = 'All Days';
  String _selectedHour = 'All Hours';

  List<Map<String, dynamic>> _stateOptions = [];
  List<Map<String, dynamic>> _cityOptions = [];
  int? _selectedState;
  int? _selectedCity;

  List<Map<String, dynamic>> _vehicles = [];
  List<int> _selectedVehicles = [];
  final Map<int, List<int>> _citiesByState = {};

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

  final Map<String, LatLng> _cityCenters = {
    'Stuttgart': const LatLng(48.775846, 9.182932),
    'Karlsruhe': const LatLng(49.006890, 8.403653),
    'Freiburg': const LatLng(47.999008, 7.842104),
    'Heidelberg': const LatLng(49.398752, 8.672434),
    'Munich': const LatLng(48.137154, 11.576124),
    'Nuremberg': const LatLng(49.452103, 11.076665),
    'Augsburg': const LatLng(48.370545, 10.897790),
    'Regensburg': const LatLng(49.013430, 12.101624),
    'Berlin': const LatLng(52.520008, 13.404954),
    'Potsdam': const LatLng(52.390569, 13.064473),
    'Cottbus': const LatLng(51.756310, 14.332867),
    'Frankfurt (Oder)': const LatLng(52.347140, 14.550620),
    'Bremen': const LatLng(53.079296, 8.801694),
    'Bremerhaven': const LatLng(53.539585, 8.580942),
    'Hamburg': const LatLng(53.551086, 9.993682),
    'Wiesbaden': const LatLng(50.082039, 8.241656),
    'Frankfurt': const LatLng(50.110924, 8.682127),
    'Darmstadt': const LatLng(49.872825, 8.651193),
    'Hanover': const LatLng(52.375892, 9.732010),
    'Braunschweig': const LatLng(52.268874, 10.526770),
    'Göttingen': const LatLng(51.541280, 9.915803),
    'Rostock': const LatLng(54.092441, 12.099147),
    'Schwerin': const LatLng(53.629372, 11.413160),
    'Greifswald': const LatLng(54.093110, 13.387860),
    'Düsseldorf': const LatLng(51.227741, 6.773456),
    'Cologne': const LatLng(50.937531, 6.960279),
    'Dortmund': const LatLng(51.513587, 7.465298),
    'Bonn': const LatLng(50.737430, 7.098207),
    'Mainz': const LatLng(49.992863, 8.247253),
    'Koblenz': const LatLng(50.356943, 7.588995),
    'Trier': const LatLng(49.749992, 6.637143),
    'Saarbrücken': const LatLng(49.240157, 6.996933),
    'Dresden': const LatLng(51.050407, 13.737262),
    'Leipzig': const LatLng(51.339695, 12.373075),
    'Chemnitz': const LatLng(50.827845, 12.921370),
    'Magdeburg': const LatLng(52.120533, 11.627624),
    'Halle': const LatLng(51.496980, 11.968802),
    'Dessau': const LatLng(51.838640, 12.245550),
    'Kiel': const LatLng(54.323293, 10.122765),
    'Lübeck': const LatLng(53.865467, 10.686559),
    'Flensburg': const LatLng(54.793743, 9.446996),
    'Erfurt': const LatLng(50.984768, 11.029880),
    'Jena': const LatLng(50.927055, 11.589237),
    'Weimar': const LatLng(50.979493, 11.323544),
  };

  late final List<String> _yearOptions = [
    'All Years',
    for (var y = 2018; y <= _yesterday.year; y++) y.toString(),
  ];

  final List<String> _monthOptions = [
    'All Months', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _selectedState = 0;
    _cityOptions = [{'id': 1000000, 'name': 'All Cities'}];
    _selectedCity = 1000000;
    _selectedYear = 'All Years';
    _selectedMonth = 'All Months';
    _selectedDay = 'All Days';
    _selectedHour = 'All Hours';

    _loadVehiclesType();
    _loadAccidentsType();
    _states();
    _loadAccidentsCategories();
  }

  List<int> get _visibleCityOptions => _citiesByState[_selectedState] ?? [];

  bool _isWithinThreshold(LatLng a, LatLng b, {double threshold = 0.18}) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy <= threshold * threshold;
  }

  bool get _selectedCityHasMarkers {
    if (_selectedCity == 1000000 || _selectedCity == 0) return true;
    final city = _cityOptions.where((e) => e['id'] == _selectedCity);
    return city.isNotEmpty;
  }

  bool get _selectedStateHasMarkers => false;

  List<String> get _visibleMonthOptions {
    if (_selectedYear == _yesterday.year.toString()) {
      return _monthOptions.take(_yesterday.month).toList();
    }
    return _monthOptions;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  List<String> get _visibleHourOptions {
    final selectedYear = int.tryParse(_selectedYear);
    final selectedDay = int.tryParse(_selectedDay);
    final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth);

    if (selectedYear == null || selectedDay == null) {
      return ['All Hours', for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0')];
    }
    if (selectedYear == _yesterday.year && selectedMonthIndex == _yesterday.month && selectedDay == _yesterday.day) {
      return ['All Hours', for (var h = 0; h <= _yesterday.hour; h++) h.toString().padLeft(2, '0')];
    }
    return ['All Hours', for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0')];
  }

  List<String> get _visibleDayOptions {
    final selectedYear = int.tryParse(_selectedYear);
    if (selectedYear == null) return ['All Days'];

    final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth);
    if (selectedMonthIndex <= 0) return ['All Days'];

    final dayCount = _daysInMonth(selectedYear, selectedMonthIndex);
    if (selectedYear == _yesterday.year && selectedMonthIndex == _yesterday.month) {
      return ['All Days', for (var d = 1; d <= _yesterday.day; d++) d.toString()];
    }
    return ['All Days', for (var d = 1; d <= dayCount; d++) d.toString()];
  }

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
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
      MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false,
    );
  }

  Future<void> _loadAccidentsFilter() async {
    final queryParameters = {
      if (_selectedState != 0 && _selectedState != null) 'state': _selectedState.toString(),
      if (_selectedCity != 1000000 && _selectedCity != null) 'city': _selectedCity.toString(),
      if (_selectedYear != 'All Years') 'year': _selectedYear,
      if (_selectedMonth != 'All Months') 'month': _monthOptions.indexOf(_selectedMonth).toString(),
      if (_selectedDay != 'All Days') 'day': _selectedDay,
      if (_selectedHour != 'All Hours') 'hour': _selectedHour,
      if (_selectedCategory != 0 && _selectedCategory != null) 'category': _selectedCategory.toString(),
      if (_selectedAccidentType != -1 && _selectedAccidentType != null) 'accident_type': _selectedAccidentType.toString(),
    };

    final url = Uri.parse('$_baseUrl/accidents/filter').replace(queryParameters: queryParameters);
    final finalUrl = url.replace(
      queryParameters: {
        ...url.queryParameters.map((k, v) => MapEntry(k, [v])),
        'vehicle_type': _selectedVehicles.map((e) => e.toString()).toList(),
      },
    );

    try {
      final response = await http.get(finalUrl);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final markers = <Marker>[];
        final polygonPoints = <LatLng>[];
        _accidentMarkers =[];

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
              child: const Icon(Icons.circle, color: Colors.green, size: 20),
            ),
          );
        }
        setState(() {
          _accidentMarkers = markers;
          _polygonPoints = polygonPoints;
          if (polygonPoints.isNotEmpty) {
            final bounds = LatLngBounds.fromPoints(polygonPoints);
            _mapController.fitCamera(
              CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
            );
          }
        });
      }
    } catch (e) {
      print('ERROR LOADING MARKERS: $e');
    }
  }

  Future<void> _loadAccidentsType() async {
    final url = Uri.parse('$_baseUrl/accidentTypes');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _accidentsTypes = List<Map<String, dynamic>>.from(data);
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
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _vehicles = List<Map<String, dynamic>>.from(data);
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
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data);
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
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _stateOptions = [
            {'id': 0, 'name': 'All States'},
            ...List<Map<String, dynamic>>.from(data),
          ];
          _selectedState = 0;
        });
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  // ─── OPTIMIZED CITIES CALL WITH STATE BOUNDARY ENFORCEMENT ──────────────────
  Future<void> _cities() async {
    int stateIdToSend = (_selectedState == 0 || _selectedState == null) ? 1 : _selectedState!;

    final url = Uri.parse('$_baseUrl/cities').replace(
      queryParameters: {'state': stateIdToSend.toString()},
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _cityOptions = [
            {'id': 1000000, 'name': 'All Cities'},
            ...List<Map<String, dynamic>>.from(data),
          ];
          _selectedCity = 1000000;
        });
      }
    } catch (e) {
      print('ERROR FETCHING CITIES: $e');
    }
  }

  LatLng? _stateCentroid(String state) {
    final cities = _citiesByState[state] ?? [];
    if (cities.isEmpty) return null;
    final centers = cities.map((city) => _cityCenters[city]).whereType<LatLng>().toList();
    if (centers.isEmpty) return null;
    final avgLat = centers.map((c) => c.latitude).reduce((a, b) => a + b) / centers.length;
    final avgLon = centers.map((c) => c.longitude).reduce((a, b) => a + b) / centers.length;
    return LatLng(avgLat, avgLon);
  }

  double _stateRadius(String state) {
    final centroid = _stateCentroid(state);
    if (centroid == null) return 0.0;
    final cities = _citiesByState[state] ?? [];
    final centers = cities.map((city) => _cityCenters[city]).whereType<LatLng>().toList();
    if (centers.isEmpty) return 0.0;
    final distances = centers.map((c) {
      final dx = c.latitude - centroid.latitude;
      final dy = c.longitude - centroid.longitude;
      return sqrt(dx * dx + dy * dy);
    }).toList();
    return (distances.reduce(max) + 0.4).clamp(0.5, 2.0);
  }

  Widget _buildDrawerDropdown<T>(
    String label,
    T value,
    List<T> options,
    void Function(T?) onChanged, {
    bool highlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 1,
          child: Text(
            label,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade400, fontWeight: FontWeight.w600),
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
                color: highlight ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                width: highlight ? 2.0 : 1.2,
              ),
            ),
            child: DropdownButton<T>(
              value: options.contains(value) ? value : null,
              dropdownColor: const Color(0xFF1E293B),
              isExpanded: true,
              underline: const SizedBox(),
              items: options.map((option) {
                return DropdownMenuItem<T>(
                  value: option,
                  child: Text(option.toString(), style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: onChanged,
              iconEnabledColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawerBarrierDismissible: false,
      endDrawer: Drawer(
        width: 600,
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
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.grey.shade400, letterSpacing: 0.8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: Colors.white70,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
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
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.0),
                      child: Text('Clear Filters', style: TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_hasFilters) ...[
                  const Text('Selected Filters', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  _buildSelectedFilters(),
                  const SizedBox(height: 20),
                ],
                _buildSectionHeader('German Region Selection', Icons.location_city_outlined),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: Text('State', style: TextStyle(fontSize: 15, color: Colors.grey.shade400, fontWeight: FontWeight.w600))),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155), width: 1.2),
                          ),
                          child: DropdownButton<int>(
                            value: _stateOptions.any((e) => e['id'] == _selectedState) ? _selectedState : 0,
                            dropdownColor: const Color(0xFF1E293B),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _stateOptions.map((state) {
                              return DropdownMenuItem<int>(
                                value: state['id'],
                                child: Text(state['name'], style: const TextStyle(color: Colors.white)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() { _selectedState = value; });
                              _cities();
                              _loadAccidentsFilter();
                            },
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: Text('Cities', style: TextStyle(fontSize: 15, color: Colors.grey.shade400, fontWeight: FontWeight.w600))),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedCityHasMarkers ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                              width: _selectedCityHasMarkers ? 2.0 : 1.2,
                            ),
                          ),
                          child: DropdownButton<int>(
                            value: _cityOptions.any((e) => e['id'] == _selectedCity) ? _selectedCity : 1000000,
                            dropdownColor: const Color(0xFF1E293B),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _cityOptions.map((cityObj) {
                              return DropdownMenuItem<int>(
                                value: cityObj['id'],
                                child: Text(cityObj['name'], style: const TextStyle(color: Colors.white)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() { _selectedCity = value; });
                              _loadAccidentsFilter();
                            },
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('Date & Time Selection', Icons.date_range_outlined),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildDrawerDropdown<String>('Year', _selectedYear, _yearOptions, (value) {
                    setState(() {
                      _selectedYear = value ?? _selectedYear;
                      if (!_visibleMonthOptions.contains(_selectedMonth)) _selectedMonth = _visibleMonthOptions.last;
                      if (!_visibleDayOptions.contains(_selectedDay)) _selectedDay = _visibleDayOptions.last;
                      if (!_visibleHourOptions.contains(_selectedHour)) _selectedHour = _visibleHourOptions.last;
                      _loadAccidentsFilter();
                    });
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: _buildDrawerDropdown<String>('Month', _selectedMonth, _visibleMonthOptions, (value) {
                    setState(() {
                      _selectedMonth = value ?? _selectedMonth;
                      if (!_visibleDayOptions.contains(_selectedDay)) _selectedDay = _visibleDayOptions.last;
                      if (!_visibleHourOptions.contains(_selectedHour)) _selectedHour = _visibleHourOptions.last;
                      _loadAccidentsFilter();
                    });
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildDrawerDropdown<String>('Day', _selectedDay, _visibleDayOptions, (value) {
                    setState(() {
                      _selectedDay = value ?? _selectedDay;
                      if (!_visibleHourOptions.contains(_selectedHour)) _selectedHour = _visibleHourOptions.last;
                      _loadAccidentsFilter();
                    });
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                  child: _buildDrawerDropdown<String>('Hour', _selectedHour, _visibleHourOptions, (value) {
                    setState(() {
                      _selectedHour = value ?? _selectedHour;
                      _loadAccidentsFilter();
                    });
                  }),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('Accident Types', Icons.assignment_turned_in_outlined),
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _accidentsTypes.length,
                  itemBuilder: (context, idx) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: HoverTranslateCard(
                        route: _accidentsTypes[idx]['name'],
                        isActive: _selectedAccidentType == _accidentsTypes[idx]['id'],
                        color: Colors.green,
                        onTap: () {
                          setState(() { _selectedAccidentType = _accidentsTypes[idx]['id']; });
                          _loadAccidentsFilter();
                        },
                        child: Text(_accidentsTypes[idx]['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildSectionHeader('Categories', Icons.lan_outlined),
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _categories.length,
                  itemBuilder: (context, idx) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: HoverTranslateCard(
                        route: _categories[idx]['name'],
                        isActive: _selectedCategory == _categories[idx]['id'],
                        color: Colors.orange,
                        onTap: () {
                          setState(() { _selectedCategory = _categories[idx]['id']; });
                          _loadAccidentsFilter();
                        },
                        child: Text(_categories[idx]['name']),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildSectionHeader('Vehicles Type', Icons.directions_car),
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _vehicles.length,
                  itemBuilder: (context, idx) {
                    final id = _vehicles[idx]['id'];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: HoverTranslateCard(
                        route: _vehicles[idx]['name'].toString(),
                        isActive: _selectedVehicles.contains(id),
                        color: Colors.white10,
                        onTap: () {
                          setState(() {
                            if (_selectedVehicles.contains(id)) {
                              _selectedVehicles.remove(id);
                            } else {
                              _selectedVehicles.add(id);
                            }
                          });
                          _loadAccidentsFilter();
                        },
                        child: Text(_vehicles[idx]['name']),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: ElevatedButton.icon(
                    onPressed: _showLogoutDialog,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.red.shade700),
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text('Logout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      appBar: AppBar(
        title: const Text('DBW Accident Integration Hub'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 10.0,
      ),
      body: SingleChildScrollView(
        child: Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader('Germany Map', Icons.map),
              _buildMapPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedFilters() {
    final List<Widget> chips = [];

    if (_selectedState != 0 && _selectedState != null) {
      final state = _stateOptions.firstWhere((e) => e['id'] == _selectedState, orElse: () => {'name': ''});
      chips.add(_buildFilterChip(state['name'], () {
        setState(() { _selectedState = 0; _selectedCity = 1000000; });
        _loadAccidentsFilter();
      }));
    }
    if (_selectedCity != 1000000 && _selectedCity != null) {
      final city = _cityOptions.firstWhere((e) => e['id'] == _selectedCity, orElse: () => {'name': ''});
      chips.add(_buildFilterChip(city['name'], () {
        setState(() { _selectedCity = 1000000; });
        _loadAccidentsFilter();
      }));
    }
    if (_selectedYear != 'All Years') {
      chips.add(_buildFilterChip(_selectedYear, () { setState(() { _selectedYear = 'All Years'; }); _loadAccidentsFilter(); }));
    }
    if (_selectedMonth != 'All Months') {
      chips.add(_buildFilterChip(_selectedMonth, () { setState(() { _selectedMonth = 'All Months'; }); _loadAccidentsFilter(); }));
    }
    if (_selectedDay != 'All Days') {
      chips.add(_buildFilterChip('Day $_selectedDay', () { setState(() { _selectedDay = 'All Days'; }); _loadAccidentsFilter(); }));
    }
    if (_selectedHour != 'All Hours') {
      chips.add(_buildFilterChip('$_selectedHour:00', () { setState(() { _selectedHour = 'All Hours'; }); _loadAccidentsFilter(); }));
    }
    if (_selectedCategory != 0 && _selectedCategory != null) {
      final category = _categories.firstWhere((e) => e['id'] == _selectedCategory, orElse: () => {'name': ''});
      chips.add(_buildFilterChip(category['name'], () { setState(() { _selectedCategory = 0; }); _loadAccidentsFilter(); }));
    }
    if (_selectedAccidentType != -1 && _selectedAccidentType != null) {
      final type = _accidentsTypes.firstWhere((e) => e['id'] == _selectedAccidentType, orElse: () => {'name': ''});
      chips.add(_buildFilterChip(type['name'], () { setState(() { _selectedAccidentType = -1; }); _loadAccidentsFilter(); }));
    }
    for (final vehicleId in _selectedVehicles) {
      final vehicle = _vehicles.firstWhere((e) => e['id'] == vehicleId, orElse: () => {'name': ''});
      chips.add(_buildFilterChip(vehicle['name'], () { setState(() { _selectedVehicles.remove(vehicleId); }); _loadAccidentsFilter(); }));
    }

    if (chips.isEmpty) return Text('No filters selected', style: TextStyle(color: Colors.grey.shade500));
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildFilterChip(String label, VoidCallback onDeleted) {
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      deleteIcon: const Icon(Icons.close, color: Colors.white, size: 18),
      onDeleted: onDeleted,
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Color(0xFF38BDF8)),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8), letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _buildMapPanel() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: const MapOptions(initialCenter: _germanyCenter, initialZoom: 6),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.myapp',
            ),
            if (_cityCenters.containsKey(_selectedCity))
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _polygonPoints,
                    color: Colors.blue.withOpacity(0.25),
                    borderColor: Colors.blueAccent.withOpacity(0.9),
                    borderStrokeWidth: 3,
                  ),
                ],
              )
            else if (_stateCentroid(_selectedState.toString()) != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _stateCentroid(_selectedState.toString())!,
                    color: Colors.purple,
                    borderColor: Colors.purpleAccent,
                    borderStrokeWidth: 3,
                    radius: _stateRadius(_selectedState.toString()),
                    useRadiusInMeter: false,
                  ),
                ],
              ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 45,
                size: const Size(40, 40),
                markers: _accidentMarkers.isNotEmpty ? _accidentMarkers : [
                  Marker(
                    width: 32,
                    height: 32,
                    point: _germanyCenter,
                    child: const Icon(Icons.circle, color: Colors.green, size: 20),
                  ),
                ],
                builder: (context, markers) {
                  return Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.blue),
                    child: Center(child: Text(markers.length.toString(), style: const TextStyle(color: Colors.white))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}   
