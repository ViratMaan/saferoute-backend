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

class DrawerQuery {
  DrawerQuery({
    required this.idx,
    required this.title,
    required this.desc,
    required this.route,
    required this.color,
    this.checked = false,
  });

  final String idx;
  final String title;
  final String desc;
  final String route;
  final Color color;
  bool checked;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String _baseUrl = "https://saferoute-intelligence-api.onrender.com";
  String _apiOutput =
      "// Ready for execution. Choose a structured examiner preset from the catalog.";
  bool _isLoading = false;
  int _statusCode = 0;
  String _activeRoute = "";
  String _activeDescription = "";
  final bool _enableAdvancedMode = false;

  final DateTime _yesterday = DateTime.now().subtract(const Duration(days: 1));
  final MapController _mapController = MapController();
  static const LatLng _germanyCenter = LatLng(51.1657, 10.4515);
  final double _mapZoom = 1.5;
  List<Marker> _accidentMarkers = [];
  // raw coordinates from API: [lat, lon, severity, vehicleType?]
  List<List<dynamic>> _accidentCoordinates = [];

  // vehicle type toggles
  List<Map<String, dynamic>> _accidentsTypes = [];
  List<Map<String, dynamic>> _categories = [];
  int? _selectedAccidentType;
  int? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedYear = _yesterday.year.toString();
    _selectedMonth = _monthOptions[_yesterday.month - 1];
    _selectedDay = _yesterday.day.toString();
    _selectedHour = _yesterday.hour.toString().padLeft(2, '0');
    _loadAccidentsType();
    _states();
    _loadAccidentsCategories();
  }

  late final List<String> _yearOptions = [
    for (var y = 2018; y <= _yesterday.year; y++) y.toString(),
  ];
  final List<String> _monthOptions = [
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

  final List<String> _vehicles = ['Car', 'Bicycle', 'Pedestrian', 'Motorcycle'];

  Map<int, List<int>> _citiesByState = {};

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

  bool _cityHasMarker(String city) {
    final center = _cityCenters[city];
    if (center == null) return false;
    return _accidentCoordinates.any((coord) {
      final lat = (coord[0] as num).toDouble();
      final lon = (coord[1] as num).toDouble();
      return _isWithinThreshold(center, LatLng(lat, lon));
    });
  }

  bool get _selectedCityHasMarkers {
    if (_selectedCity == null) return false;

    final cityName = _cityOptions.firstWhere(
      (e) => e['id'] == _selectedCity,
    )['name'];

    return _cityHasMarker(cityName);
  }

  bool get _selectedStateHasMarkers => false;

  // bool get _selectedStateHasMarkers {
  //   if (_selectedState == null) return false;
  //   return (_citiesByState[_selectedState] ?? []).any(_cityHasMarker);
  // }

  List<String> get _visibleMonthOptions {
    if (_selectedYear == _yesterday.year.toString()) {
      return _monthOptions.take(_yesterday.month).toList();
    }
    return _monthOptions;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  // List<String> get _visibleDayOptions {
  //   final selectedYear = int.parse(_selectedYear);
  //   final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth) + 1;
  //   final dayCount = _daysInMonth(selectedYear, selectedMonthIndex);
  //   if (selectedYear == _yesterday.year &&
  //       selectedMonthIndex == _yesterday.month) {
  //     return [for (var d = 1; d <= _yesterday.day; d++) d.toString()];
  //   }
  //   return [for (var d = 1; d <= dayCount; d++) d.toString()];
  // }

  List<String> get _visibleHourOptions {
    final selectedYear = int.tryParse(_selectedYear);
    final selectedDay = int.tryParse(_selectedDay);
    final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth) + 1;

    if (selectedYear == null || selectedDay == null) {
      return [for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0')];
    }

    if (selectedYear == _yesterday.year &&
        selectedMonthIndex == _yesterday.month &&
        selectedDay == _yesterday.day) {
      return [
        for (var h = 0; h <= _yesterday.hour; h++) h.toString().padLeft(2, '0'),
      ];
    }

    return [for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0')];
  }

  List<String> get _visibleDayOptions {
    final selectedYear = int.tryParse(_selectedYear);

    if (selectedYear == null) {
      return [];
    }

    final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth) + 1;

    if (selectedMonthIndex <= 0) {
      return [];
    }

    final dayCount = _daysInMonth(selectedYear, selectedMonthIndex);

    if (selectedYear == _yesterday.year &&
        selectedMonthIndex == _yesterday.month) {
      return [for (var d = 1; d <= _yesterday.day; d++) d.toString()];
    }

    return [for (var d = 1; d <= dayCount; d++) d.toString()];
  }

  // List<String> get _visibleHourOptions {
  //   final selectedYear = int.parse(_selectedYear);
  //   final selectedMonthIndex = _monthOptions.indexOf(_selectedMonth) + 1;
  //   final selectedDay = int.parse(_selectedDay);
  //   if (selectedYear == _yesterday.year &&
  //       selectedMonthIndex == _yesterday.month &&
  //       selectedDay == _yesterday.day) {
  //     return [
  //       for (var h = 0; h <= _yesterday.hour; h++) h.toString().padLeft(2, '0'),
  //     ];
  //   }
  //   return [for (var h = 0; h < 24; h++) h.toString().padLeft(2, '0')];
  // }

  String _selectedYear = '';
  String _selectedMonth = '';
  String _selectedDay = '';
  String _selectedHour = '';

  // Per-item checkbox selections in the drawer list
  final List<DrawerQuery> _drawerQueries = [
    DrawerQuery(
      idx: 'Q1',
      title: 'Earliest Accident Year',
      desc: 'Calculates global baseline timeline minimum.',
      route: '/accidents/time/earliest',
      color: const Color(0xFF38BDF8),
    ),
    DrawerQuery(
      idx: 'Q2',
      title: 'Saxony 2023 Injury Matrix',
      desc:
          'Aggregates counts restricted strictly to Saxony and true injuries.',
      route: '/aggregates/accidents?state=SN&year=2023&injury=true',
      color: const Color(0xFF34D399),
    ),
    DrawerQuery(
      idx: 'Q3',
      title: 'NRW Coverage Timeline',
      desc: 'Minimum record index year localized to North Rhine-Westphalia.',
      route: '/accidents/time/earliest?state=NW',
      color: const Color(0xFFFB923C),
    ),
    DrawerQuery(
      idx: 'Q4',
      title: 'Mecklenburg Timeline',
      desc:
          'Minimum record index year localized to Mecklenburg-Western Pomerania.',
      route: '/accidents/time/earliest?state=MV',
      color: const Color(0xFFF472B6),
    ),
    DrawerQuery(
      idx: 'Q5',
      title: 'Berlin Pedestrians (2023)',
      desc:
          'Filters occurrences intersecting Berlin regional keys with pedestrians.',
      route: '/aggregates/accidents?state=BE&year=2023&participant=pedestrian',
      color: const Color(0xFF60A5FA),
    ),
  ];

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _logout();
    }
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

  Future<void> _executeQuery(String endpoint, String title, String desc) async {
    setState(() {
      _isLoading = true;
      _activeRoute = endpoint;
      _activeDescription = desc;
      _apiOutput =
          "/* TRANSMITTING REQUEST TO BACKEND HARDWARE LAYER */\nGET $_baseUrl$endpoint ...";
    });

    try {
      final response = await http.get(Uri.parse('$_baseUrl$endpoint'));
      setState(() {
        _statusCode = response.statusCode;
        if (response.statusCode == 200) {
          var decodedJson = json.decode(utf8.decode(response.bodyBytes));
          _apiOutput = const JsonEncoder.withIndent('  ').convert(decodedJson);
        } else {
          _apiOutput =
              "/* ERROR RESPONSE RECEIVED FROM BACKEND PIPELINE */\n\nHTTP STATUS: $_statusCode\n\nPayload:\n${response.body}";
        }
      });
    } catch (e) {
      setState(() {
        _statusCode = 0;
        _apiOutput =
            "/* PIPELINE CONNECTION TIMEOUT / PROTOCOL ERROR */\n\n"
            "Could not connect to: $_baseUrl$endpoint\n\n"
            "Troubleshooting Steps:\n"
            "1. Confirm your student-built backend web service container is fully operational on port 8080.\n"
            "2. If compiling for Flutter Web, make sure CORS configurations are active.\n\n"
            "System Logs:\n$e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAccidentsFilter() async {
    final url = Uri.parse('$_baseUrl/accidents/filter').replace(
      queryParameters: {
        if (_selectedState != null) 'state': _selectedState.toString(),

        if (_selectedCity != null) 'city': _selectedCity.toString(),

        'year': _selectedYear,

        'month': (_monthOptions.indexOf(_selectedMonth) + 1).toString(),

        'day': _selectedDay,

        'hour': _selectedHour,

        if (_selectedAccidentType != null)
          'accident_type': _selectedAccidentType.toString(),

        if (_selectedCategory != null) 'category': _selectedCategory.toString(),

        if (_vehicles != []) 'vehicle_type': _vehicles,
      },
    );
    try {
      final response = await http.get(url);

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        print('Loaded ${data}');
        print('Status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _loadAccidentsType() async {
    final url = Uri.parse('$_baseUrl/accidentTypes');
    try {
      final response = await http.get(url);

      print('Status: ${response.statusCode}');
      print('BodyAccidentTypes: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _accidentsTypes = List<Map<String, dynamic>>.from(data);
        if (_accidentsTypes.isNotEmpty) {
          _selectedAccidentType = _accidentsTypes.first['id'];
        }
        setState(() {});

        print('Loaded ${data}');
        print('Status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _loadAccidentsCategories() async {
    final url = Uri.parse('$_baseUrl/categories');
    try {
      final response = await http.get(url);

      print('Status: ${response.statusCode}');
      print('BodyCategories: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _categories = List<Map<String, dynamic>>.from(data);
        if (_categories.isNotEmpty) {
          _selectedCategory = _categories.first['id'];
        }
        setState(() {});

        print('Loaded ${data}');
        print('Status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  Future<void> _states() async {
    final url = Uri.parse('$_baseUrl/states');
    try {
      final response = await http.get(url);

      print('Status: ${response.statusCode}');
      print('BodyState: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        _stateOptions = List<Map<String, dynamic>>.from(data);
        if (_stateOptions.isNotEmpty) {
          _selectedState = _stateOptions.first['id'];
        }
        setState(() {});

        print('Loaded ${data}');
        print('Status: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  // Future<void> _cities() async {
  //   final url = Uri.parse(
  //     '$_baseUrl/cities',
  //   ).replace(queryParameters: {'state': _selectedState.toString()});

  //   try {
  //     final response = await http.get(url);

  //     print('Status: ${response.statusCode}');
  //     print('BodyCities: ${response.body}');

  //     if (response.statusCode == 200) {
  //       final data = json.decode(utf8.decode(response.bodyBytes));
  //       _citiesByState[_selectedState.toString()] = List<Map<String, dynamic>>.from(data);
  //       if (_citiesByState[_selectedState.toString()] != null &&
  //           _citiesByState[_selectedState.toString()]!.isNotEmpty) {
  //         _selectedCity = _citiesByState[_selectedState.toString()]!.first;
  //       }
  //       setState(() {
  //         if (_visibleCityOptions.isNotEmpty) {
  //           _selectedCity = _visibleCityOptions.first;
  //         } else {
  //           _selectedCity = '';
  //         }
  //       });

  //       print('Loaded ${data}');
  //       print('Status: ${response.statusCode}');
  //       print('Response: ${response.body}');
  //     }
  //   } catch (e) {
  //     print('ERROR: $e');
  //   }
  // }

  Future<void> _cities() async {
    final url = Uri.parse(
      '$_baseUrl/cities',
    ).replace(queryParameters: {'state': _selectedState.toString()});

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));

        setState(() {
          _cityOptions = List<Map<String, dynamic>>.from(data);

          _selectedCity = _cityOptions.isNotEmpty
              ? _cityOptions.first['id']
              : null;
        });
        print('$data');
        print('$_cityOptions');
      }
    } catch (e) {
      print('ERROR: $e');
    }
  }

  LatLng? _stateCentroid(String state) {
    final cities = _citiesByState[state] ?? [];
    if (cities.isEmpty) return null;
    final centers = cities
        .map((city) => _cityCenters[city])
        .whereType<LatLng>()
        .toList();
    if (centers.isEmpty) return null;
    final avgLat =
        centers.map((c) => c.latitude).reduce((a, b) => a + b) / centers.length;
    final avgLon =
        centers.map((c) => c.longitude).reduce((a, b) => a + b) /
        centers.length;
    return LatLng(avgLat, avgLon);
  }

  double _stateRadius(String state) {
    final centroid = _stateCentroid(state);
    if (centroid == null) return 0.0;
    final cities = _citiesByState[state] ?? [];
    final centers = cities
        .map((city) => _cityCenters[city])
        .whereType<LatLng>()
        .toList();
    if (centers.isEmpty) return 0.0;
    final distances = centers.map((c) {
      final dx = c.latitude - centroid.latitude;
      final dy = c.longitude - centroid.longitude;
      return sqrt(dx * dx + dy * dy);
    }).toList();
    return (distances.reduce(max) + 0.4).clamp(0.5, 2.0);
  }

  List<LatLng> _cityPolygon(String city, {double radiusDegrees = 1.5}) {
    final center = _cityCenters[city];
    if (center == null) return [];

    final points = <LatLng>[];
    final latRad = center.latitude * pi / 180;
    final lonFactor = cos(latRad);
    const steps = 32;

    for (var i = 0; i < steps; i++) {
      final angle = 2 * pi * i / steps;
      final latOffset = radiusDegrees * sin(angle);
      final lonOffset = (radiusDegrees * cos(angle));
      points.add(
        LatLng(center.latitude + latOffset, center.longitude + lonOffset),
      );
      setState(() {});
    }
    print('City: $city');
    print('Center: $center');
    print('Points generated: ${points.length}');

    return points;
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
      // mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          flex: 1,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
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
                width: highlight ? 2.0 : 1.2,
              ),
              boxShadow: highlight
                  ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.18),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
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
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.white70,
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'German Region Selection',
                  Icons.location_city_outlined,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    // mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          'State',
                          style: TextStyle(
                            fontSize: 15,
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
                              color: _selectedStateHasMarkers
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFF334155),
                              width: _selectedStateHasMarkers ? 2.0 : 1.2,
                            ),
                            boxShadow: _selectedStateHasMarkers
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: DropdownButton<int>(
                            value: _selectedState,
                            dropdownColor: const Color(0xFF1E293B),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _stateOptions
                                .map(
                                  (state) => DropdownMenuItem<int>(
                                    value: state['id'],
                                    child: Text(
                                      state['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedState = value;
                              });
                              _cities();
                            },
                            style: const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // child: DropdownButton<int>(
                  //   value: _selectedState,
                  //   items: _stateOptions.map((state) {
                  //     return DropdownMenuItem<int>(
                  //       value: state['id'],
                  //       child: Text(state['name']),
                  //     );
                  //   }).toList(),
                  //   onChanged: (value) {
                  //     setState(() {
                  //       _selectedState = value;
                  //     });
                  //   },
                  // ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    // mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Cities',
                          style: TextStyle(
                            fontSize: 15,
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
                              color: _selectedCityHasMarkers
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFF334155),
                              width: _selectedCityHasMarkers ? 2.0 : 1.2,
                            ),
                            boxShadow: _selectedCityHasMarkers
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: DropdownButton<int>(
                            value: _selectedCity,
                            dropdownColor: const Color(0xFF1E293B),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _cityOptions
                                .map(
                                  (_visibleCityOptions) =>
                                      DropdownMenuItem<int>(
                                        value: _visibleCityOptions['id'],
                                        child: Text(
                                          _visibleCityOptions['name'],
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCity = value;
                              });
                            },
                            style: const TextStyle(color: Colors.white),
                            iconEnabledColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  //  _buildDrawerDropdown<String>(
                  //   'City',
                  //   _selectedCity,
                  //   _visibleCityOptions,
                  //   (value) => setState(() {
                  //     _selectedCity = value ?? _selectedCity;
                  //     _loadAccidentsFilter();
                  //   }),
                  //   highlight: _selectedCityHasMarkers,
                  // ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Selected Region: $_selectedState • $_selectedCity',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'Date & Time Selection',
                  Icons.date_range_outlined,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildDrawerDropdown<String>(
                    'Year',
                    _selectedYear,
                    _yearOptions,
                    (value) => setState(() {
                      _selectedYear = value ?? _selectedYear;
                      if (!_visibleMonthOptions.contains(_selectedMonth)) {
                        _selectedMonth = _visibleMonthOptions.last;
                      }
                      if (!_visibleDayOptions.contains(_selectedDay)) {
                        _selectedDay = _visibleDayOptions.last;
                      }
                      if (!_visibleHourOptions.contains(_selectedHour)) {
                        _selectedHour = _visibleHourOptions.last;
                      }
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: _buildDrawerDropdown<String>(
                    'Month',
                    _selectedMonth,
                    _visibleMonthOptions,
                    (value) => setState(() {
                      _selectedMonth = value ?? _selectedMonth;
                      if (!_visibleDayOptions.contains(_selectedDay)) {
                        _selectedDay = _visibleDayOptions.last;
                      }
                      if (!_visibleHourOptions.contains(_selectedHour)) {
                        _selectedHour = _visibleHourOptions.last;
                      }
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: _buildDrawerDropdown<String>(
                    'Day',
                    _selectedDay,
                    _visibleDayOptions,
                    (value) => setState(() {
                      _selectedDay = value ?? _selectedDay;
                      if (!_visibleHourOptions.contains(_selectedHour)) {
                        _selectedHour = _visibleHourOptions.last;
                      }
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  child: _buildDrawerDropdown<String>(
                    'Hour',
                    _selectedHour,
                    _visibleHourOptions,
                    (value) => setState(() {
                      _selectedHour = value ?? _selectedHour;
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Selected: $_selectedYear • $_selectedMonth • $_selectedDay • ${_selectedHour}h',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader(
                  'Accident Types',
                  Icons.assignment_turned_in_outlined,
                ),
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _accidentsTypes.length,
                  itemBuilder: (context, idx) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: HoverTranslateCard(
                        route: _accidentsTypes[idx]['name'],
                        isActive: _activeRoute == _accidentsTypes[idx]['name'],
                        color: Color(0x255952),
                        onTap: () => _executeQuery(
                          _accidentsTypes[idx]['name'],
                          _accidentsTypes[idx]['id'],
                          _accidentsTypes[idx]['name'],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Checkbox(
                            //   value: query.checked,
                            //   onChanged: (value) {
                            //     setState(() {
                            //       query.checked = value ?? false;
                            //     });
                            //   },
                            //   activeColor: query.color,
                            //   checkColor: Colors.white,
                            // ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                // color: _accidentsTypes[idx]['name'].color.withAlpha(
                                //   (0.15 * 255).round(),
                                // ),
                                color: Color(
                                  0x568458,
                                ).withAlpha((0.15 * 255).round()),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Color(
                                    0x845545,
                                  ).withAlpha((0.4 * 255).round()),
                                  // color: _accidentsTypes[idx]['name'].color
                                  //     .withAlpha((0.4 * 255).round()),
                                ),
                              ),
                              child: Text(
                                _accidentsTypes[idx]['id'].toString(),
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Consolas',
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _accidentsTypes[idx]['name'],
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _accidentsTypes[idx]['name'],
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _accidentsTypes[idx]['name'],
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 11,
                                      color: Color(0xFF0EA5E9),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.play_circle_fill,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ],
                        ),
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
                      child: _buildEndpointTile(
                        _categories[idx]['id'].toString(),
                        _categories[idx]['name'],
                        'GET',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildSectionHeader('Vehicles Type', Icons.lan_outlined),
                ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _vehicles.length,
                  itemBuilder: (context, idx) {
                    return HoverTranslateCard(
                      route: _vehicles[idx].toString(),
                      isActive: _activeRoute == _vehicles[idx].toString(),
                      color: Colors.white10,
                      onTap: () => _executeQuery(
                        _vehicles[idx].toString(),
                        _vehicles[idx].toString(),
                        _vehicles[idx].toString(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(_vehicles[idx].toString()),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: ElevatedButton.icon(
                    onPressed: _showLogoutDialog,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.red.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
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
        elevation: 50.0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Column(
        children: [
          // Workspace Core
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // _buildConsoleHeaderPanel(),
                const SizedBox(height: 16),

                // Active Endpoint Route Context Badge
                // if (_activeRoute.isNotEmpty) ...[
                //   Container(
                //     padding: const EdgeInsets.all(12),
                //     decoration: BoxDecoration(
                //       color: const Color(0xFF1E293B),
                //       borderRadius: BorderRadius.circular(8),
                //       border: Border.all(color: const Color(0xFF334155)),
                //     ),
                //     child: Column(
                //       crossAxisAlignment: CrossAxisAlignment.start,
                //       children: [
                //         Text(
                //           'ACTIVE ENDPOINT ROUTE:',
                //           style: TextStyle(
                //             fontSize: 10,
                //             fontWeight: FontWeight.bold,
                //             color: Colors.grey.shade400,
                //             letterSpacing: 1,
                //           ),
                //         ),
                //         const SizedBox(height: 4),
                //         SelectableText(
                //           _activeRoute,
                //           style: const TextStyle(
                //             fontFamily: 'Consolas',
                //             fontSize: 13,
                //             color: Color(0xFF38BDF8),
                //             fontWeight: FontWeight.bold,
                //           ),
                //         ),
                //         const SizedBox(height: 6),
                //         Text(
                //           _activeDescription,
                //           style: TextStyle(
                //             fontSize: 11,
                //             color: Colors.grey.shade400,
                //             fontStyle: FontStyle.italic,
                //           ),
                //         ),
                //       ],
                //     ),
                //   ),
                //   const SizedBox(height: 16),
                // ],
                _buildSectionHeader('Germany Map', Icons.map),
                _buildMapPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF38BDF8),
              letterSpacing: 0.8,
            ),
          ),
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
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _cityCenters[_selectedCity] ?? _germanyCenter,
                initialZoom: _mapZoom,
                minZoom: 4,
                maxZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.myapp',
                ),

                if (_cityCenters.containsKey(_selectedCity))
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _cityPolygon(_selectedCity.toString()),
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

                MarkerLayer(
                  markers: _accidentMarkers.isNotEmpty
                      ? _accidentMarkers
                      : [
                          Marker(
                            width: 32,
                            height: 32,
                            point: _germanyCenter,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFF38BDF8),
                              size: 32,
                            ),
                          ),
                        ],
                ),
              ],
            ),

            // Vehicle type toggles (top-left)
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveQueryCard({
    required String idx,
    required String title,
    required String desc,
    required String route,
    required Color color,
  }) {
    bool isActive = _activeRoute == route;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1E293B) : const Color(0xFF151F32),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? color : const Color(0xFF22314D),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _executeQuery(route, title, desc),
          hoverColor: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withAlpha((0.15 * 255).round()),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: color.withAlpha((0.4 * 255).round()),
                    ),
                  ),
                  child: Text(
                    idx,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        route,
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 11,
                          color: Color(0xFF0EA5E9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 2.0),
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 20,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndpointTile(String label, String route, String verb) {
    bool isActive = _activeRoute == route;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E293B) : const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF0EA5E9)
                  : const Color(0xFF1E293B),
            ),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor: Colors.transparent,
            onTap: () => _executeQuery(
              route,
              label,
              'System core data layer endpoint lookup query.',
            ),
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withAlpha((0.15 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                verb,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0EA5E9),
                  fontSize: 10,
                ),
              ),
            ),
            title: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              route,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // Widget _buildConsoleHeaderPanel() {
  //   Color chipColor = _statusCode == 200
  //       ? const Color(0xFF10B981)
  //       : const Color(0xFFEF4444);
  //   if (_statusCode == 0) chipColor = Colors.grey;

  //   return Row(
  //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //     children: [
  //       Row(
  //         children: [
  //           const Icon(Icons.terminal_rounded, color: Colors.grey, size: 20),
  //           const SizedBox(width: 8),
  //           const Text(
  //             'Isolated REST Response Matrix',
  //             style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
  //           ),
  //         ],
  //       ),
  //       Container(
  //         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  //         decoration: BoxDecoration(
  //           color: chipColor.withAlpha((0.15 * 255).round()),
  //           borderRadius: BorderRadius.circular(6),
  //           border: Border.all(color: chipColor.withAlpha((0.4 * 255).round())),
  //         ),
  //         child: Text(
  //           _statusCode == 0 ? 'READY' : 'HTTP STATUS: $_statusCode',
  //           style: TextStyle(
  //             color: chipColor,
  //             fontFamily: 'Consolas',
  //             fontSize: 11,
  //             fontWeight: FontWeight.bold,
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  // ignore: unused_element
  Widget _buildAnimatedQueryCard(
    String idx,
    String title,
    String desc,
    String route,
    Color color,
    bool enableAdvancedMode,
  ) {
    return HoverTranslateCard(
      route: route,
      isActive: _activeRoute == route,
      color: color,
      onTap: () => _executeQuery(route, title, desc),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox(
          //   value: enableAdvancedMode,
          //   onChanged: (value) {
          //     setState(() => _enableAdvancedMode = value ?? false);
          //   },
          //   activeColor: const Color(0xFF0EA5E9),
          //   checkColor: Colors.white,
          // ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha((0.15 * 255).round()),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withAlpha((0.4 * 255).round())),
            ),
            child: Text(
              idx,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'Consolas',
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  route,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    color: Color(0xFF0EA5E9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.play_circle_fill, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
